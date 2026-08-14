-module(bankai_replica_ffi).
-export([public_key/1, trust_peer/2, revoke_peer/2, sign_snapshot/4,
         verify_snapshot/7, mark_applied/2, record_conflict/3,
         list_conflicts/1, resolve_conflict/2, clear_conflicts/1,
         reset_identity_for_test/1, adversarial_envelope_checks_for_test/0]).

%% Bankai owns rig identity and trust material. AaronDB owns the canonical signed
%% envelope primitive. Private seeds are local files (0600); no key material is
%% exported through task JSONL or Mnesia task tables.
-define(DOMAIN, <<"bankai-replica-v2">>).
-define(MAX_FRAME, 16777216).
-define(MAX_PARENTS, 1024).

public_key(Workspace) ->
    with_seed(Workspace, fun(Seed) ->
        {ok, base64:encode(aarondb@envelope:public_key(Seed))}
    end).

trust_peer(Workspace, Public64) ->
    ensure_identity_dir(Workspace),
    with_decoded_public(Public64, fun(Public) ->
        update_key_file(trust_path(Workspace), fun(Keys) -> add_unique(Keys, Public) end)
    end).

revoke_peer(Workspace, Public64) ->
    ensure_identity_dir(Workspace),
    with_decoded_public(Public64, fun(Public) ->
        update_key_file(revoked_path(Workspace), fun(Keys) -> add_unique(Keys, Public) end)
    end).

sign_snapshot(Workspace, Payload, Parents64, Clock) when Clock >= 0 ->
    with_seed(Workspace, fun(Seed) ->
        case decode_parents(Parents64) of
            {ok, Parents} ->
                Envelope = aarondb@envelope:sign(?DOMAIN, Payload, Seed, Parents, Clock, 1),
                {envelope, _Version, Domain, Body, _Hash, Author, SignedParents,
                 LogicalClock, Epoch, Signature} = Envelope,
                {ok, iolist_to_binary([
                    <<"{\"protocol\":\"bankai-replica-v2\",\"domain\":">>, json_string(Domain),
                    <<",\"payload\":">>, json_string(base64:encode(Body)),
                    <<",\"author\":">>, json_string(base64:encode(Author)),
                    <<",\"parents\":">>, json_array([base64:encode(P) || P <- SignedParents]),
                    <<",\"logical_clock\":">>, integer_to_binary(LogicalClock),
                    <<",\"key_epoch\":">>, integer_to_binary(Epoch),
                    <<",\"signature\":">>, json_string(base64:encode(Signature)), <<"}">>
                ])};
            Error -> Error
        end
    end);
sign_snapshot(_Workspace, _Payload, _Parents, _Clock) ->
    {error, <<"replica logical clock must be non-negative">>}.

verify_snapshot(Workspace, Payload64, Author64, Parents64, Clock, Epoch, Signature64)
  when Clock >= 0, Epoch > 0 ->
    case {decode64(Payload64), decode64(Author64), decode_parents(Parents64), decode64(Signature64)} of
        {{ok, Payload}, {ok, Author}, {ok, Parents}, {ok, Signature}} ->
            case trusted(Workspace, Author) of
                false -> {error, <<"unknown replica author">>};
                true ->
                    case revoked(Workspace, Author) of
                        true -> {error, <<"revoked replica author">>};
                        false -> verify_envelope(Workspace, Payload, Author, Parents, Clock, Epoch, Signature)
                    end
            end;
        _ -> {error, <<"invalid replica envelope encoding">>}
    end;
verify_snapshot(_Workspace, _Payload64, _Author64, _Parents64, _Clock, _Epoch, _Signature64) ->
    {error, <<"invalid replica envelope clock or key epoch">>}.

mark_applied(Workspace, Signature64) ->
    case decode64(Signature64) of
        {ok, Signature} -> update_key_file(seen_path(Workspace), fun(Keys) -> add_unique(Keys, Signature) end);
        _ -> {error, <<"invalid replica signature encoding">>}
    end.

record_conflict(Workspace, Author64, Detail) ->
    ensure_identity_dir(Workspace),
    Path = conflict_path(Workspace),
    Entry = {erlang:system_time(nanosecond), Author64, Detail},
    Existing = read_terms(Path),
    atomic_write(Path, term_to_binary([Entry | Existing])).

