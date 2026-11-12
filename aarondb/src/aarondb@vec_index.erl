-module(aarondb@vec_index).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vec_index.gleam").
-export([default_config/0, new_with_config/1, new/0, deterministic_config/1, new_with_m/1, delete/2, contains/2, try_insert/3, insert/3, exact_search/4, try_search/4, search/4, size/1]).
-export_type([layer/0, level_source/0, hnsw_config/0, vec_index/0, search_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type layer() :: {layer,
        gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:entity_id()))}.

-type level_source() :: random_levels | {deterministic_levels, list(integer())}.

-type hnsw_config() :: {hnsw_config, integer(), integer(), level_source()}.

-type vec_index() :: {vec_index,
        gleam@dict:dict(aarondb@fact:entity_id(), list(float())),
        gleam@dict:dict(integer(), layer()),
        gleam@option:option(integer()),
        hnsw_config(),
        {ok, aarondb@fact:entity_id()} | {error, nil},
        integer()}.

-type search_result() :: {search_result, aarondb@fact:entity_id(), float()}.

-file("src/aarondb/vec_index.gleam", 56).
?DOC(" Production HNSW configuration. Its level source is intentionally random.\n").
-spec default_config() -> hnsw_config().
default_config() ->
    {hnsw_config, 16, 100, random_levels}.

-file("src/aarondb/vec_index.gleam", 83).
?DOC(
    " Create an empty index with an explicit configuration.\n"
    "\n"
    " `DeterministicLevels` provides reproducible topology for tests and benchmarks.\n"
).
-spec new_with_config(hnsw_config()) -> vec_index().
new_with_config(Config) ->
    {vec_index,
        maps:new(),
        maps:from_list([{0, {layer, maps:new()}}]),
        none,
        Config,
        {error, nil},
        0}.

-file("src/aarondb/vec_index.gleam", 61).
?DOC(" Create an empty vector index with production defaults.\n").
-spec new() -> vec_index().
new() ->
    new_with_config(default_config()).

-file("src/aarondb/vec_index.gleam", 67).
?DOC(
    " A repeatable test/benchmark configuration. Each insert consumes one supplied\n"
    " non-negative level; after exhaustion, new nodes are placed on level zero.\n"
).
-spec deterministic_config(list(integer())) -> hnsw_config().
deterministic_config(Levels) ->
    {hnsw_config, 16, 100, {deterministic_levels, Levels}}.

-file("src/aarondb/vec_index.gleam", 76).
?DOC(" Create an empty vector index with custom max-neighbor degree.\n").
-spec new_with_m(integer()) -> vec_index().
new_with_m(M) ->
    new_with_config(
        begin
            _record = default_config(),
            {hnsw_config,
                M,
                erlang:element(3, _record),
                erlang:element(4, _record)}
        end
    ).

-file("src/aarondb/vec_index.gleam", 105).
-spec random_level(float()) -> integer().
random_level(Multiplier) ->
    R = rand:uniform(),
    Log_r@1 = case gleam@float:logarithm(R) of
        {ok, Log_r} -> Log_r;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/vec_index"/utf8>>,
                        function => <<"random_level"/utf8>>,
                        line => 107,
                        value => _assert_fail,
                        start => 3234,
                        'end' => 3275,
                        pattern_start => 3245,
                        pattern_end => 3254})
    end,
    Level = erlang:round(math:floor(Multiplier * Log_r@1)),
    case Level < 0 of
        true ->
            - Level;

        false ->
            Level
    end.

-file("src/aarondb/vec_index.gleam", 94).
-spec next_level(level_source(), float()) -> {integer(), level_source()}.
next_level(Source, Multiplier) ->
    case Source of
        random_levels ->
            {random_level(Multiplier), random_levels};

        {deterministic_levels, [Level | Rest]} ->
            {gleam@int:max(0, Level), {deterministic_levels, Rest}};

        {deterministic_levels, []} ->
            {0, {deterministic_levels, []}}
    end.

