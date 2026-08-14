-module(bankai_gate_wisps_ffi).
-export([
    init/1, reset_workspace/1,
    resolve_gate/9, gate_audits/2,
    apply_verified_fact/8, valid_facts/3,
    create_wisp/5, get_wisp_metadata/2,
    transition_wisp/8, burn_wisps/6, wisp_archives/2
]).

-define(GATE_AUDITS, bankai_gate_audits_v1).
-define(GATE_FACTS, bankai_gate_facts_v1).
-define(GATE_FACT_SIGS, bankai_gate_fact_signatures_v1).
-define(WISP_META, bankai_wisp_meta_v1).
-define(WISP_ARCHIVE, bankai_wisp_archive_v1).
-define(META, bankai_gate_wisp_meta_v1).
-define(CURRENT, bankai_current_v2).
-define(VERSIONS, bankai_versions_v2).

init(_Workspace) ->
    ensure_table(?GATE_AUDITS,
                 [key, workspace, sequence, gate_id, action, actor,
                  reason, resolved_hash, at]),
    ensure_table(?GATE_FACTS,
                 [key, workspace, signature, gate_id, issuer, state,
                  observed_at, expires_at, wire]),
    ensure_table(?GATE_FACT_SIGS,
                 [key, workspace, signature, gate_id]),
    ensure_table(?WISP_META,
                 [key, workspace, wisp_id, expires_at]),
    ensure_table(?WISP_ARCHIVE,
                 [key, workspace, sequence, wisp_id, action, actor,
                  reason, task_hash, task_json, at]),
    ensure_required_table(?CURRENT, [key, workspace, id, hash, json]),
    ensure_required_table(?VERSIONS, [key, workspace, hash, json]),
    ensure_table(?META, [key, workspace, name, value]),
    Tables = [?GATE_AUDITS, ?GATE_FACTS, ?GATE_FACT_SIGS,
              ?WISP_META, ?WISP_ARCHIVE, ?META, ?CURRENT, ?VERSIONS],
    case mnesia:wait_for_tables(Tables, 5000) of
        ok -> {ok, nil};
        {timeout, Bad} -> {error, format("gate/wisp table timeout: ~p", [Bad])}
    end.

reset_workspace(Workspace) -> transaction(fun() ->
    delete_rows({?GATE_AUDITS, '_', Workspace, '_', '_', '_', '_', '_', '_', '_'}),
    delete_rows({?GATE_FACTS, '_', Workspace, '_', '_', '_', '_', '_', '_', '_'}),
    delete_rows({?GATE_FACT_SIGS, '_', Workspace, '_', '_', '_'}),
    delete_rows({?WISP_META, '_', Workspace, '_', '_'}),
    delete_rows({?WISP_ARCHIVE, '_', Workspace, '_', '_', '_', '_', '_', '_', '_', '_'}),
    delete_rows({?META, '_', Workspace, '_', '_'}),
    {ok, nil}
end).

%% Gate-head mutation, immutable version, audit, and committed change are one
%% transaction. The caller computes canonical task bytes and supplies a CAS hash.
resolve_gate(Workspace, GateId, ExpectedHash, NewHash, NewJson,
             Action, Actor, Reason, At) -> transaction(fun() ->
    case current_for_update(Workspace, GateId, ExpectedHash) of
        {ok, _OldJson} ->
            write_version_and_current(Workspace, GateId, NewHash, NewJson),
            Sequence = write_gate_audit(Workspace, GateId, Action, Actor,
                                        Reason, NewHash, At),
            bankai_changefeed_ffi:record_in_transaction(
              Workspace, <<"gate-resolve">>, [{GateId, ExpectedHash, NewHash}]),
            {ok, Sequence};
        Error -> Error
    end
end).

write_gate_audit(Workspace, GateId, Action, Actor, Reason, ResolvedHash, At) ->
    Sequence = next_sequence(Workspace, gate_audit_sequence),
    Key = {Workspace, Sequence},
    mnesia:write({?GATE_AUDITS, Key, Workspace, Sequence, GateId,
                  Action, Actor, Reason, ResolvedHash, At}),
    Sequence.

