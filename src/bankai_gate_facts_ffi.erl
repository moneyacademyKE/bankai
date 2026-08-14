-module(bankai_gate_facts_ffi).
-export([public_key/1, trust_issuer/2, revoke_issuer/2, sign/5, verify/11,
         issuer_status/2, reset_for_test/1]).

%% Gate facts reuse Bankai's workspace identity and trust material. Their
%% envelope domain is intentionally independent from every other signed Bankai
%% protocol, so those signatures cannot be replayed as gate evidence.
-define(DOMAIN, <<"bankai-gate-fact-v1">>).
-define(MAX_FRAME, 16777216).
-define(MAX_PARENTS, 1).

public_key(Workspace) when is_binary(Workspace) ->
    with_seed(Workspace, fun(Seed) ->
        {ok, base64:encode(aarondb@envelope:public_key(Seed))}
    end);
public_key(_Workspace) ->
    {error, <<"invalid gate fact workspace">>}.

trust_issuer(Workspace, Public64)
  when is_binary(Workspace), is_binary(Public64) ->
    with_decoded_public(Public64, fun(Public) ->
        update_key_file(Workspace, trust_path(Workspace),
                        fun(Keys) -> add_unique(Keys, Public) end)
    end);
trust_issuer(_Workspace, _Public64) ->
    {error, <<"invalid gate fact issuer">>}.

revoke_issuer(Workspace, Public64)
  when is_binary(Workspace), is_binary(Public64) ->
    with_decoded_public(Public64, fun(Public) ->
        update_key_file(Workspace, revoked_path(Workspace),
                        fun(Keys) -> add_unique(Keys, Public) end)
    end);
revoke_issuer(_Workspace, _Public64) ->
    {error, <<"invalid gate fact issuer">>}.

issuer_status(Workspace, Public64)
  when is_binary(Workspace), is_binary(Public64) ->
    with_decoded_public(Public64, fun(Public) ->
        {ok, {lists:member(Public, read_key_file(trust_path(Workspace))),
              lists:member(Public, read_key_file(revoked_path(Workspace)))}}
    end);
issuer_status(_Workspace, _Public64) ->
    {error, <<"invalid gate fact issuer">>}.

sign(Workspace, GateId, satisfied, ObservedAt, ExpiresAt)
  when is_binary(Workspace), is_binary(GateId),
       is_integer(ObservedAt), is_integer(ExpiresAt) ->
    case valid_fact_fields(GateId, satisfied, ObservedAt, ExpiresAt) of
        ok ->
            with_seed(Workspace, fun(Seed) ->
                Payload = fact_payload(GateId, satisfied, ObservedAt, ExpiresAt),
                Envelope = aarondb@envelope:sign(
                    ?DOMAIN, Payload, Seed, [], ObservedAt, 1),
                {envelope, 1, Domain, Payload, _Hash, Author, [],
                 ObservedAt, 1, Signature} = Envelope,
                {ok, {Domain, GateId, satisfied, ObservedAt, ExpiresAt,
                      base64:encode(Author), base64:encode(Signature)}}
            end);
        Error -> Error
    end;
sign(_Workspace, _GateId, _State, _ObservedAt, _ExpiresAt) ->
    {error, <<"invalid gate fact fields">>}.

verify(Workspace, Domain, GateId, State, ObservedAt, ExpiresAt,
       Author64, Signature64, ExpectedGateId, ExpectedIssuer64, Now)
  when is_binary(Workspace), is_binary(Domain), is_binary(GateId),
       is_integer(ObservedAt), is_integer(ExpiresAt), is_binary(Author64),
       is_binary(Signature64), is_binary(ExpectedGateId),
       is_binary(ExpectedIssuer64), is_integer(Now) ->
    case decode_wire_keys(Author64, Signature64, ExpectedIssuer64) of
        {ok, Author, Signature, ExpectedIssuer} ->
            verify_decoded(Workspace, Domain, GateId, State, ObservedAt,
                           ExpiresAt, Author, Author64, Signature, Signature64,
                           ExpectedGateId, ExpectedIssuer, Now);
        error -> {error, <<"malformed gate fact encoding">>}
    end;