-file("src/aarondb/vec_index.gleam", 638).
?DOC(" Prune a neighbor list to max_neighbors, keeping the most similar.\n").
-spec prune_neighbors(
    integer(),
    aarondb@fact:entity_id(),
    list(aarondb@fact:entity_id()),
    gleam@dict:dict(aarondb@fact:entity_id(), list(float()))
) -> list(aarondb@fact:entity_id()).
prune_neighbors(Max_neighbors, Node_id, Candidates, Nodes) ->
    case gleam_stdlib:map_get(Nodes, Node_id) of
        {error, nil} ->
            gleam@list:take(gleam@list:unique(Candidates), Max_neighbors);

        {ok, Node_vec} ->
            _pipe = gleam@list:unique(Candidates),
            _pipe@1 = gleam@list:filter_map(
                _pipe,
                fun(C) -> case gleam_stdlib:map_get(Nodes, C) of
                        {ok, V} ->
                            {ok, {C, aarondb@vector:dot_product(Node_vec, V)}};

                        {error, nil} ->
                            {error, nil}
                    end end
            ),
            _pipe@2 = gleam@list:sort(
                _pipe@1,
                fun(A, B) ->
                    gleam@float:compare(
                        erlang:element(2, B),
                        erlang:element(2, A)
                    )
                end
            ),
            _pipe@3 = gleam@list:take(_pipe@2, Max_neighbors),
            gleam@list:map(_pipe@3, fun(Pair) -> erlang:element(1, Pair) end)
    end.

-file("src/aarondb/vec_index.gleam", 661).
-spec unwrap_list({ok, list(GSY)} | {error, nil}) -> list(GSY).
unwrap_list(Res) ->
    case Res of
        {ok, L} ->
            L;

        {error, nil} ->
            []
    end.

-file("src/aarondb/vec_index.gleam", 355).
-spec compare_search_results(search_result(), search_result()) -> gleam@order:order().
compare_search_results(A, B) ->
    case gleam@float:compare(erlang:element(3, B), erlang:element(3, A)) of
        eq ->
            gleam@int:compare(
                aarondb@fact:eid_to_integer(erlang:element(2, A)),
                aarondb@fact:eid_to_integer(erlang:element(2, B))
            );

        Other ->
            Other
    end.