gate_audits(Workspace, GateId) -> transaction(fun() ->
    Rows = mnesia:match_object(
             {?GATE_AUDITS, '_', Workspace, '_', '_', '_', '_', '_', '_', '_'}),
    Filtered = [Row || Row = {?GATE_AUDITS, _Key, _Workspace, _Sequence,
                              SavedGateId, _Action, _Actor, _Reason,
                              _ResolvedHash, _At} <- Rows,
                       GateId =:= <<>> orelse SavedGateId =:= GateId],
    Result = [{Sequence, SavedGateId, Action, Actor, Reason, ResolvedHash, At}
              || {?GATE_AUDITS, _Key, _Workspace, Sequence, SavedGateId,
                  Action, Actor, Reason, ResolvedHash, At} <- Filtered],
    {ok, lists:keysort(1, Result)}
end).

%% Verification is deliberately outside this persistence module. This function
%% accepts the verified Fact fields and atomically replay-marks the signature,
%% stores the evidence, advances the gate head, audits it, and emits the change.
apply_verified_fact(Workspace, GateId, ExpectedHash, NewHead,
                    {Signature, Issuer, State, ObservedAt, ExpiresAt},
                    Wire, Reason, At) -> transaction(fun() ->
    SignatureKey = {Workspace, Signature},
    case mnesia:read(?GATE_FACT_SIGS, SignatureKey, write) of
        [{?GATE_FACT_SIGS, SignatureKey, Workspace, Signature, GateId}] ->
            {ok, {false, 0}};
        [{?GATE_FACT_SIGS, SignatureKey, Workspace, Signature, _OtherGate}] ->
            {error, <<"gate fact signature already bound to another gate">>};
        [] ->
            case current_for_update(Workspace, GateId, ExpectedHash) of
                {ok, _OldJson} ->
                    {NewHash, NewJson} = NewHead,
                    FactKey = {Workspace, GateId, Signature},
                    mnesia:write({?GATE_FACTS, FactKey, Workspace, Signature,
                                  GateId, Issuer, State, ObservedAt,
                                  ExpiresAt, Wire}),
                    mnesia:write({?GATE_FACT_SIGS, SignatureKey, Workspace,
                                  Signature, GateId}),
                    case NewHash =:= ExpectedHash of
                        true -> ok;
                        false -> write_version_and_current(
                                   Workspace, GateId, NewHash, NewJson)
                    end,
                    Sequence = write_gate_audit(
                      Workspace, GateId, <<"signed_fact">>, Issuer,
                      Reason, NewHash, At),
                    case NewHash =:= ExpectedHash of
                        true -> ok;
                        false -> bankai_changefeed_ffi:record_in_transaction(
                                   Workspace, <<"gate-fact">>,
                                   [{GateId, ExpectedHash, NewHash}])
                    end,
                    {ok, {true, Sequence}};
                Error -> Error
            end
    end
end).

valid_facts(Workspace, GateId, Now) -> transaction(fun() ->
    Rows = mnesia:match_object(
             {?GATE_FACTS, '_', Workspace, '_', GateId, '_', '_', '_', '_', '_'}),
    Valid = [Row || Row = {?GATE_FACTS, _Key, _Workspace, _Signature, _GateId,
                           _Issuer, State, ObservedAt, ExpiresAt, _Wire} <- Rows,
                    State =:= satisfied orelse State =:= <<"satisfied">>,
                    ObservedAt =< Now, ExpiresAt > Now],
    Sorted = lists:sort(fun fact_before/2, Valid),
    {ok, [{Signature, Issuer, State, ObservedAt, ExpiresAt, Wire}
          || {?GATE_FACTS, _Key, _Workspace, Signature, _GateId,
              Issuer, State, ObservedAt, ExpiresAt, Wire} <- Sorted]}
end).

fact_before(A, B) ->
    {?GATE_FACTS, _, _, SignatureA, _, IssuerA, _, ObservedA, ExpiresA, _} = A,
    {?GATE_FACTS, _, _, SignatureB, _, IssuerB, _, ObservedB, ExpiresB, _} = B,
    {ObservedA, ExpiresA, IssuerA, SignatureA} <
        {ObservedB, ExpiresB, IssuerB, SignatureB}.

