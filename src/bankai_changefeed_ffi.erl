-module(bankai_changefeed_ffi).
-export([
    init/0,
    reset_workspace/1,
    record_in_transaction/3,
    high_watermark_in_transaction/1,
    tail_json/2
]).

%% Bankai's committed change source. These tables are owned by Bankai, not by
%% AaronDB: task-head changes and event records share the caller's Mnesia
%% transaction, while AaronDB consumes the resulting ordered projection source.
-define(CHANGES, bankai_changes_v1).
-define(EVENT_IDS, bankai_change_ids_v1).
-define(META, bankai_change_meta_v1).

init() ->
    ensure_table(?CHANGES,
                 [key, workspace, offset, event_id, operation,
                  task_ids, preconditions, affected_hashes]),
    ensure_table(?EVENT_IDS, [key, workspace, event_id, offset]),
    ensure_table(?META, [key, workspace, name, value]),
    case mnesia:wait_for_tables([?CHANGES, ?EVENT_IDS, ?META], 5000) of
        ok -> ok;
        {timeout, Bad} -> throw({bankai_changefeed_timeout, Bad})
    end.

reset_workspace(Workspace) ->
    delete_workspace_rows(?CHANGES, Workspace),
    delete_workspace_rows(?EVENT_IDS, Workspace),
    delete_workspace_rows(?META, Workspace).

%% Must be called from the same Mnesia transaction as the authoritative task
%% mutation. Retried commands are identified by a deterministic canonical key;
%% an already-recorded command leaves the offset and durable event stream intact.
record_in_transaction(Workspace, Operation, Rows) ->
    EventId = event_id(Operation, Rows),
    IdKey = {Workspace, EventId},
    case mnesia:read(?EVENT_IDS, IdKey, write) of
        [_] -> duplicate;
        [] ->
            Offset = next_offset(Workspace),
            {Ids, Preconditions, Hashes} = split_rows(Rows),
            mnesia:write({?CHANGES, {Workspace, Offset}, Workspace, Offset,
                          EventId, Operation, Ids, Preconditions, Hashes}),
            mnesia:write({?EVENT_IDS, IdKey, Workspace, EventId, Offset}),
            {recorded, Offset}
    end.

high_watermark_in_transaction(Workspace) ->
    case mnesia:read(?META, {Workspace, change_offset_v1}, read) of
        [] -> -1;
        [{?META, _, Workspace, change_offset_v1, Next}] -> Next - 1
    end.

tail_json(Workspace, After) ->
    transaction(fun() ->
        Rows = mnesia:match_object({?CHANGES, '_', Workspace, '_', '_', '_', '_', '_', '_'}),
        Ordered = lists:keysort(4, [Row || Row = {?CHANGES, _, _, Offset, _, _, _, _, _} <- Rows,
                                         Offset > After]),
        {ok, [event_json(Row) || Row <- Ordered]}
    end).

ensure_table(Name, Attributes) ->
    case mnesia:create_table(Name, [{attributes, Attributes}, {disc_copies, [node()]}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} ->
            case mnesia:table_info(Name, attributes) of
                Attributes -> ok;
                Actual -> throw({bankai_changefeed_schema_mismatch, Name, Actual})
            end;
        {aborted, Reason} -> throw({bankai_changefeed_table_create_failed, Name, Reason})
    end.

delete_workspace_rows(Table, Workspace) ->
    Width = case Table of
        ?CHANGES -> {?CHANGES, '_', Workspace, '_', '_', '_', '_', '_', '_'};
        ?EVENT_IDS -> {?EVENT_IDS, '_', Workspace, '_', '_'};
        ?META -> {?META, '_', Workspace, '_', '_'}
    end,
    Rows = mnesia:match_object(Width),
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end, Rows).

next_offset(Workspace) ->
    Key = {Workspace, change_offset_v1},
    case mnesia:read(?META, Key, write) of
        [] ->
            mnesia:write({?META, Key, Workspace, change_offset_v1, 1}),
            0;
        [{?META, Key, Workspace, change_offset_v1, Next}] ->
            mnesia:write({?META, Key, Workspace, change_offset_v1, Next + 1}),
            Next
    end.

split_rows(Rows) ->
    lists:foldr(fun({Id, Precondition, Hash}, {Ids, Preconditions, Hashes}) ->
        {[Id | Ids], [Precondition | Preconditions], [Hash | Hashes]}
    end, {[], [], []}, Rows).

event_id(Operation, Rows) ->
    iolist_to_binary([
        <<"bankai-change-v1|">>, frame(Operation),
        [ [frame(Id), frame(Precondition), frame(Hash)] || {Id, Precondition, Hash} <- Rows ]
    ]).

frame(Value) -> [integer_to_binary(byte_size(Value)), <<":">>, Value].

event_json({?CHANGES, _Key, _Workspace, Offset, EventId, Operation,
            Ids, Preconditions, Hashes}) ->
    iolist_to_binary([
        <<"{\"offset\":">>, integer_to_binary(Offset),
        <<",\"event_id\":">>, json_string(EventId),
        <<",\"operation\":">>, json_string(Operation),
        <<",\"task_ids\":">>, json_array(Ids),
        <<",\"preconditions\":">>, json_array(Preconditions),
        <<",\"affected_hashes\":">>, json_array(Hashes), <<"}">>
    ]).

json_array(Values) -> [<<"[">>, join_json(Values), <<"]">>].

join_json([]) -> [];
join_json([Value]) -> json_string(Value);
join_json([Value | Rest]) -> [json_string(Value), <<",">>, join_json(Rest)].

json_string(Value) -> [<<"\"">>, escape_json(Value), <<"\"">>].

escape_json(Value) ->
    EscapedBackslash = binary:replace(Value, <<"\\">>, <<"\\\\">>, [global]),
    EscapedQuote = binary:replace(EscapedBackslash, <<"\"">>, <<"\\\"">>, [global]),
    EscapedNewline = binary:replace(EscapedQuote, <<"\n">>, <<"\\n">>, [global]),
    binary:replace(EscapedNewline, <<"\r">>, <<"\\r">>, [global]).

transaction(F) ->
    try mnesia:transaction(F) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} -> {error, iolist_to_binary(io_lib:format("mnesia transaction aborted: ~p", [Reason]))}
    catch
        Class:Reason -> {error, iolist_to_binary(io_lib:format("mnesia failure (~p): ~p", [Class, Reason]))}
    end.