-file("src/aarondb/vec_index.gleam", 443).
-spec greedy_search(
    gleam@dict:dict(aarondb@fact:entity_id(), list(float())),
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:entity_id())),
    list(float()),
    list(aarondb@fact:entity_id()),
    gleam@dict:dict(aarondb@fact:entity_id(), boolean()),
    list(search_result()),
    integer()
) -> list(search_result()).
greedy_search(Nodes, Edges, Query, Candidates, Visited, Results, Budget) ->
    case (Budget =< 0) orelse gleam@list:is_empty(Candidates) of
        true ->
            Results;

        false ->
            Scored_candidates = begin
                _pipe = gleam@list:filter_map(
                    Candidates,
                    fun(Eid) -> case gleam_stdlib:map_get(Nodes, Eid) of
                            {ok, V} ->
                                {ok,
                                    {search_result,
                                        Eid,
                                        aarondb@vector:dot_product(Query, V)}};

                            _ ->
                                {error, nil}
                        end end
                ),
                gleam@list:sort(
                    _pipe,
                    fun(A, B) ->
                        gleam@float:compare(
                            erlang:element(3, B),
                            erlang:element(3, A)
                        )
                    end
                )
            end,
            case Scored_candidates of
                [] ->
                    Results;

                [Best | _] ->
                    Rest_candidates = gleam@list:filter(
                        Candidates,
                        fun(C) -> C /= erlang:element(2, Best) end
                    ),
                    Furthest_res = begin
                        _pipe@1 = Results,
                        _pipe@2 = gleam@list:sort(
                            _pipe@1,
                            fun(A@1, B@1) ->
                                gleam@float:compare(
                                    erlang:element(3, A@1),
                                    erlang:element(3, B@1)
                                )
                            end
                        ),
                        gleam@list:first(_pipe@2)
                    end,
                    Results_count = erlang:length(Results),
                    case Furthest_res of
                        {ok, Furthest} ->
                            Stop = (erlang:element(3, Best) < erlang:element(
                                3,
                                Furthest
                            ))
                            andalso (Results_count >= 20),
                            case Stop of
                                true ->
                                    Results;

                                false ->
                                    Neighbors = begin
                                        _pipe@3 = gleam_stdlib:map_get(
                                            Edges,
                                            erlang:element(2, Best)
                                        ),
                                        _pipe@4 = unwrap_list(_pipe@3),
                                        gleam@list:filter(
                                            _pipe@4,
                                            fun(N) ->
                                                not gleam@dict:has_key(
                                                    Visited,
                                                    N
                                                )
                                            end
                                        )
                                    end,
                                    New_visited = gleam@list:fold(
                                        Neighbors,
                                        Visited,
                                        fun(Acc, N@1) ->
                                            gleam@dict:insert(Acc, N@1, true)
                                        end
                                    ),
                                    Scored_neighbors = gleam@list:filter_map(
                                        Neighbors,
                                        fun(N@2) ->
                                            case gleam_stdlib:map_get(
                                                Nodes,
                                                N@2
                                            ) of
                                                {ok, V@1} ->
                                                    {ok,
                                                        {search_result,
                                                            N@2,
                                                            aarondb@vector:dot_product(
                                                                Query,
                                                                V@1
                                                            )}};

                                                _ ->
                                                    {error, nil}
                                            end
                                        end
                                    ),
                                    New_candidates = begin
                                        _pipe@5 = lists:append(
                                            Rest_candidates,
                                            Neighbors
                                        ),
                                        gleam@list:unique(_pipe@5)
                                    end,
                                    New_results = begin
                                        _pipe@6 = lists:append(
                                            Results,
                                            Scored_neighbors
                                        ),
                                        _pipe@7 = gleam@list:unique(_pipe@6),
                                        _pipe@8 = gleam@list:sort(
                                            _pipe@7,
                                            fun compare_search_results/2
                                        ),
                                        gleam@list:take(_pipe@8, 100)
                                    end,
                                    greedy_search(
                                        Nodes,
                                        Edges,
                                        Query,
                                        New_candidates,
                                        New_visited,
                                        New_results,
                                        Budget - 1
                                    )
                            end;

                        {error, nil} ->
                            Neighbors@1 = begin
                                _pipe@9 = gleam_stdlib:map_get(
                                    Edges,
                                    erlang:element(2, Best)
                                ),
                                _pipe@10 = unwrap_list(_pipe@9),
                                gleam@list:filter(
                                    _pipe@10,
                                    fun(N@3) ->
                                        not gleam@dict:has_key(Visited, N@3)
                                    end
                                )
                            end,
                            New_visited@1 = gleam@list:fold(
                                Neighbors@1,
                                Visited,
                                fun(Acc@1, N@4) ->
                                    gleam@dict:insert(Acc@1, N@4, true)
                                end
                            ),
                            Scored_neighbors@1 = gleam@list:filter_map(
                                Neighbors@1,
                                fun(N@5) ->
                                    case gleam_stdlib:map_get(Nodes, N@5) of
                                        {ok, V@2} ->
                                            {ok,
                                                {search_result,
                                                    N@5,
                                                    aarondb@vector:dot_product(
                                                        Query,
                                                        V@2
                                                    )}};

                                        _ ->
                                            {error, nil}
                                    end
                                end
                            ),
                            New_candidates@1 = begin
                                _pipe@11 = lists:append(
                                    Rest_candidates,
                                    Neighbors@1
                                ),
                                gleam@list:unique(_pipe@11)
                            end,
                            New_results@1 = begin
                                _pipe@12 = lists:append(
                                    Results,
                                    Scored_neighbors@1
                                ),
                                _pipe@13 = gleam@list:unique(_pipe@12),
                                _pipe@14 = gleam@list:sort(
                                    _pipe@13,
                                    fun compare_search_results/2
                                ),
                                gleam@list:take(_pipe@14, 100)
                            end,
                            greedy_search(
                                Nodes,
                                Edges,
                                Query,
                                New_candidates@1,
                                New_visited@1,
                                New_results@1,
                                Budget - 1
                            )
                    end
            end
    end.

