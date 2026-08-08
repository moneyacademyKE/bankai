-module(bankai_mnesia_ffi).
-export([init/1, reset_workspace/1, current_json/1, versions_json/1, get_current/2,
         put_new/4, compare_and_put/5, replace_many/2, import_if_needed/3,
         import_snapshot/3, replace_current_snapshot/2]).

%% Versioned table names are intentional. The abandoned v1 schema keyed records
%% by workspace alone, which could retain only one task per workspace. Leaving
%% those tables untouched avoids destructive "migration"; v2 has composite
%% keys and is the only schema this release reads or writes.
-define(CURRENT, bankai_current_v2).
-define(VERSIONS, bankai_versions_v2).
-define(META, bankai_meta_v2).

init(_Workspace) ->
    case mnesia:system_info(is_running) of
        yes -> ok;
        _ ->
            case mnesia:create_schema([node()]) of
                ok -> ok;
                {error, {_, {already_exists, _}}} -> ok;
                {error, {already_exists, _}} -> ok;
                _ -> ok
            end,
            case application:ensure_all_started(mnesia) of
                {ok, _} -> ok;
                {error, Reason} -> throw({mnesia_start_failed, Reason})
            end
    end,
    ensure_table(?CURRENT, [key, workspace, id, hash, json]),
    ensure_table(?VERSIONS, [key, workspace, hash, json]),
    ensure_table(?META, [key, workspace, name, value]),
    case mnesia:wait_for_tables([?CURRENT, ?VERSIONS, ?META], 5000) of
        ok -> {ok, nil};
        {timeout, Bad} -> {error, iolist_to_binary(io_lib:format("mnesia table timeout: ~p", [Bad]))}
    end.

%% Test-only workspace cleanup. It is intentionally scoped to one workspace
%% and removes no schema/table data, so parallel test workspaces stay isolated.
reset_workspace(Workspace) -> transaction(fun() ->
    delete_workspace_rows(?CURRENT, Workspace),
    delete_workspace_rows(?VERSIONS, Workspace),
    delete_workspace_rows(?META, Workspace),
    {ok, nil}
end).

delete_workspace_rows(?CURRENT, Workspace) ->
    Rows = mnesia:match_object({?CURRENT, '_', Workspace, '_', '_', '_'}),
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end, Rows);
delete_workspace_rows(Table, Workspace) ->
    Rows = mnesia:match_object({Table, '_', Workspace, '_', '_'}),
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end, Rows).

ensure_table(Name, Attributes) ->
    case mnesia:create_table(Name, [{attributes, Attributes}, {disc_copies, [node()]}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} ->
            case mnesia:table_info(Name, attributes) of
                Attributes -> ok;
                Actual -> throw({bankai_schema_mismatch, Name, Actual})
            end;
        {aborted, Reason} -> throw({bankai_table_create_failed, Name, Reason})
    end.

current_json(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?CURRENT, '_', Workspace, '_', '_', '_'}),
    {ok, [Json || {?CURRENT, _, _, _, _, Json} <- Rows]}
end).

versions_json(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?VERSIONS, '_', Workspace, '_', '_'}),
    {ok, [Json || {?VERSIONS, _, _, _, Json} <- Rows]}
end).

get_current(Workspace, Id) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, read) of
        [{?CURRENT, Key, Workspace, Id, _Hash, Json}] -> {ok, Json};
        [] -> {error, <<"no such task: ", Id/binary>>}
    end
end).

put_new(Workspace, Id, Hash, Json) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [] -> write_version_and_current(Workspace, Id, Hash, Json), {ok, Json};
        _ -> {error, <<"task already exists: ", Id/binary>>}
    end
end).

compare_and_put(Workspace, Id, ExpectedHash, Hash, Json) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [{?CURRENT, Key, Workspace, Id, ExpectedHash, _}] ->
            write_version_and_current(Workspace, Id, Hash, Json), {ok, Json};
        [{?CURRENT, Key, Workspace, Id, _Actual, _}] ->
            {error, <<"task changed concurrently: ", Id/binary>>};
        [] -> {error, <<"no such task: ", Id/binary>>}
    end
