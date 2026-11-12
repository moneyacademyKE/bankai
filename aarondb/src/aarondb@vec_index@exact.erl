-module(aarondb@vec_index@exact).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vec_index/exact.gleam").
-export([compare_scored_entities/2, search/4]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/vec_index/exact.gleam", 11).
?DOC(
    " A deterministic ordering for scored entities: score descending, then entity\n"
    " ID ascending. This makes ties mechanically comparable.\n"
).
-spec compare_scored_entities(
    {aarondb@fact:entity_id(), float()},
    {aarondb@fact:entity_id(), float()}
) -> gleam@order:order().
compare_scored_entities(A, B) ->
    case gleam@float:compare(erlang:element(2, B), erlang:element(2, A)) of
        eq ->
            gleam@int:compare(
                aarondb@fact:eid_to_integer(erlang:element(1, A)),
                aarondb@fact:eid_to_integer(erlang:element(1, B))
            );

        Other ->
            Other
    end.

-file("src/aarondb/vec_index/exact.gleam", 23).
?DOC(
    " Score every vector in a finite corpus and return the deterministic top-k.\n"
    " Inputs must already be validated and dimension-compatible by the caller.\n"
).
-spec search(
    gleam@dict:dict(aarondb@fact:entity_id(), list(float())),
    list(float()),
    float(),
    integer()
) -> list({aarondb@fact:entity_id(), float()}).
search(Nodes, Query, Threshold, K) ->
    Query@1 = aarondb@vector:normalize(Query),
    _pipe = Nodes,
    _pipe@1 = maps:to_list(_pipe),
    _pipe@2 = gleam@list:map(
        _pipe@1,
        fun(Entry) ->
            {erlang:element(1, Entry),
                aarondb@vector:dot_product(Query@1, erlang:element(2, Entry))}
        end
    ),
    _pipe@3 = gleam@list:filter(
        _pipe@2,
        fun(Result) -> erlang:element(2, Result) >= Threshold end
    ),
    _pipe@4 = gleam@list:sort(_pipe@3, fun compare_scored_entities/2),
    gleam@list:take(_pipe@4, K).
