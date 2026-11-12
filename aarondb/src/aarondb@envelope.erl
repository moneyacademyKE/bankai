-module(aarondb@envelope).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/envelope.gleam").
-export([new_keyring/2, put_key/2, revoke/2, payload_digest/1, public_key/1, sign/6, canonical_bytes/1, verify/3]).
-export_type([envelope/0, key_state/0, key/0, keyring/0, envelope_error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # envelope — canonical Ed25519-signed generic facts and events\n"
    "\n"
    " `EnvelopeV1` has deliberately boring bytes: a fixed tag/version followed by\n"
    " length-delimited fields in this exact order. The unsigned frame is hashed\n"
    " with its domain and then signed. It is unrelated to local capability auth.\n"
).

-type envelope() :: {envelope,
        integer(),
        binary(),
        bitstring(),
        bitstring(),
        bitstring(),
        list(bitstring()),
        integer(),
        integer(),
        bitstring()}.

-type key_state() :: {active, integer()} | {rotated, integer()} | revoked.

-type key() :: {key, bitstring(), key_state()}.

-type keyring() :: {keyring, list(key()), integer(), integer()}.

-type envelope_error() :: {unsupported_version, integer()} |
    {wrong_domain, binary(), binary()} |
    invalid_payload_hash |
    invalid_signature |
    unknown_author |
    inactive_key |
    revoked_key |
    {wrong_key_epoch, integer(), integer()} |
    {frame_too_large, integer(), integer()} |
    {too_many_parents, integer(), integer()} |
    negative_logical_clock.

-file("src/aarondb/envelope.gleam", 55).
-spec new_keyring(integer(), integer()) -> keyring().
new_keyring(Maximum_frame_bytes, Maximum_parents) ->
    {keyring, [], Maximum_frame_bytes, Maximum_parents}.

-file("src/aarondb/envelope.gleam", 61).
?DOC(
    " Adding the same public key replaces its lifecycle state; no map ordering is\n"
    " involved in either key lookup or canonical envelope bytes.\n"
).
-spec put_key(keyring(), key()) -> keyring().
put_key(Keyring, Key) ->
    {keyring,
        [Key |
            gleam@list:filter(
                erlang:element(2, Keyring),
                fun(Existing) ->
                    erlang:element(2, Existing) /= erlang:element(2, Key)
                end
            )],
        erlang:element(3, Keyring),
        erlang:element(4, Keyring)}.

-file("src/aarondb/envelope.gleam", 70).
-spec revoke(keyring(), bitstring()) -> keyring().
revoke(Keyring, Public_key) ->
    put_key(Keyring, {key, Public_key, revoked}).

-file("src/aarondb/envelope.gleam", 74).
-spec payload_digest(bitstring()) -> bitstring().
payload_digest(Payload) ->
    aarondb_envelope_ffi:sha256(Payload).

-file("src/aarondb/envelope.gleam", 78).
-spec public_key(bitstring()) -> bitstring().
public_key(Private_key) ->
    aarondb_envelope_ffi:ed25519_public_key(Private_key).

-file("src/aarondb/envelope.gleam", 229).
-spec frame(bitstring()) -> bitstring().
frame(Value) ->
    <<(erlang:byte_size(Value)):32, Value/bitstring>>.

-file("src/aarondb/envelope.gleam", 237).
-spec parents_frame(list(bitstring())) -> bitstring().
parents_frame(Parents) ->
    case Parents of
        [] ->
            <<>>;

        [Parent | Rest] ->
            <<((frame(Parent)))/bitstring, ((parents_frame(Rest)))/bitstring>>
    end.

-file("src/aarondb/envelope.gleam", 233).
-spec frame_parents(list(bitstring())) -> bitstring().
frame_parents(Parents) ->
    <<(erlang:length(Parents)):32, ((parents_frame(Parents)))/bitstring>>.

-file("src/aarondb/envelope.gleam", 225).
-spec frame_string(binary()) -> bitstring().
frame_string(Value) ->
    <<(string:length(Value)):32, Value/binary>>.

-file("src/aarondb/envelope.gleam", 206).
-spec unsigned_frame(
    binary(),
    bitstring(),
    bitstring(),
    list(bitstring()),
    integer(),
    integer()
) -> bitstring().
unsigned_frame(Domain, Payload, Author, Parents, Logical_clock, Key_epoch) ->
    <<"AARON-ENVELOPE-V1-SIGNATURE"/utf8,
        ((frame_string(Domain)))/bitstring,
        ((frame(Payload)))/bitstring,
        ((frame(Author)))/bitstring,
        ((frame_parents(Parents)))/bitstring,
        Logical_clock:64,
        Key_epoch:32>>.

-file("src/aarondb/envelope.gleam", 82).
-spec sign(
    binary(),
    bitstring(),
    bitstring(),
    list(bitstring()),
    integer(),
    integer()
) -> envelope().
sign(Domain, Payload, Author_private_key, Parents, Logical_clock, Key_epoch) ->
    Author = public_key(Author_private_key),
    Unsigned = unsigned_frame(
        Domain,
        Payload,
        Author,
        Parents,
        Logical_clock,
        Key_epoch
    ),
    Digest = aarondb_envelope_ffi:sha256(Unsigned),
    {envelope,
        1,
        Domain,
        Payload,
        payload_digest(Payload),
        Author,
        Parents,
        Logical_clock,
        Key_epoch,
        aarondb_envelope_ffi:ed25519_sign(Digest, Author_private_key)}.

-file("src/aarondb/envelope.gleam", 190).
-spec verify_signature(envelope()) -> {ok, nil} | {error, envelope_error()}.
verify_signature(Envelope) ->
    Digest = aarondb_envelope_ffi:sha256(
        unsigned_frame(
            erlang:element(3, Envelope),
            erlang:element(4, Envelope),
            erlang:element(6, Envelope),
            erlang:element(7, Envelope),
            erlang:element(8, Envelope),
            erlang:element(9, Envelope)
        )
    ),
    case aarondb_envelope_ffi:ed25519_verify(
        Digest,
        erlang:element(10, Envelope),
        erlang:element(6, Envelope)
    ) of
        true ->
            {ok, nil};

        false ->
            {error, invalid_signature}
    end.

-file("src/aarondb/envelope.gleam", 168).
-spec verify_hash_and_key(envelope(), keyring()) -> {ok, nil} |
    {error, envelope_error()}.
verify_hash_and_key(Envelope, Keyring) ->
    case erlang:element(5, Envelope) /= payload_digest(
        erlang:element(4, Envelope)
    ) of
        true ->
            {error, invalid_payload_hash};

        false ->
            case gleam@list:find(
                erlang:element(2, Keyring),
                fun(Key) ->
                    erlang:element(2, Key) =:= erlang:element(6, Envelope)
                end
            ) of
                {error, nil} ->
                    {error, unknown_author};

                {ok, {key, _, revoked}} ->
                    {error, revoked_key};

                {ok, {key, _, {rotated, _}}} ->
                    {error, inactive_key};

                {ok, {key, _, {active, Epoch}}} ->
                    case Epoch /= erlang:element(9, Envelope) of
                        true ->
                            {error,
                                {wrong_key_epoch,
                                    Epoch,
                                    erlang:element(9, Envelope)}};

                        false ->
                            verify_signature(Envelope)
                    end
            end
    end.

-file("src/aarondb/envelope.gleam", 124).
-spec canonical_bytes(envelope()) -> bitstring().
canonical_bytes(Envelope) ->
    <<"AARON-ENVELOPE"/utf8,
        (erlang:element(2, Envelope)):32,
        ((frame_string(erlang:element(3, Envelope))))/bitstring,
        ((frame(erlang:element(4, Envelope))))/bitstring,
        ((frame(erlang:element(5, Envelope))))/bitstring,
        ((frame(erlang:element(6, Envelope))))/bitstring,
        ((frame_parents(erlang:element(7, Envelope))))/bitstring,
        (erlang:element(8, Envelope)):64,
        (erlang:element(9, Envelope)):32,
        ((frame(erlang:element(10, Envelope))))/bitstring>>.

-file("src/aarondb/envelope.gleam", 139).
-spec verify_shape(envelope(), keyring()) -> {ok, nil} |
    {error, envelope_error()}.
verify_shape(Envelope, Keyring) ->
    case erlang:element(8, Envelope) < 0 of
        true ->
            {error, negative_logical_clock};

        false ->
            case erlang:length(erlang:element(7, Envelope)) > erlang:element(
                4,
                Keyring
            ) of
                true ->
                    {error,
                        {too_many_parents,
                            erlang:length(erlang:element(7, Envelope)),
                            erlang:element(4, Keyring)}};

                false ->
                    case erlang:byte_size(canonical_bytes(Envelope)) > erlang:element(
                        3,
                        Keyring
                    ) of
                        true ->
                            {error,
                                {frame_too_large,
                                    erlang:byte_size(canonical_bytes(Envelope)),
                                    erlang:element(3, Keyring)}};

                        false ->
                            verify_hash_and_key(Envelope, Keyring)
                    end
            end
    end.

-file("src/aarondb/envelope.gleam", 109).
?DOC(
    " Verification binds the requested application domain as well as the exact\n"
    " unsigned frame. A valid signature for another domain is not reusable here.\n"
).
-spec verify(envelope(), binary(), keyring()) -> {ok, nil} |
    {error, envelope_error()}.
verify(Envelope, Domain, Keyring) ->
    case erlang:element(2, Envelope) /= 1 of
        true ->
            {error, {unsupported_version, erlang:element(2, Envelope)}};

        false ->
            case erlang:element(3, Envelope) /= Domain of
                true ->
                    {error, {wrong_domain, Domain, erlang:element(3, Envelope)}};

                false ->
                    verify_shape(Envelope, Keyring)
            end
    end.