list_conflicts(Workspace) ->
    Path = conflict_path(Workspace),
    Entries = read_terms(Path),
    JsonItems = [
        iolist_to_binary([
            <<"{\"id\":">>, json_string(integer_to_binary(Ts)),
            <<",\"timestamp\":">>, integer_to_binary(Ts),
            <<",\"author\":">>, json_string(Author64),
            <<",\"detail\":">>, json_string(Detail),
            <<"}">>
        ])
     || {Ts, Author64, Detail} <- Entries
    ],
    {ok, iolist_to_binary([<<"[">>, join_raw_json(JsonItems), <<"]">>])}.

resolve_conflict(Workspace, ConflictId) ->
    Path = conflict_path(Workspace),
    Entries = read_terms(Path),
    Filtered = lists:filter(fun({Ts, _Author, _Detail}) ->
        integer_to_binary(Ts) =/= ConflictId
    end, Entries),
    atomic_write(Path, term_to_binary(Filtered)).

clear_conflicts(Workspace) ->
    Path = conflict_path(Workspace),
    atomic_write(Path, term_to_binary([])).

reset_identity_for_test(Workspace) ->
    _ = file:delete(seed_path(Workspace)),
    _ = file:delete(trust_path(Workspace)),
    _ = file:delete(revoked_path(Workspace)),
    _ = file:delete(seen_path(Workspace)),
    _ = file:delete(conflict_path(Workspace)),
    {ok, nil}.

%% The envelope verifier is the source of truth. This runs direct deterministic
%% checks over invalid protocol forms; the network decoder separately refuses
%% malformed JSON before this boundary.
adversarial_envelope_checks_for_test() ->
    Seed = crypto:strong_rand_bytes(32),
    Public = aarondb@envelope:public_key(Seed),
    Keyring = aarondb@envelope:put_key(
        aarondb@envelope:new_keyring(?MAX_FRAME, ?MAX_PARENTS),
        {key, Public, {active, 1}}),
    Envelope = aarondb@envelope:sign(?DOMAIN, <<"payload">>, Seed, [], 0, 1),
    {envelope, Version, Domain, Payload, Hash, Author, Parents, Clock, Epoch, Signature} = Envelope,
    Tampered = {envelope, Version, Domain, Payload, Hash, Author, Parents, Clock, Epoch,
                <<0, Signature/binary>>},
    Revoked = aarondb@envelope:revoke(Keyring, Public),
    case {aarondb@envelope:verify(Tampered, ?DOMAIN, Keyring),
          aarondb@envelope:verify(Envelope, ?DOMAIN, Revoked)} of
        {{error, invalid_signature}, {error, revoked_key}} -> {ok, nil};
        Other -> {error, iolist_to_binary(io_lib:format("adversarial envelope check failed: ~p", [Other]))}
    end.

verify_envelope(Workspace, Payload, Author, Parents, Clock, Epoch, Signature) ->
    Envelope = {envelope, 1, ?DOMAIN, Payload, aarondb@envelope:payload_digest(Payload),
                Author, Parents, Clock, Epoch, Signature},
    Keyring0 = aarondb@envelope:new_keyring(?MAX_FRAME, ?MAX_PARENTS),
    Keyring = aarondb@envelope:put_key(Keyring0, {key, Author, {active, Epoch}}),
    case aarondb@envelope:verify(Envelope, ?DOMAIN, Keyring) of
        {ok, nil} ->
            case seen(Workspace, Signature) of
                true -> {error, <<"replayed replica envelope">>};
                false -> {ok, Payload}
            end;
        {error, Reason} -> {error, iolist_to_binary(io_lib:format("replica envelope rejected: ~p", [Reason]))}
    end.

with_seed(Workspace, Fun) ->
    case seed(Workspace) of
        {ok, Seed} -> Fun(Seed);
        Error -> Error
    end.