verify(_Workspace, _Domain, _GateId, _State, _ObservedAt, _ExpiresAt,
       _Author64, _Signature64, _ExpectedGateId, _ExpectedIssuer64, _Now) ->
    {error, <<"malformed gate fact wire">>}.

reset_for_test(Workspace) when is_binary(Workspace) ->
    _ = file:delete(seed_path(Workspace)),
    _ = file:delete(trust_path(Workspace)),
    _ = file:delete(revoked_path(Workspace)),
    {ok, nil};
reset_for_test(_Workspace) ->
    {error, <<"invalid gate fact workspace">>}.

verify_decoded(Workspace, Domain, GateId, State, ObservedAt, ExpiresAt,
               Author, Author64, Signature, Signature64, ExpectedGateId,
               ExpectedIssuer, Now) ->
    case preliminary_check(Domain, GateId, State, ObservedAt, ExpiresAt,
                           Author, ExpectedGateId, ExpectedIssuer, Now) of
        ok ->
            case revoked(Workspace, Author) of
                true -> {error, <<"revoked gate fact issuer">>};
                false ->
                    case trusted(Workspace, Author) of
                        false -> {error, <<"unknown gate fact issuer">>};
                        true ->
                            verify_signature(GateId, State, ObservedAt,
                                             ExpiresAt, Author, Author64,
                                             Signature, Signature64)
                    end
            end;
        Error -> Error
    end.

preliminary_check(?DOMAIN, GateId, State, ObservedAt, ExpiresAt, Author,
                  ExpectedGateId, ExpectedIssuer, Now) ->
    case Author =:= ExpectedIssuer of
        false -> {error, <<"wrong gate fact issuer">>};
        true ->
            case GateId =:= ExpectedGateId of
                false -> {error, <<"wrong gate fact gate">>};
                true ->
                    case valid_fact_fields(GateId, State, ObservedAt, ExpiresAt) of
                        ok when Now < 0 ->
                            {error, <<"invalid gate fact verification time">>};
                        ok when ObservedAt > Now ->
                            {error, <<"future gate fact observation">>};
                        ok when ExpiresAt =< Now ->
                            {error, <<"expired gate fact">>};
                        ok -> ok;
                        Error -> Error
                    end
            end
    end;
preliminary_check(_Domain, _GateId, _State, _ObservedAt, _ExpiresAt, _Author,
                  _ExpectedGateId, _ExpectedIssuer, _Now) ->
    {error, <<"wrong gate fact domain">>}.

verify_signature(GateId, State, ObservedAt, ExpiresAt, Author, Author64,
                 Signature, Signature64) ->
    Payload = fact_payload(GateId, State, ObservedAt, ExpiresAt),
    Envelope = {envelope, 1, ?DOMAIN, Payload,
                aarondb@envelope:payload_digest(Payload), Author, [],
                ObservedAt, 1, Signature},
    Keyring0 = aarondb@envelope:new_keyring(?MAX_FRAME, ?MAX_PARENTS),
    Keyring = aarondb@envelope:put_key(
        Keyring0, {key, Author, {active, 1}}),
    case aarondb@envelope:verify(Envelope, ?DOMAIN, Keyring) of
        {ok, nil} ->
            {ok, {GateId, State, ObservedAt, ExpiresAt,
                  Author64, Signature64}};
        {error, Reason} ->
            {error, iolist_to_binary(
                io_lib:format("gate fact envelope rejected: ~p", [Reason]))}
    end.

valid_fact_fields(GateId, satisfied, ObservedAt, ExpiresAt)
  when byte_size(GateId) > 0, ObservedAt >= 0, ExpiresAt > ObservedAt ->
    ok;
valid_fact_fields(_GateId, _State, _ObservedAt, _ExpiresAt) ->
    {error, <<"invalid gate fact fields">>}.

%% Deterministic ETF is an internal canonical payload. Domain, author, logical
%% clock, and this payload are all covered by aarondb's Ed25519 envelope; the
%% payload itself contains every public fact field.
fact_payload(GateId, State, ObservedAt, ExpiresAt) ->
    term_to_binary(
        {bankai_gate_fact_v1, GateId, State, ObservedAt, ExpiresAt},
        [deterministic]).

