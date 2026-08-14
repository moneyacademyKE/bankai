-module(bankai_mnesia_ffi).
-export([init/1, reset_workspace/1, current_json/1, versions_json/1, snapshot_json/1,
         projection_snapshot_rows/1, get_current/2, put_new/5, compare_and_put/6,
         compare_and_put_committed/7, replace_many/3, replace_many_idempotent/4,
         idempotent_result/3, import_if_needed/3, import_snapshot/3,
         replace_current_snapshot/2, projection_checkpoint/2,
         set_projection_checkpoint/3]).

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
    bankai_changefeed_ffi:init(),
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
    bankai_changefeed_ffi:reset_workspace(Workspace),
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
    Sorted = lists:sort(fun current_before/2, Rows),
    {ok, [Json || {?CURRENT, _, _, _, _, Json} <- Sorted]}
end).

versions_json(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?VERSIONS, '_', Workspace, '_', '_'}),
    Sorted = lists:sort(fun version_before/2, Rows),
    {ok, [Json || {?VERSIONS, _, _, _, Json} <- Sorted]}
end).

%% A snapshot is paired with the exact committed change-stream offset while the
%% read transaction is open. Consumers resume strictly after this watermark.
snapshot_json(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?CURRENT, '_', Workspace, '_', '_', '_'}),
    Watermark = bankai_changefeed_ffi:high_watermark_in_transaction(Workspace),
    Jsons = [Json || {?CURRENT, _, _, _, _, Json} <-
                       lists:sort(fun current_before/2, Rows)],
    {ok, <<"{\"offset\":", (integer_to_binary(Watermark))/binary,
          ",\"tasks\":[", (join_json(Jsons))/binary, "]}">>}
end).

%% Paired current-head snapshot plus exact stream watermark for the daemon's
%% rebuildable AaronDB projections. This is one Mnesia read transaction.
projection_snapshot_rows(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?CURRENT, '_', Workspace, '_', '_', '_'}),
    Watermark = bankai_changefeed_ffi:high_watermark_in_transaction(Workspace),
    {ok, {Watermark, [Json || {?CURRENT, _, _, _, _, Json} <-
                              lists:sort(fun current_before/2, Rows)]}}
end).

projection_checkpoint(Workspace, Projection) -> transaction(fun() ->
    Key = {Workspace, <<"projection:", Projection/binary>>},
    case mnesia:read(?META, Key, read) of
        [] -> {ok, -1};
        [{?META, Key, Workspace, _Name, Offset}] -> {ok, Offset}
    end
end).

set_projection_checkpoint(Workspace, Projection, Offset) -> transaction(fun() ->
    Key = {Workspace, <<"projection:", Projection/binary>>},
    mnesia:write({?META, Key, Workspace, <<"projection:", Projection/binary>>, Offset}),
    {ok, nil}
end).

get_current(Workspace, Id) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, read) of
        [{?CURRENT, Key, Workspace, Id, _Hash, Json}] -> {ok, Json};
        [] -> {error, <<"no such task: ", Id/binary>>}
    end
end).

put_new(Workspace, Id, Hash, Json, Operation) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [] ->
            write_version_and_current(Workspace, Id, Hash, Json),
            record_change(Workspace, Operation, [{Id, <<"none">>, Hash}]),
            {ok, Json};
        _ -> {error, <<"task already exists: ", Id/binary>>}
    end
end).

compare_and_put(Workspace, Id, ExpectedHash, Hash, Json, Operation) -> transaction(fun() ->
    compare_and_put_row(Workspace, Id, ExpectedHash, Hash, Json, Operation)
end).

%% Cluster command application is exactly-once by the committed command identity.
%% The command journal and task/version CAS live in one Mnesia transaction, so a
%% daemon crash can only retry the same accepted command, never publish a partial
%% head advance. The journal uses Bankai meta because it is authority metadata,
%% not an AaronDB projection.
compare_and_put_committed(Workspace, CommandId, Id, ExpectedHash, Hash, Json, Operation) ->
    transaction(fun() ->
        Key = {Workspace, <<"cluster-command:", CommandId/binary>>},
        case mnesia:read(?META, Key, write) of
            [{?META, Key, Workspace, _Name, SavedJson}] -> {ok, SavedJson};
            [] ->
                case compare_and_put_row(Workspace, Id, ExpectedHash, Hash, Json, Operation) of
                    {ok, AppliedJson} ->
                        mnesia:write({?META, Key, Workspace,
                                      <<"cluster-command:", CommandId/binary>>, AppliedJson}),
                        {ok, AppliedJson};
                    Error -> Error
                end
        end
    end).

compare_and_put_row(Workspace, Id, ExpectedHash, Hash, Json, Operation) ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [{?CURRENT, Key, Workspace, Id, ExpectedHash, _}] ->
            write_version_and_current(Workspace, Id, Hash, Json),
            record_change(Workspace, Operation, [{Id, ExpectedHash, Hash}]),
            {ok, Json};
        [{?CURRENT, Key, Workspace, Id, _Actual, _}] ->
            {error, <<"task changed concurrently: ", Id/binary>>};
        [] -> {error, <<"no such task: ", Id/binary>>}
    end.

write_version_and_current(Workspace, Id, Hash, Json) ->
    VersionKey = {Workspace, Hash},
    case mnesia:read(?VERSIONS, VersionKey, write) of
        [] -> mnesia:write({?VERSIONS, VersionKey, Workspace, Hash, Json});
        _ -> ok
    end,
    mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json}).