seed(Workspace) ->
    ensure_identity_dir(Workspace),
    Path = seed_path(Workspace),
    case file:read_file(Path) of
        {ok, Seed} when byte_size(Seed) =:= 32 -> {ok, Seed};
        {ok, _} -> {error, <<"invalid Bankai Ed25519 seed">>};
        {error, enoent} ->
            _ = application:ensure_all_started(crypto),
            Seed = crypto:strong_rand_bytes(32),
            case atomic_write(Path, Seed) of
                {ok, nil} -> file:change_mode(Path, 8#600), {ok, Seed};
                Error -> Error
            end;
        {error, Reason} -> {error, file_error(Reason)}
    end.

trusted(Workspace, Public) -> lists:member(Public, read_key_file(trust_path(Workspace))).
revoked(Workspace, Public) -> lists:member(Public, read_key_file(revoked_path(Workspace))).
seen(Workspace, Signature) -> lists:member(Signature, read_key_file(seen_path(Workspace))).

with_decoded_public(Public64, Fun) ->
    case decode64(Public64) of
        {ok, Public} when byte_size(Public) =:= 32 -> Fun(Public);
        _ -> {error, <<"invalid Ed25519 public key">>}
    end.

decode_parents(Parents64) ->
    lists:foldr(fun(Encoded, Acc) ->
        case {decode64(Encoded), Acc} of
            {{ok, Parent}, {ok, Parents}} -> {ok, [Parent | Parents]};
            _ -> {error, <<"invalid replica parent encoding">>}
        end
    end, {ok, []}, Parents64).

decode64(Value) when is_binary(Value) ->
    try {ok, base64:decode(Value)} catch error:_ -> {error, invalid_base64} end.

update_key_file(Path, Update) ->
    Existing = read_key_file(Path),
    atomic_write(Path, term_to_binary(Update(Existing))).

read_key_file(Path) ->
    case file:read_file(Path) of
        {ok, Data} ->
            try
                Value = binary_to_term(Data, [safe]),
                case is_list(Value) andalso lists:all(fun is_binary/1, Value) of
                    true -> Value;
                    false -> []
                end
            catch error:_ -> [] end;
        _ -> []
    end.

read_terms(Path) ->
    case file:read_file(Path) of
        {ok, Data} ->
            try
                Value = binary_to_term(Data, [safe]),
                case is_list(Value) of true -> Value; false -> [] end
            catch error:_ -> [] end;
        _ -> []
    end.

add_unique(Keys, Key) -> case lists:member(Key, Keys) of true -> Keys; false -> [Key | Keys] end.

ensure_identity_dir(Workspace) ->
    filelib:ensure_dir(filename:join([binary_to_list(Workspace), "identity", "placeholder"])).

seed_path(Workspace) -> filename:join([binary_to_list(Workspace), "identity", "ed25519.seed"]).
trust_path(Workspace) -> filename:join([binary_to_list(Workspace), "identity", "trusted.term"]).
revoked_path(Workspace) -> filename:join([binary_to_list(Workspace), "identity", "revoked.term"]).
seen_path(Workspace) -> filename:join([binary_to_list(Workspace), "identity", "seen.term"]).
conflict_path(Workspace) -> filename:join([binary_to_list(Workspace), "identity", "conflicts.term"]).

atomic_write(Path, Data) ->
    Temp = Path ++ ".tmp",
    case file:write_file(Temp, Data, [binary]) of
        ok ->
            case file:rename(Temp, Path) of
                ok -> {ok, nil};
                {error, Reason} -> {error, file_error(Reason)}
            end;
        {error, Reason} -> {error, file_error(Reason)}
    end.

file_error(Reason) -> iolist_to_binary(io_lib:format("identity storage error: ~p", [Reason])).

json_array(Values) -> [<<"[">>, join_json(Values), <<"]">>].
join_json([]) -> [];
join_json([Value]) -> json_string(Value);
join_json([Value | Rest]) -> [json_string(Value), <<",">>, join_json(Rest)].

join_raw_json([]) -> [];
join_raw_json([Value]) -> Value;
join_raw_json([Value | Rest]) -> [Value, <<",">>, join_raw_json(Rest)].

json_string(Value) -> [<<"\"">>, escape_json(Value), <<"\"">>].
escape_json(Value) ->
    EscapedBackslash = binary:replace(Value, <<"\\">>, <<"\\\\">>, [global]),
    EscapedQuote = binary:replace(EscapedBackslash, <<"\"">>, <<"\\\"">>, [global]),
    EscapedNewline = binary:replace(EscapedQuote, <<"\n">>, <<"\\n">>, [global]),
    binary:replace(EscapedNewline, <<"\r">>, <<"\\r">>, [global]).
