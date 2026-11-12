-module(aarondb@engine@navigator).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/navigator.gleam").
-export([plan/1, explain/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/engine/navigator.gleam", 7).
?DOC(
    " Legacy bridge to centralized optimizer.\n"
    " Rich Hickey alignment: \"Namespaces are good, but logic should be where it belongs.\"\n"
).
-spec plan(list(aarondb@shared@ast:body_clause())) -> list(aarondb@shared@ast:body_clause()).
plan(Clauses) ->
    erlang:element(
        3,
        aarondb@shared@optimizer:optimize(
            {'query', [], Clauses, none, none, none}
        )
    ).

-file("src/aarondb/engine/navigator.gleam", 17).
-spec explain(list(aarondb@shared@ast:body_clause())) -> binary().
explain(Clauses) ->
    aarondb@shared@optimizer:explain(Clauses).