-file("src/aarondb/vec_index.gleam", 283).
-spec descend_to_level(
    vec_index(),
    list(float()),
    aarondb@fact:entity_id(),
    integer(),
    integer()
) -> aarondb@fact:entity_id().
descend_to_level(Idx, Query, Ep, Current_level, Stop_level) ->
    case Current_level < Stop_level of
        true ->
            Ep;

        false ->
            Layer = begin
                _pipe = gleam_stdlib:map_get(
                    erlang:element(3, Idx),
                    Current_level
                ),
                gleam@result:unwrap(_pipe, {layer, maps:new()})
            end,
            Vec_ep = begin
                _pipe@1 = gleam_stdlib:map_get(erlang:element(2, Idx), Ep),
                gleam@result:unwrap(_pipe@1, Query)
            end,
            Ep_res = {search_result,
                Ep,
                aarondb@vector:dot_product(Query, Vec_ep)},
            Results = greedy_search(
                erlang:element(2, Idx),
                erlang:element(2, Layer),
                Query,
                [Ep],
                maps:new(),
                [Ep_res],
                10
            ),
            Next_ep = case begin
                _pipe@2 = Results,
                _pipe@3 = gleam@list:sort(
                    _pipe@2,
                    fun(A, B) ->
                        gleam@float:compare(
                            erlang:element(3, B),
                            erlang:element(3, A)
                        )
                    end
                ),
                gleam@list:first(_pipe@3)
            end of
                {ok, Best} ->
                    erlang:element(2, Best);

                {error, nil} ->
                    Ep
            end,
            descend_to_level(Idx, Query, Next_ep, Current_level - 1, Stop_level)
    end.

