-module(bankai_rules_ffi).
-export([
    init/1, reset_workspace/1,
    register/4, get/2, list/1,
    set_approval/3, is_approved/2,
    append_audit/10, list_audit/2
]).

%% Rule artifacts, local trust, and audit events are deliberately separate.
%% A portable source artifact is never an executable permission grant.
-define(ARTIFACTS, bankai_rule_artifacts_v1).
-define(APPROVALS, bankai_rule_approvals_v1).
-define(AUDITS, bankai_rule_audits_v1).

init(_Workspace) ->
    ensure_table(?ARTIFACTS, [key, workspace, hash, name, source]),
    ensure_table(?APPROVALS, [key, workspace, hash, approved]),
    ensure_table(?AUDITS, [key, workspace, sequence, hash, caller,
                           input_hash, task_id, task_hash, duration_ns,
                           outcome, result]),
    case mnesia:wait_for_tables([?ARTIFACTS, ?APPROVALS, ?AUDITS], 5000) of
        ok -> {ok, nil};
        {timeout, Bad} -> {error, format("rule table timeout: ~p", [Bad])}
    end.

reset_workspace(Workspace) -> transaction(fun() ->
    delete_rows(?ARTIFACTS, {?ARTIFACTS, '_', Workspace, '_', '_', '_'}),
    delete_rows(?APPROVALS, {?APPROVALS, '_', Workspace, '_', '_'}),
    delete_rows(?AUDITS, {?AUDITS, '_', Workspace, '_', '_', '_', '_', '_', '_', '_', '_', '_'}),
    {ok, nil}
end).

register(Workspace, Hash, Name, Source) -> transaction(fun() ->
    Key = {Workspace, Hash},
    case mnesia:read(?ARTIFACTS, Key, write) of
        [] ->
            mnesia:write({?ARTIFACTS, Key, Workspace, Hash, Name, Source}),
            {ok, nil};
        [{?ARTIFACTS, Key, Workspace, Hash, _SavedName, Source}] ->
            %% Same content hash/source is an idempotent register. Preserve the
            %% original display name so replay cannot rewrite artifact metadata.
            {ok, nil};
        [{?ARTIFACTS, Key, Workspace, Hash, _SavedName, _OtherSource}] ->
            {error, <<"rule hash collision: ", Hash/binary>>}
    end
end).

get(Workspace, Hash) -> transaction(fun() ->
    Key = {Workspace, Hash},
    case mnesia:read(?ARTIFACTS, Key, read) of
        [{?ARTIFACTS, Key, Workspace, Hash, Name, Source}] ->
            {ok, {Name, Source}};
        [] -> {error, <<"no such rule: ", Hash/binary>>}
    end
end).

list(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?ARTIFACTS, '_', Workspace, '_', '_', '_'}),
    Result = lists:sort([
        {Hash, Name, approval_in_transaction(Workspace, Hash)}
        || {?ARTIFACTS, _Key, _WorkspaceRow, Hash, Name, _Source} <- Rows
    ]),
    {ok, Result}
end).

set_approval(Workspace, Hash, Approved) -> transaction(fun() ->
    ArtifactKey = {Workspace, Hash},
    case mnesia:read(?ARTIFACTS, ArtifactKey, read) of
        [] -> {error, <<"no such rule: ", Hash/binary>>};
        _ ->
            Key = {Workspace, Hash},
            mnesia:write({?APPROVALS, Key, Workspace, Hash, Approved}),
            {ok, nil}
    end
end).

is_approved(Workspace, Hash) -> transaction(fun() ->
    {ok, approval_in_transaction(Workspace, Hash)}
end).

append_audit(Workspace, Hash, Caller, InputHash, TaskId, TaskHash,
             DurationNs, Outcome, Result, _Reserved) -> transaction(fun() ->
    Sequence = erlang:unique_integer([monotonic, positive]),
    Key = {Workspace, Sequence},
    mnesia:write({?AUDITS, Key, Workspace, Sequence, Hash, Caller,
                  InputHash, TaskId, TaskHash, DurationNs, Outcome, Result}),
    {ok, Sequence}
end).

%% Hash may be <<>> to list the complete local audit stream. The sort is stable
%% by append sequence, never wall clock, so replay/debug output is deterministic.
list_audit(Workspace, Hash) -> transaction(fun() ->
    Rows = mnesia:match_object({?AUDITS, '_', Workspace, '_', '_', '_', '_', '_', '_', '_', '_', '_'}),
    Filtered = case Hash of
        <<>> -> Rows;
        _ -> [Row || Row = {?AUDITS, _Key, _WorkspaceRow, _Sequence, RuleHash,
                            _Caller, _InputHash, _TaskId, _TaskHash,
                            _Duration, _Outcome, _Result} <- Rows,
                       RuleHash =:= Hash]
    end,
    Sorted = lists:keysort(4, Filtered),
    {ok, [
        {Sequence, RuleHash, Caller, InputHash, TaskId, TaskHash,
         DurationNs, Outcome, Result}
        || {?AUDITS, _Key, _WorkspaceRow, Sequence, RuleHash, Caller, InputHash,
            TaskId, TaskHash, DurationNs, Outcome, Result} <- Sorted
    ]}
end).

approval_in_transaction(Workspace, Hash) ->
    Key = {Workspace, Hash},
    case mnesia:read(?APPROVALS, Key, read) of
        [{?APPROVALS, Key, Workspace, Hash, true}] -> true;
        _ -> false
    end.

delete_rows(_Table, Pattern) ->
    Rows = mnesia:match_object(Pattern),
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end, Rows),
    ok.

ensure_table(Name, Attributes) ->
    case mnesia:create_table(Name, [{attributes, Attributes}, {disc_copies, [node()]}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} ->
            case mnesia:table_info(Name, attributes) of
                Attributes -> ok;
                Actual -> throw({bankai_rule_schema_mismatch, Name, Actual})
            end;
        {aborted, Reason} -> throw({bankai_rule_table_create_failed, Name, Reason})
    end.

transaction(Fun) ->
    try mnesia:transaction(Fun) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} -> {error, format("rule transaction aborted: ~p", [Reason])}
    catch
        Class:Reason -> {error, format("rule persistence failure (~p): ~p", [Class, Reason])}
    end.

format(Template, Args) ->
    iolist_to_binary(io_lib:format(Template, Args)).