%% Wisp creation and optional TTL metadata share the initial authoritative
%% version/current-head transaction.
create_wisp(Workspace, Id, Hash, Json, Expiry) -> transaction(fun() ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [] ->
            write_version_and_current(Workspace, Id, Hash, Json),
            write_expiry(Workspace, Id, Expiry),
            bankai_changefeed_ffi:record_in_transaction(
              Workspace, <<"wisp-create">>, [{Id, <<"none">>, Hash}]),
            {ok, Json};
        _ -> {error, <<"task already exists: ", Id/binary>>}
    end
end).

get_wisp_metadata(Workspace, WispId) -> transaction(fun() ->
    case mnesia:read(?WISP_META, {Workspace, WispId}, read) of
        [{?WISP_META, _Key, Workspace, WispId, ExpiresAt}] ->
            {ok, {some, ExpiresAt}};
        [] -> {ok, none}
    end
end).

%% Promotion archives the exact prior canonical head before installing the new
%% normal-task head. Metadata removal, versioning, audit, and change are atomic.
transition_wisp(Workspace, Id, ExpectedHash, NewHash, NewJson,
                Actor, Reason, At) -> transaction(fun() ->
    case current_for_update(Workspace, Id, ExpectedHash) of
        {ok, OldJson} ->
            Sequence = write_wisp_archive(Workspace, Id, <<"promote">>,
                                          Actor, Reason, ExpectedHash,
                                          OldJson, At),
            write_version_and_current(Workspace, Id, NewHash, NewJson),
            mnesia:delete(?WISP_META, {Workspace, Id}, write),
            bankai_changefeed_ffi:record_in_transaction(
              Workspace, <<"wisp-promote">>, [{Id, ExpectedHash, NewHash}]),
            {ok, Sequence};
        Error -> Error
    end
end).

%% Rows are {Id, ExpectedHash, ExpectedExpiry}. ExpectedExpiry = -1 means an
%% explicit burn; GC supplies the observed expiry and is revalidated at commit.
burn_wisps(Workspace, Rows, Action, Actor, Reason, At) -> transaction(fun() ->
    case validate_burn_rows(Workspace, Rows, At, sets:new()) of
        {ok, CanonicalRows} ->
            lists:foreach(fun({Id, Hash, Json}) ->
                %% Archive-first is literal inside this transaction.
                _ = write_wisp_archive(Workspace, Id, Action, Actor, Reason,
                                       Hash, Json, At),
                mnesia:delete(?CURRENT, {Workspace, Id}, write),
                mnesia:delete(?WISP_META, {Workspace, Id}, write)
            end, CanonicalRows),
            bankai_changefeed_ffi:record_in_transaction(
              Workspace, <<"wisp-burn">>,
              [{Id, Hash, <<"archived">>} || {Id, Hash, _} <- CanonicalRows]),
            {ok, length(CanonicalRows)};
        Error -> Error
    end
end).

validate_burn_rows(_Workspace, [], _At, _Seen) -> {ok, []};
validate_burn_rows(Workspace, [{Id, Hash, Expiry} | Rest], At, Seen) ->
    case sets:is_element(Id, Seen) of
        true -> {error, <<"duplicate wisp burn id: ", Id/binary>>};
        false ->
            case {current_for_update(Workspace, Id, Hash),
                  valid_burn_expiry(Workspace, Id, Expiry, At)} of
                {{ok, Json}, ok} ->
                    case validate_burn_rows(Workspace, Rest, At,
                                            sets:add_element(Id, Seen)) of
                        {ok, Rows} -> {ok, [{Id, Hash, Json} | Rows]};
                        Error -> Error
                    end;
                {Error = {error, _}, _} -> Error;
                {_, Error = {error, _}} -> Error
            end
    end.