-file("src/aarondb/vec_index.gleam", 163).
?DOC(" Greedy-links the new node to its nearest existing neighbors across multiple levels.\n").
-spec do_insert(vec_index(), aarondb@fact:entity_id(), list(float()), integer()) -> vec_index().
do_insert(Idx, Entity, Vec, Dimensions) ->
    Vec@1 = aarondb@vector:normalize(Vec),
    Nodes = gleam@dict:insert(erlang:element(2, Idx), Entity, Vec@1),
    Log_16@1 = case gleam@float:logarithm(16.0) of
        {ok, Log_16} -> Log_16;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/vec_index"/utf8>>,
                        function => <<"do_insert"/utf8>>,
                        line => 174,
                        value => _assert_fail,
                        start => 5006,
                        'end' => 5051,
                        pattern_start => 5017,
                        pattern_end => 5027})
    end,
    {Level, Level_source} = next_level(
        erlang:element(4, erlang:element(5, Idx)),
        case Log_16@1 of
            +0.0 -> +0.0;
            -0.0 -> -0.0;
            Gleam@denominator -> 1.0 / Gleam@denominator
        end
    ),
    Idx@1 = {vec_index,
        erlang:element(2, Idx),
        erlang:element(3, Idx),
        erlang:element(4, Idx),
        begin
            _record = erlang:element(5, Idx),
            {hnsw_config,
                erlang:element(2, _record),
                erlang:element(3, _record),
                Level_source}
        end,
        erlang:element(6, Idx),
        erlang:element(7, Idx)},
    New_max_level = gleam@int:max(erlang:element(7, Idx@1), Level),
    case erlang:element(6, Idx@1) of
        {error, nil} ->
            Layers = gleam@int:range(
                0,
                Level + 1,
                erlang:element(3, Idx@1),
                fun(Acc, I) ->
                    gleam@dict:insert(
                        Acc,
                        I,
                        {layer, gleam@dict:insert(maps:new(), Entity, [])}
                    )
                end
            ),
            {vec_index,
                Nodes,
                Layers,
                {some, Dimensions},
                erlang:element(5, Idx@1),
                {ok, Entity},
                Level};

        {ok, Ep_id} ->
            Ep_for_level = descend_to_level(
                Idx@1,
                Vec@1,
                Ep_id,
                erlang:element(7, Idx@1),
                Level + 1
            ),
            {Final_layers, _} = gleam@int:range(
                Level,
                -1,
                {erlang:element(3, Idx@1), Ep_for_level},
                fun(Acc@1, I@1) ->
                    {Curr_layers, Curr_ep} = Acc@1,
                    Layer = begin
                        _pipe = gleam_stdlib:map_get(Curr_layers, I@1),
                        gleam@result:unwrap(_pipe, {layer, maps:new()})
                    end,
                    Vec_ep = begin
                        _pipe@1 = gleam_stdlib:map_get(Nodes, Curr_ep),
                        gleam@result:unwrap(_pipe@1, Vec@1)
                    end,
                    Ep_res = {search_result,
                        Curr_ep,
                        aarondb@vector:dot_product(Vec@1, Vec_ep)},
                    Neighbors = begin
                        _pipe@2 = greedy_search(
                            Nodes,
                            erlang:element(2, Layer),
                            Vec@1,
                            [Curr_ep],
                            maps:from_list([{Curr_ep, true}]),
                            [Ep_res],
                            100
                        ),
                        _pipe@3 = gleam@list:filter(
                            _pipe@2,
                            fun(R) -> erlang:element(2, R) /= Entity end
                        ),
                        _pipe@4 = gleam@list:sort(
                            _pipe@3,
                            fun(A, B) ->
                                gleam@float:compare(
                                    erlang:element(3, B),
                                    erlang:element(3, A)
                                )
                            end
                        ),
                        gleam@list:take(
                            _pipe@4,
                            erlang:element(2, erlang:element(5, Idx@1))
                        )
                    end,
                    Neighbor_ids = gleam@list:map(
                        Neighbors,
                        fun(R@1) -> erlang:element(2, R@1) end
                    ),
                    Edges_with_new = gleam@dict:insert(
                        erlang:element(2, Layer),
                        Entity,
                        Neighbor_ids
                    ),
                    Final_edges = gleam@list:fold(
                        Neighbor_ids,
                        Edges_with_new,
                        fun(E_acc, N_id) ->
                            Existing = begin
                                _pipe@5 = gleam_stdlib:map_get(E_acc, N_id),
                                unwrap_list(_pipe@5)
                            end,
                            Updated = prune_neighbors(
                                erlang:element(2, erlang:element(5, Idx@1)),
                                N_id,
                                [Entity | Existing],
                                Nodes
                            ),
                            gleam@dict:insert(E_acc, N_id, Updated)
                        end
                    ),
                    New_layers = gleam@dict:insert(
                        Curr_layers,
                        I@1,
                        {layer, Final_edges}
                    ),
                    Next_ep = case gleam@list:first(Neighbors) of
                        {ok, Best} ->
                            erlang:element(2, Best);

                        {error, nil} ->
                            Curr_ep
                    end,
                    {New_layers, Next_ep}
                end
            ),
            {vec_index,
                Nodes,
                Final_layers,
                erlang:element(4, Idx@1),
                erlang:element(5, Idx@1),
                case (Level > erlang:element(7, Idx@1)) orelse gleam@result:is_error(
                    erlang:element(6, Idx@1)
                ) of
                    true ->
                        {ok, Entity};

                    false ->
                        erlang:element(6, Idx@1)
                end,
                New_max_level}
    end.

-file("src/aarondb/vec_index.gleam", 158).
-spec valid_vector(list(float())) -> boolean().
valid_vector(Vec) ->
    aarondb@vec_index@validation:vector_is_valid(Vec).