end).


write_version_and_current(Workspace, Id, Hash, Json) ->
    VersionKey = {Workspace, Hash},
    case mnesia:read(?VERSIONS, VersionKey, write) of
        [] -> mnesia:write({?VERSIONS, VersionKey, Workspace, Hash, Json});
        _ -> ok
    end,
    mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json}).


%% Atomically compare-and-swap a planned set of current heads. Each row is
%% {Id, ExpectedHash, NewHash, Json}; validate all heads before writing any row.
replace_many(Workspace, Rows) -> transaction(fun() ->
    case validate_replacements(Workspace, Rows) of
        ok ->
            lists:foreach(fun({Id, _ExpectedHash, Hash, Json}) ->
                write_version_and_current(Workspace, Id, Hash, Json)
            end, Rows),
            {ok, nil};
        {error, Reason} -> {error, Reason}
    end
end).

validate_replacements(_Workspace, []) -> ok;
validate_replacements(Workspace, [{Id, ExpectedHash, _Hash, _Json} | Rest]) ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [{?CURRENT, Key, Workspace, Id, ExpectedHash, _}] ->
            validate_replacements(Workspace, Rest);
        [{?CURRENT, Key, Workspace, Id, _Actual, _}] ->
            {error, <<"task changed concurrently: ", Id/binary>>};
        [] -> {error, <<"no such task: ", Id/binary>>}
    end.

%% Import is deliberately a union of immutable versions. The Gleam boundary
%% validates the whole snapshot and rejects divergent heads before this
%% transaction begins. Existing heads win; missing IDs get the incoming head.
import_snapshot(Workspace, Versions, Current) -> transaction(fun() ->
    lists:foreach(fun({_Id, Hash, Json}) ->
        VersionKey = {Workspace, Hash},
        case mnesia:read(?VERSIONS, VersionKey, write) of
            [] -> mnesia:write({?VERSIONS, VersionKey, Workspace, Hash, Json});
            _ -> ok
        end
    end, Versions),
    lists:foreach(fun({Id, Hash, Json}) ->
        CurrentKey = {Workspace, Id},
        case mnesia:read(?CURRENT, CurrentKey, write) of
            [] -> mnesia:write({?CURRENT, CurrentKey, Workspace, Id, Hash, Json});
            _ -> ok
        end
    end, Current),
    {ok, nil}
end).


%% Archival changes the active view only; version rows remain immutable and
%% addressable so inspect/history never lose provenance.
replace_current_snapshot(Workspace, Current) -> transaction(fun() ->
    delete_workspace_rows(?CURRENT, Workspace),
    lists:foreach(fun({Id, Hash, Json}) ->
        mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json})
    end, Current),
    {ok, nil}
end).

import_if_needed(Workspace, Versions, Current) -> transaction(fun() ->
    MetaKey = {Workspace, legacy_jsonl_import_v1},
    case mnesia:read(?META, MetaKey, write) of
        [] ->
            import_snapshot_rows(Workspace, Versions, Current),
            mnesia:write({?META, MetaKey, Workspace, legacy_jsonl_import_v1, done}),
            {ok, nil};
        _ -> {ok, nil}
    end
end).

import_snapshot_rows(Workspace, Versions, Current) ->
    lists:foreach(fun({_Id, Hash, Json}) ->
        VersionKey = {Workspace, Hash},
        case mnesia:read(?VERSIONS, VersionKey, write) of
            [] -> mnesia:write({?VERSIONS, VersionKey, Workspace, Hash, Json});
            _ -> ok
        end
    end, Versions),
    lists:foreach(fun({Id, Hash, Json}) ->
        mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json})
    end, Current).

transaction(F) ->
    try mnesia:transaction(F) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} -> {error, iolist_to_binary(io_lib:format("mnesia transaction aborted: ~p", [Reason]))}
    catch
        Class:Reason -> {error, iolist_to_binary(io_lib:format("mnesia failure (~p): ~p", [Class, Reason]))}
    end.