decode_wire_keys(Author64, Signature64, ExpectedIssuer64) ->
    case {decode_public(Author64), decode_signature(Signature64),
          decode_public(ExpectedIssuer64)} of
        {{ok, Author}, {ok, Signature}, {ok, ExpectedIssuer}} ->
            {ok, Author, Signature, ExpectedIssuer};
        _ -> error
    end.

with_seed(Workspace, Fun) ->
    case seed(Workspace) of
        {ok, Seed} -> Fun(Seed);
        Error -> Error
    end.

seed(Workspace) ->
    case ensure_identity_dir(Workspace) of
        ok -> read_or_create_seed(seed_path(Workspace));
        {error, Reason} -> {error, file_error(Reason)}
    end.

read_or_create_seed(Path) ->
    case file:read_file(Path) of
        {ok, Seed} when byte_size(Seed) =:= 32 -> {ok, Seed};
        {ok, _} -> {error, <<"invalid Bankai Ed25519 seed">>};
        {error, enoent} -> create_seed(Path);
        {error, Reason} -> {error, file_error(Reason)}
    end.

create_seed(Path) ->
    _ = application:ensure_all_started(crypto),
    Seed = crypto:strong_rand_bytes(32),
    case atomic_write(Path, Seed) of
        {ok, nil} ->
            case file:change_mode(Path, 8#600) of
                ok -> {ok, Seed};
                {error, Reason} -> {error, file_error(Reason)}
            end;
        Error -> Error
    end.

trusted(Workspace, Public) ->
    lists:member(Public, read_key_file(trust_path(Workspace))).

revoked(Workspace, Public) ->
    lists:member(Public, read_key_file(revoked_path(Workspace))).

with_decoded_public(Public64, Fun) ->
    case decode_public(Public64) of
        {ok, Public} -> Fun(Public);
        _ -> {error, <<"invalid Ed25519 public key">>}
    end.

decode_public(Value) ->
    case decode64(Value) of
        {ok, Public} when byte_size(Public) =:= 32 -> {ok, Public};
        _ -> {error, invalid_public_key}
    end.

decode_signature(Value) ->
    case decode64(Value) of
        {ok, Signature} when byte_size(Signature) =:= 64 -> {ok, Signature};
        _ -> {error, invalid_signature}
    end.

decode64(Value) when is_binary(Value) ->
    try
        Decoded = base64:decode(Value),
        case base64:encode(Decoded) =:= Value of
            true -> {ok, Decoded};
            false -> {error, noncanonical_base64}
        end
    catch error:_ -> {error, invalid_base64}
    end;
decode64(_Value) ->
    {error, invalid_base64}.

update_key_file(Workspace, Path, Update) ->
    case ensure_identity_dir(Workspace) of
        ok ->
            Existing = read_key_file(Path),
            atomic_write(Path, term_to_binary(Update(Existing), [deterministic]));
        {error, Reason} -> {error, file_error(Reason)}
    end.

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

add_unique(Keys, Key) ->
    case lists:member(Key, Keys) of
        true -> Keys;
        false -> [Key | Keys]
    end.

ensure_identity_dir(Workspace) ->
    filelib:ensure_dir(filename:join(
        [binary_to_list(Workspace), "identity", "placeholder"])).

seed_path(Workspace) ->
    filename:join([binary_to_list(Workspace), "identity", "ed25519.seed"]).
trust_path(Workspace) ->
    filename:join([binary_to_list(Workspace), "identity", "trusted.term"]).
revoked_path(Workspace) ->
    filename:join([binary_to_list(Workspace), "identity", "revoked.term"]).

atomic_write(Path, Data) ->
    Temp = Path ++ ".gate-fact.tmp",
    case file:write_file(Temp, Data, [binary]) of
        ok ->
            case file:rename(Temp, Path) of
                ok -> {ok, nil};
                {error, Reason} -> {error, file_error(Reason)}
            end;
        {error, Reason} -> {error, file_error(Reason)}
    end.

file_error(Reason) ->
    iolist_to_binary(io_lib:format("identity storage error: ~p", [Reason])).
