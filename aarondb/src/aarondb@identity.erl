-module(aarondb@identity).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/identity.gleam").
-export([new/3, put_certificate/2, revoke/2, admit_peer/5, reconnect/2, authorize_bootstrap/2, clean_recovery/0, force_recovery/2, inspect_recovery/4, fingerprint_for/2]).
-export_type([certificate_state/0, certificate/0, trust_store/0, rpc_limits/0, peer_error/0, recovery_alarm/0, recovery_state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # identity — durable node trust, mTLS policy, and safe recovery reference surface\n"
    "\n"
    " This is a policy model, not a socket implementation. A real transport presents\n"
    " peer certificate facts here *before* it delivers a Raft RPC. Durable adapters\n"
    " persist `TrustStore` and `RecoveryState` atomically with their authority files.\n"
).

-type certificate_state() :: {active, integer()} |
    {rotated, integer()} |
    revoked.

-type certificate() :: {certificate,
        binary(),
        binary(),
        binary(),
        certificate_state()}.

-type trust_store() :: {trust_store,
        binary(),
        list(binary()),
        list(certificate()),
        list(binary())}.

-type rpc_limits() :: {rpc_limits, integer(), integer()}.

-type peer_error() :: unknown_certificate |
    {wrong_certificate, binary(), binary()} |
    {untrusted_issuer, binary()} |
    inactive_certificate |
    revoked_certificate |
    {unauthorized_member, binary()} |
    {invalid_rpc_size, integer(), integer()} |
    invalid_reconnect_limit |
    {reconnect_exhausted, integer()} |
    bootstrap_denied.

-type recovery_alarm() :: {unsafe_recovery_acknowledged, binary()} |
    trust_material_missing |
    {membership_mismatch, list(binary()), list(binary())}.

-type recovery_state() :: {recovery_state, list(recovery_alarm()), boolean()}.

-file("src/aarondb/identity.gleam", 61).
-spec new(binary(), list(binary()), list(binary())) -> trust_store().
new(Cluster, Trusted_issuers, Members) ->
    {trust_store, Cluster, Trusted_issuers, [], Members}.

-file("src/aarondb/identity.gleam", 247).
-spec rotate(certificate_state()) -> certificate_state().
rotate(State) ->
    case State of
        {active, Epoch} ->
            {rotated, Epoch};

        Other ->
            Other
    end.

-file("src/aarondb/identity.gleam", 71).
?DOC(
    " Replacing a fingerprint is an explicit rotation. Existing certificates are\n"
    " retained only as `Rotated` evidence, never as valid transport credentials.\n"
).
-spec put_certificate(trust_store(), certificate()) -> trust_store().
put_certificate(Store, Certificate) ->
    {trust_store,
        erlang:element(2, Store),
        erlang:element(3, Store),
        [Certificate |
            gleam@list:map(
                erlang:element(4, Store),
                fun(Existing) ->
                    {certificate, Node, Fingerprint, Issuer, State} = Existing,
                    case (Node =:= erlang:element(2, Certificate)) andalso (Fingerprint
                    /= erlang:element(3, Certificate)) of
                        true ->
                            {certificate,
                                Node,
                                Fingerprint,
                                Issuer,
                                rotate(State)};

                        false ->
                            Existing
                    end
                end
            )],
        erlang:element(5, Store)}.

-file("src/aarondb/identity.gleam", 87).
-spec revoke(trust_store(), binary()) -> trust_store().
revoke(Store, Fingerprint) ->
    {trust_store,
        erlang:element(2, Store),
        erlang:element(3, Store),
        gleam@list:map(
            erlang:element(4, Store),
            fun(Certificate) ->
                {certificate, Node, Saved, Issuer, State} = Certificate,
                case Saved =:= Fingerprint of
                    true ->
                        {certificate, Node, Saved, Issuer, revoked};

                    false ->
                        {certificate, Node, Saved, Issuer, State}
                end
            end
        ),
        erlang:element(5, Store)}.

-file("src/aarondb/identity.gleam", 214).
-spec validate_certificate_state(list(binary()), binary(), certificate_state()) -> {ok,
        nil} |
    {error, peer_error()}.
validate_certificate_state(Members, Node, State) ->
    case State of
        revoked ->
            {error, revoked_certificate};

        {rotated, _} ->
            {error, inactive_certificate};

        {active, _} ->
            case gleam@list:contains(Members, Node) of
                true ->
                    {ok, nil};

                false ->
                    {error, {unauthorized_member, Node}}
            end
    end.

-file("src/aarondb/identity.gleam", 240).
-spec result_to_option({ok, certificate()} | {error, nil}) -> gleam@option:option(certificate()).
result_to_option(Result) ->
    case Result of
        {ok, Certificate} ->
            {some, Certificate};

        {error, nil} ->
            none
    end.

-file("src/aarondb/identity.gleam", 230).
-spec find_certificate(list(certificate()), binary()) -> gleam@option:option(certificate()).
find_certificate(Certificates, Fingerprint) ->
    _pipe = gleam@list:find(
        Certificates,
        fun(Certificate) -> erlang:element(3, Certificate) =:= Fingerprint end
    ),
    result_to_option(_pipe).

-file("src/aarondb/identity.gleam", 197).
-spec validate_certificate(trust_store(), binary(), binary()) -> {ok, nil} |
    {error, peer_error()}.
validate_certificate(Store, Expected_node, Fingerprint) ->
    case find_certificate(erlang:element(4, Store), Fingerprint) of
        none ->
            {error, unknown_certificate};

        {some, {certificate, Node, _, _, _}} when Node =/= Expected_node ->
            {error, {wrong_certificate, Expected_node, Node}};

        {some, {certificate, _, _, Issuer, State}} ->
            case gleam@list:contains(erlang:element(3, Store), Issuer) of
                false ->
                    {error, {untrusted_issuer, Issuer}};

                true ->
                    validate_certificate_state(
                        erlang:element(5, Store),
                        Expected_node,
                        State
                    )
            end
    end.

-file("src/aarondb/identity.gleam", 102).
?DOC(
    " Mutual TLS admission: issuer, presented identity, active certificate, and\n"
    " committed membership must all agree. Nothing reaches Raft before this passes.\n"
).
-spec admit_peer(trust_store(), binary(), binary(), rpc_limits(), integer()) -> {ok,
        nil} |
    {error, peer_error()}.
admit_peer(Store, Expected_node, Fingerprint, Limits, Rpc_bytes) ->
    case (erlang:element(2, Limits) < 1) orelse (erlang:element(3, Limits) < 1) of
        true ->
            {error, invalid_reconnect_limit};

        false ->
            case (Rpc_bytes > erlang:element(2, Limits)) orelse (Rpc_bytes < 0) of
                true ->
                    {error,
                        {invalid_rpc_size, Rpc_bytes, erlang:element(2, Limits)}};

                false ->
                    validate_certificate(Store, Expected_node, Fingerprint)
            end
    end.

-file("src/aarondb/identity.gleam", 121).
?DOC(
    " `attempt` is zero based. Callers must stop after this returns exhaustion;\n"
    " this deliberately refuses an unbounded retry loop disguised as resilience.\n"
).
-spec reconnect(rpc_limits(), integer()) -> {ok, nil} | {error, peer_error()}.
reconnect(Limits, Attempt) ->
    case (erlang:element(3, Limits) < 1) orelse (Attempt < 0) of
        true ->
            {error, invalid_reconnect_limit};

        false ->
            case Attempt < erlang:element(3, Limits) of
                true ->
                    {ok, nil};

                false ->
                    {error, {reconnect_exhausted, Attempt}}
            end
    end.

-file("src/aarondb/identity.gleam", 134).
?DOC(
    " New-cluster bootstrap may install the initial member set only when the trust\n"
    " store is empty. Existing clusters require committed membership changes.\n"
).
-spec authorize_bootstrap(trust_store(), list(binary())) -> {ok, nil} |
    {error, peer_error()}.
authorize_bootstrap(Store, Requested_members) ->
    case ((erlang:element(5, Store) =:= []) andalso (erlang:element(4, Store)
    =:= []))
    andalso (Requested_members /= []) of
        true ->
            {ok, nil};

        false ->
            {error, bootstrap_denied}
    end.

-file("src/aarondb/identity.gleam", 146).
-spec clean_recovery() -> recovery_state().
clean_recovery() ->
    {recovery_state, [], false}.

-file("src/aarondb/identity.gleam", 152).
?DOC(
    " A forced repair is an operator action, not an automatic healing path. Its\n"
    " durable alarm remains until an operator explicitly records the incident.\n"
).
-spec force_recovery(recovery_state(), binary()) -> recovery_state().
force_recovery(State, Reason) ->
    {recovery_state,
        [{unsafe_recovery_acknowledged, Reason} | erlang:element(2, State)],
        true}.

-file("src/aarondb/identity.gleam", 156).
-spec inspect_recovery(
    recovery_state(),
    list(binary()),
    list(binary()),
    boolean()
) -> recovery_state().
inspect_recovery(
    State,
    Expected_members,
    Actual_members,
    Trust_material_present
) ->
    With_trust = case Trust_material_present of
        true ->
            erlang:element(2, State);

        false ->
            [trust_material_missing | erlang:element(2, State)]
    end,
    Alarms = case Expected_members =:= Actual_members of
        true ->
            With_trust;

        false ->
            [{membership_mismatch, Expected_members, Actual_members} |
                With_trust]
    end,
    {recovery_state, Alarms, erlang:element(3, State)}.

-file("src/aarondb/identity.gleam", 183).
-spec certificate_fingerprint({ok, certificate()} | {error, nil}) -> gleam@option:option(binary()).
certificate_fingerprint(Result) ->
    case Result of
        {ok, {certificate, _, Fingerprint, _, _}} ->
            {some, Fingerprint};

        {error, nil} ->
            none
    end.

-file("src/aarondb/identity.gleam", 190).
-spec is_active(certificate_state()) -> boolean().
is_active(State) ->
    case State of
        {active, _} ->
            true;

        _ ->
            false
    end.

-file("src/aarondb/identity.gleam", 176).
-spec fingerprint_for(trust_store(), binary()) -> gleam@option:option(binary()).
fingerprint_for(Store, Node) ->
    _pipe = gleam@list:find(
        erlang:element(4, Store),
        fun(Certificate) ->
            (erlang:element(2, Certificate) =:= Node) andalso is_active(
                erlang:element(5, Certificate)
            )
        end
    ),
    certificate_fingerprint(_pipe).
