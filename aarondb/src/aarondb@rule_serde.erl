-module(aarondb@rule_serde).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/rule_serde.gleam").
-export([serialize/1, deserialize/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/rule_serde.gleam", 11).
-spec serialize(aarondb@shared@ast:rule()) -> binary().
serialize(Rule) ->
    Bits = erlang:term_to_binary(Rule),
    gleam_stdlib:base64_encode(Bits, false).

-file("src/aarondb/rule_serde.gleam", 18).
?DOC(
    " Decodes only serialized `ast.Rule` values, rejecting malformed, unsafe,\n"
    " and wrong-shaped Erlang external terms.\n"
).
-spec deserialize(binary()) -> {ok, aarondb@shared@ast:rule()} | {error, nil}.
deserialize(S) ->
    gleam@result:'try'(
        gleam@bit_array:base64_decode(S),
        fun(Bits) -> aarondb_term_ffi:decode_rule(Bits) end
    ).