-file("src/aarondb/vec_index.gleam", 584).
?DOC(" Remove a node from the index across all layers and repair edges.\n").
-spec delete(vec_index(), aarondb@fact:entity_id()) -> vec_index().
delete(Idx, Entity) ->
    Nodes = gleam@dict:delete(erlang:element(2, Idx), Entity),
    Is_empty = gleam@dict:is_empty(Nodes),
    Layers = gleam@dict:map_values(
        erlang:element(3, Idx),
        fun(_, Layer) ->
            Neighbors = begin
                _pipe = gleam_stdlib:map_get(erlang:element(2, Layer), Entity),
                unwrap_list(_pipe)
            end,
            Edges = gleam@dict:delete(erlang:element(2, Layer), Entity),
            Repaired_edges = gleam@list:fold(
                Neighbors,
                Edges,
                fun(Acc, N_id) ->
                    Existing = begin
                        _pipe@1 = gleam_stdlib:map_get(Acc, N_id),
                        unwrap_list(_pipe@1)
                    end,
                    Filtered = gleam@list:filter(
                        Existing,
                        fun(E) -> E /= Entity end
                    ),
                    gleam@dict:insert(Acc, N_id, Filtered)
                end
            ),
            {layer, Repaired_edges}
        end
    ),
    New_entry = case erlang:element(6, Idx) of
        {ok, Ep} when Ep =:= Entity ->
            case gleam_stdlib:map_get(Layers, 0) of
                {ok, L0} ->
                    case begin
                        _pipe@2 = maps:keys(erlang:element(2, L0)),
                        gleam@list:first(_pipe@2)
                    end of
                        {ok, K} ->
                            {ok, K};

                        {error, nil} ->
                            {error, nil}
                    end;

                {error, nil} ->
                    {error, nil}
            end;

        Other ->
            Other
    end,
    {vec_index, Nodes, Layers, case Is_empty of
            true ->
                none;

            false ->
                erlang:element(4, Idx)
        end, erlang:element(5, Idx), New_entry, case Is_empty of
            true ->
                0;

            false ->
                erlang:element(7, Idx)
        end}.

-file("src/aarondb/vec_index.gleam", 674).
?DOC(" Check if the index contains a given entity.\n").
-spec contains(vec_index(), aarondb@fact:entity_id()) -> boolean().
contains(Idx, Entity) ->
    gleam@dict:has_key(erlang:element(2, Idx), Entity).

-file("src/aarondb/vec_index.gleam", 138).
?DOC(
    " Insert a vector, returning `Error` when it is empty, has zero magnitude, or\n"
    " its dimensionality differs from the index. Use this at validation boundaries\n"
    " when an invalid vector must be surfaced to the caller.\n"
).
-spec try_insert(vec_index(), aarondb@fact:entity_id(), list(float())) -> {ok,
        vec_index()} |
    {error, nil}.
try_insert(Idx, Entity, Vec) ->
    Idx@1 = case contains(Idx, Entity) of
        true ->
            delete(Idx, Entity);

        false ->
            Idx
    end,
    Dimensions = aarondb@vector:dimensions(Vec),
    case valid_vector(Vec) of
        false ->
            {error, nil};

        true ->
            case erlang:element(4, Idx@1) of
                {some, Expected} when Expected =/= Dimensions ->
                    {error, nil};

                _ ->
                    {ok, do_insert(Idx@1, Entity, Vec, Dimensions)}
            end
    end.

-file("src/aarondb/vec_index.gleam", 124).
?DOC(
    " Insert a vector into the NSW graph.\n"
    "\n"
    " A vector index has one fixed dimensionality, established by its first vector.\n"
    " A mismatched vector is rejected without changing the index.\n"
).
-spec insert(vec_index(), aarondb@fact:entity_id(), list(float())) -> vec_index().
insert(Idx, Entity, Vec) ->
    case try_insert(Idx, Entity, Vec) of
        {ok, Index} ->
            Index;

        {error, nil} ->
            Idx
    end.

-file("src/aarondb/vec_index.gleam", 398).
-spec valid_query(list(float()), float(), integer()) -> boolean().
valid_query(Query, Threshold, K) ->
    aarondb@vec_index@validation:query_is_valid(Query, Threshold, K).

-file("src/aarondb/vec_index.gleam", 332).
?DOC(
    " Exhaustively score every indexed vector with the same cosine, threshold, and\n"
    " validation rules as `try_search`.\n"
    "\n"
    " This is the deterministic finite-corpus oracle for tests and benchmarks.\n"
    " Unlike HNSW, it is not approximate. Equal scores are ordered by ascending\n"
    " entity ID so callers can compare results mechanically.\n"
).
-spec exact_search(vec_index(), list(float()), float(), integer()) -> {ok,
        list(search_result())} |
    {error, nil}.