%% Atomically compare-and-swap a planned set of current heads. Each row is
%% {Id, ExpectedHash, NewHash, Json}; validate all heads before writing any row.
replace_many(Workspace, Rows, Operation) -> transaction(fun() ->
    apply_replacements(Workspace, Rows, Operation)
end).

%% Read-only idempotency lookup. Returning the saved fingerprint and summary
%% lets callers short-circuit before re-planning against heads that the original
%% command already advanced.
idempotent_result(Workspace, IdempotencyKey, Namespace) -> transaction(fun() ->
    Key = {Workspace, <<Namespace/binary, ":", IdempotencyKey/binary>>},
    case mnesia:read(?META, Key, read) of
        [{?META, Key, Workspace, _Name, {Fingerprint, Summary}}] ->
            {ok, {some, {Fingerprint, Summary}}};
        [] -> {ok, none}
    end
end).

%% Local batch idempotency lives in the same Mnesia transaction as validation,
%% head/version writes, and the committed-change event. A repeated key returns
%% the original summary; a reused key with different canonical request data is
%% rejected rather than silently applying a different batch.
replace_many_idempotent(Workspace, IdempotencyKey, Fingerprint, Rows) ->
    transaction(fun() ->
        Key = {Workspace, <<"batch-command:", IdempotencyKey/binary>>},
        case mnesia:read(?META, Key, write) of
            [{?META, Key, Workspace, _Name, Saved}] ->
                case Saved of
                    {Fingerprint, Summary} -> {ok, Summary};
                    _ -> {error, <<"idempotency key already used with different batch">>}
                end;
            [] ->
                case apply_replacements(Workspace, Rows, <<"batch">>) of
                    {ok, nil} ->
                        Summary = iolist_to_binary(io_lib:format(
                            "applied ~B mutation(s)", [length(Rows)])),
                        mnesia:write({?META, Key, Workspace,
                                      <<"batch-command:", IdempotencyKey/binary>>,
                                      {Fingerprint, Summary}}),
                        {ok, Summary};
                    Error -> Error
                end
        end
    end).

apply_replacements(Workspace, Rows, Operation) ->
    case validate_replacements(Workspace, Rows) of
        ok ->
            lists:foreach(fun({Id, _ExpectedHash, Hash, Json}) ->
                write_version_and_current(Workspace, Id, Hash, Json)
            end, Rows),
            record_change(Workspace, Operation, [
                {Id, ExpectedHash, Hash} || {Id, ExpectedHash, Hash, _Json} <- Rows
            ]),
            {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

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
    Missing = lists:filter(fun({Id, _Hash, _Json}) ->
        mnesia:read(?CURRENT, {Workspace, Id}, write) =:= []
    end, Current),
    lists:foreach(fun({Id, Hash, Json}) ->
        mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json})
    end, Missing),
    case Missing of
        [] -> ok;
        _ -> record_change(Workspace, <<"import">>, [
            {Id, <<"none">>, Hash} || {Id, Hash, _Json} <- Missing
        ])
    end,
    {ok, nil}
end).

%% Archival changes the active view only; version rows remain immutable and
%% addressable so inspect/history never lose provenance.
replace_current_snapshot(Workspace, Current) -> transaction(fun() ->
    Existing = mnesia:match_object({?CURRENT, '_', Workspace, '_', '_', '_'}),
    delete_workspace_rows(?CURRENT, Workspace),
    lists:foreach(fun({Id, Hash, Json}) ->
        mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json})
    end, Current),
    case (Existing == []) andalso (Current == []) of
        true -> ok;
        false -> record_change(Workspace, <<"compact">>, [
            {Id, <<"snapshot">>, Hash} || {Id, Hash, _Json} <- Current
        ])
    end,
    {ok, nil}
end).

import_if_needed(Workspace, Versions, Current) -> transaction(fun() ->
    MetaKey = {Workspace, legacy_jsonl_import_v1},
    case mnesia:read(?META, MetaKey, write) of
        [] ->
            import_snapshot_rows(Workspace, Versions, Current),
            mnesia:write({?META, MetaKey, Workspace, legacy_jsonl_import_v1, done}),
            case Current of
                [] -> ok;
                _ -> record_change(Workspace, <<"legacy-import">>, [
                    {Id, <<"none">>, Hash} || {Id, Hash, _Json} <- Current
                ])
            end,
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

record_change(_Workspace, _Operation, []) -> ok;
record_change(Workspace, Operation, Rows) ->
    bankai_changefeed_ffi:record_in_transaction(Workspace, Operation, Rows),
    ok.

current_before({?CURRENT, _, _, IdA, _, _},
               {?CURRENT, _, _, IdB, _, _}) -> IdA < IdB.

version_before({?VERSIONS, _, _, HashA, _},
               {?VERSIONS, _, _, HashB, _}) -> HashA < HashB.

join_json([]) -> <<>>;
join_json([Json]) -> Json;
join_json([Json | Rest]) -> <<Json/binary, ",", (join_json(Rest))/binary>>.

transaction(F) ->
    try mnesia:transaction(F) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} -> {error, iolist_to_binary(io_lib:format("mnesia transaction aborted: ~p", [Reason]))}
    catch
        Class:Reason -> {error, iolist_to_binary(io_lib:format("mnesia failure (~p): ~p", [Class, Reason]))}
    end.