valid_burn_expiry(_Workspace, _Id, -1, _At) -> ok;
valid_burn_expiry(Workspace, Id, ExpectedExpiry, At) ->
    case mnesia:read(?WISP_META, {Workspace, Id}, write) of
        [{?WISP_META, _Key, Workspace, Id, ExpectedExpiry}]
          when ExpectedExpiry =< At -> ok;
        [{?WISP_META, _Key, Workspace, Id, _Other}] ->
            {error, <<"wisp expiry changed concurrently: ", Id/binary>>};
        [] -> {error, <<"wisp has no expiry: ", Id/binary>>}
    end.

write_wisp_archive(Workspace, WispId, Action, Actor, Reason,
                   TaskHash, TaskJson, At) ->
    Sequence = next_sequence(Workspace, wisp_archive_sequence),
    Key = {Workspace, Sequence},
    mnesia:write({?WISP_ARCHIVE, Key, Workspace, Sequence, WispId,
                  Action, Actor, Reason, TaskHash, TaskJson, At}),
    Sequence.

wisp_archives(Workspace, WispId) -> transaction(fun() ->
    Rows = mnesia:match_object(
             {?WISP_ARCHIVE, '_', Workspace, '_', '_', '_', '_', '_', '_', '_', '_'}),
    Filtered = [Row || Row = {?WISP_ARCHIVE, _Key, _Workspace, _Sequence,
                              SavedWispId, _Action, _Actor, _Reason,
                              _TaskHash, _TaskJson, _At} <- Rows,
                       WispId =:= <<>> orelse SavedWispId =:= WispId],
    Result = [{Sequence, SavedWispId, Action, Actor, Reason, TaskHash, TaskJson, At}
              || {?WISP_ARCHIVE, _Key, _Workspace, Sequence, SavedWispId,
                  Action, Actor, Reason, TaskHash, TaskJson, At} <- Filtered],
    {ok, lists:keysort(1, Result)}
end).

current_for_update(Workspace, Id, ExpectedHash) ->
    Key = {Workspace, Id},
    case mnesia:read(?CURRENT, Key, write) of
        [{?CURRENT, Key, Workspace, Id, ExpectedHash, Json}] -> {ok, Json};
        [{?CURRENT, Key, Workspace, Id, _Actual, _Json}] ->
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

write_expiry(_Workspace, _Id, none) -> ok;
write_expiry(Workspace, Id, {some, ExpiresAt}) ->
    Key = {Workspace, Id},
    mnesia:write({?WISP_META, Key, Workspace, Id, ExpiresAt}).

next_sequence(Workspace, Name) ->
    Key = {Workspace, Name},
    case mnesia:read(?META, Key, write) of
        [] ->
            mnesia:write({?META, Key, Workspace, Name, 2}),
            1;
        [{?META, Key, Workspace, Name, Next}] ->
            mnesia:write({?META, Key, Workspace, Name, Next + 1}),
            Next
    end.

delete_rows(Pattern) ->
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end,
                  mnesia:match_object(Pattern)).

ensure_required_table(Name, Attributes) ->
    try mnesia:table_info(Name, attributes) of
        Attributes -> ok;
        Actual -> throw({bankai_gate_wisp_schema_mismatch, Name, Actual})
    catch
        exit:_ -> throw({bankai_gate_wisp_missing_task_table, Name})
    end.

ensure_table(Name, Attributes) ->
    case mnesia:create_table(Name, [{attributes, Attributes},
                                    {disc_copies, [node()]}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} ->
            case mnesia:table_info(Name, attributes) of
                Attributes -> ok;
                Actual -> throw({bankai_gate_wisp_schema_mismatch, Name, Actual})
            end;
        {aborted, Reason} ->
            throw({bankai_gate_wisp_table_create_failed, Name, Reason})
    end.

transaction(Fun) ->
    try mnesia:transaction(Fun) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} ->
            {error, format("gate/wisp transaction aborted: ~p", [Reason])}
    catch
        Class:Reason ->
            {error, format("gate/wisp persistence failure (~p): ~p",
                           [Class, Reason])}
    end.

format(Template, Args) ->
    iolist_to_binary(io_lib:format(Template, Args)).