exact_search(Idx, Query, Threshold, K) ->
    Dimensions = aarondb@vector:dimensions(Query),
    case valid_query(Query, Threshold, K) of
        false ->
            {error, nil};

        true ->
            case erlang:element(4, Idx) of
                {some, Expected} when Expected =/= Dimensions ->
                    {error, nil};

                _ ->
                    _pipe = aarondb@vec_index@exact:search(
                        erlang:element(2, Idx),
                        Query,
                        Threshold,
                        K
                    ),
                    _pipe@1 = gleam@list:map(
                        _pipe,
                        fun(Result) ->
                            {search_result,
                                erlang:element(1, Result),
                                erlang:element(2, Result)}
                        end
                    ),
                    {ok, _pipe@1}
            end
    end.

-file("src/aarondb/vec_index.gleam", 403).
?DOC(" Uses hierarchical greedy beam search.\n").
-spec do_search(vec_index(), list(float()), float(), integer()) -> list(search_result()).
do_search(Idx, Query, Threshold, K) ->
    case erlang:element(6, Idx) of
        {error, nil} ->
            [];

        {ok, Start} ->
            Query@1 = aarondb@vector:normalize(Query),
            Ep_0 = descend_to_level(
                Idx,
                Query@1,
                Start,
                erlang:element(7, Idx),
                1
            ),
            Layer_0 = begin
                _pipe = gleam_stdlib:map_get(erlang:element(3, Idx), 0),
                gleam@result:unwrap(_pipe, {layer, maps:new()})
            end,
            Vec_ep = begin
                _pipe@1 = gleam_stdlib:map_get(erlang:element(2, Idx), Ep_0),
                gleam@result:unwrap(_pipe@1, Query@1)
            end,
            Ep_res = {search_result,
                Ep_0,
                aarondb@vector:dot_product(Query@1, Vec_ep)},
            Results = greedy_search(
                erlang:element(2, Idx),
                erlang:element(2, Layer_0),
                Query@1,
                [Ep_0],
                maps:new(),
                [Ep_res],
                erlang:element(3, erlang:element(5, Idx))
            ),
            _pipe@2 = Results,
            _pipe@3 = gleam@list:filter(
                _pipe@2,
                fun(R) -> erlang:element(3, R) >= Threshold end
            ),
            _pipe@4 = gleam@list:sort(_pipe@3, fun compare_search_results/2),
            gleam@list:take(_pipe@4, K)
    end.

-file("src/aarondb/vec_index.gleam", 381).
?DOC(
    " Search for vectors similar to `query`.\n"
    "\n"
    " Returns `Error` when the query is empty, has zero magnitude, does not match\n"
    " the index dimensions, `threshold` is outside `[-1.0, 1.0]`, or `k` is not\n"
    " positive. This prevents invalid inputs from receiving ambiguous scores.\n"
).
-spec try_search(vec_index(), list(float()), float(), integer()) -> {ok,
        list(search_result())} |
    {error, nil}.
try_search(Idx, Query, Threshold, K) ->
    Dimensions = aarondb@vector:dimensions(Query),
    case valid_query(Query, Threshold, K) of
        false ->
            {error, nil};

        true ->
            case erlang:element(4, Idx) of
                {some, Expected} when Expected =/= Dimensions ->
                    {error, nil};

                _ ->
                    {ok, do_search(Idx, Query, Threshold, K)}
            end
    end.

-file("src/aarondb/vec_index.gleam", 364).
?DOC(" Search using the HNSW approximation, returning an empty list for invalid input.\n").
-spec search(vec_index(), list(float()), float(), integer()) -> list(search_result()).
search(Idx, Query, Threshold, K) ->
    case try_search(Idx, Query, Threshold, K) of
        {ok, Results} ->
            Results;

        {error, nil} ->
            []
    end.

-file("src/aarondb/vec_index.gleam", 669).
?DOC(" Get the number of vectors in the index.\n").
-spec size(vec_index()) -> integer().
size(Idx) ->
    maps:size(erlang:element(2, Idx)).
