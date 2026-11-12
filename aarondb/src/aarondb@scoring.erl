-module(aarondb@scoring).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/scoring.gleam").
-export([weighted_union/5]).
-export_type([scored_result/0, normalization_strategy/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # scoring — local result-combination compatibility helper\n"
    "\n"
    " This module is the authoritative helper for combining caller-owned scored\n"
    " result lists. It is used by the standalone local BM25 test surface and is\n"
    " intentionally separate from `engine/cognitive`: it does not learn, persist\n"
    " relevance, execute retrieval, or define a cognitive-memory model.\n"
    "\n"
    " `weighted_union` is deterministic only up to its documented score ordering;\n"
    " callers that need a semantic retrieval contract must use an engine-backed\n"
    " query or define one explicitly.\n"
).

-type scored_result() :: {scored_result, aarondb@fact:entity_id(), float()}.

-type normalization_strategy() :: min_max | none.

-file("src/aarondb/scoring.gleam", 70).
-spec normalize(list(scored_result()), normalization_strategy()) -> list(scored_result()).
normalize(Results, Strategy) ->
    case {Strategy, Results} of
        {none, _} ->
            Results;

        {_, []} ->
            [];

        {min_max, _} ->
            Min_s = gleam@list:fold(
                Results,
                1000000.0,
                fun(Acc, R) -> gleam@float:min(Acc, erlang:element(3, R)) end
            ),
            Max_s = gleam@list:fold(
                Results,
                -1000000.0,
                fun(Acc@1, R@1) ->
                    gleam@float:max(Acc@1, erlang:element(3, R@1))
                end
            ),
            Range = Max_s - Min_s,
            Safe_range = case Range of
                +0.0 ->
                    1.0;

                Val ->
                    Val
            end,
            _pipe = Results,
            gleam@list:map(
                _pipe,
                fun(R@2) ->
                    Normalized = case Safe_range of
                        +0.0 -> +0.0;
                        -0.0 -> -0.0;
                        Gleam@denominator -> (erlang:element(3, R@2) - Min_s) / Gleam@denominator
                    end,
                    {scored_result, erlang:element(2, R@2), Normalized}
                end
            )
    end.

-file("src/aarondb/scoring.gleam", 29).
?DOC(
    " Combines two lists of scored results using weighted union.\n"
    " Scores are first normalized (if requested) then combined by weight.\n"
    " If an entity appears in only one list, it's treated as having score 0.0 in the other.\n"
).
-spec weighted_union(
    list(scored_result()),
    list(scored_result()),
    float(),
    float(),
    normalization_strategy()
) -> list(scored_result()).
weighted_union(Results_a, Results_b, Weight_a, Weight_b, Normalization) ->
    Norm_a = normalize(Results_a, Normalization),
    Norm_b = normalize(Results_b, Normalization),
    Map_a = gleam@list:fold(
        Norm_a,
        maps:new(),
        fun(Acc, R) ->
            gleam@dict:insert(Acc, erlang:element(2, R), erlang:element(3, R))
        end
    ),
    Map_b = gleam@list:fold(
        Norm_b,
        maps:new(),
        fun(Acc@1, R@1) ->
            gleam@dict:insert(
                Acc@1,
                erlang:element(2, R@1),
                erlang:element(3, R@1)
            )
        end
    ),
    All_entities = begin
        _pipe = lists:append(maps:keys(Map_a), maps:keys(Map_b)),
        gleam@list:unique(_pipe)
    end,
    _pipe@1 = All_entities,
    _pipe@2 = gleam@list:map(
        _pipe@1,
        fun(E) ->
            Score_a = case gleam_stdlib:map_get(Map_a, E) of
                {ok, S} ->
                    S;

                {error, _} ->
                    +0.0
            end,
            Score_b = case gleam_stdlib:map_get(Map_b, E) of
                {ok, S@1} ->
                    S@1;

                {error, _} ->
                    +0.0
            end,
            Final_score = (Weight_a * Score_a) + (Weight_b * Score_b),
            {scored_result, E, Final_score}
        end
    ),
    gleam@list:sort(
        _pipe@2,
        fun(A, B) ->
            gleam@float:compare(erlang:element(3, B), erlang:element(3, A))
        end
    ).
