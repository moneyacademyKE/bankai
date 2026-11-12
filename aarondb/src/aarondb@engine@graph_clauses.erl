-module(aarondb@engine@graph_clauses).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/graph_clauses.gleam").
-export([shortest_path/8, pagerank/7, reachable/5, connected_components/5, neighbors/6, strongly_connected/5, cycle_detect/4, betweenness/5, topological_sort/5]).

-file("src/aarondb/engine/graph_clauses.gleam", 221).
-spec resolve_part(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:value()).
resolve_part(Part, Ctx) ->
    case Part of
        {var, Name} ->
            gleam@option:from_result(gleam_stdlib:map_get(Ctx, Name));

        {val, Val} ->
            {some, Val};

        {uid, Uid} ->
            {some, {ref, Uid}};

        {attr_val, S} ->
            {some, {str, S}};

        {lookup, {_, Val@1}} ->
            {some, Val@1}
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 210).
-spec resolve_entity_id(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:entity_id()).
resolve_entity_id(Part, Ctx) ->
    case resolve_part(Part, Ctx) of
        {some, {ref, Eid}} ->
            {some, Eid};

        {some, {int, I}} ->
            {some, {entity_id, I}};

        _ ->
            none
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 9).
-spec shortest_path(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    binary(),
    binary(),
    gleam@option:option(binary()),
    gleam@option:option(integer()),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
shortest_path(Db_state, From, To, Edge, Path_var, Cost_var, Max_depth, Ctx) ->
    From_eid = resolve_entity_id(From, Ctx),
    To_eid = resolve_entity_id(To, Ctx),
    case {From_eid, To_eid} of
        {{some, F}, {some, T}} ->
            case aarondb@algo@graph:shortest_path(
                Db_state,
                F,
                T,
                Edge,
                Max_depth
            ) of
                {some, Path} ->
                    Path_val = {list,
                        gleam@list:map(Path, fun(Field@0) -> {ref, Field@0} end)},
                    Ctx@1 = gleam@dict:insert(Ctx, Path_var, Path_val),
                    Ctx@2 = case Cost_var of
                        {some, Cv} ->
                            gleam@dict:insert(
                                Ctx@1,
                                Cv,
                                {int, erlang:length(Path) - 1}
                            );

                        none ->
                            Ctx@1
                    end,
                    [Ctx@2];

                none ->
                    []
            end;

        {_, _} ->
            []
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 180).
-spec bind_score_map(
    gleam@dict:dict(aarondb@fact:entity_id(), float()),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
bind_score_map(Values, Entity_var, Value_var, Ctx) ->
    case gleam_stdlib:map_get(Ctx, Entity_var) of
        {ok, {ref, Eid}} ->
            case gleam_stdlib:map_get(Values, Eid) of
                {ok, Value} ->
                    [gleam@dict:insert(Ctx, Value_var, {float, Value})];

                {error, _} ->
                    []
            end;

        {ok, {int, Eid_int}} ->
            case gleam_stdlib:map_get(Values, {entity_id, Eid_int}) of
                {ok, Value@1} ->
                    [gleam@dict:insert(Ctx, Value_var, {float, Value@1})];

                {error, _} ->
                    []
            end;

        {error, _} ->
            gleam@dict:fold(
                Values,
                [],
                fun(Acc, Eid@1, Value@2) ->
                    New_ctx = gleam@dict:insert(Ctx, Entity_var, {ref, Eid@1}),
                    New_ctx@1 = gleam@dict:insert(
                        New_ctx,
                        Value_var,
                        {float, Value@2}
                    ),
                    [New_ctx@1 | Acc]
                end
            );

        _ ->
            []
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 41).
-spec pagerank(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    binary(),
    float(),
    integer(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
pagerank(Db_state, Entity_var, Edge, Rank_var, Damping, Iterations, Ctx) ->
    Ranks = aarondb@algo@graph:pagerank(Db_state, Edge, Damping, Iterations),
    bind_score_map(Ranks, Entity_var, Rank_var, Ctx).

-file("src/aarondb/engine/graph_clauses.gleam", 54).
-spec reachable(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:part(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
reachable(Db_state, From, Edge, Node_var, Ctx) ->
    case resolve_entity_id(From, Ctx) of
        {some, Eid} ->
            _pipe = aarondb@algo@graph:reachable(Db_state, Eid, Edge),
            gleam@list:map(
                _pipe,
                fun(N) -> gleam@dict:insert(Ctx, Node_var, {ref, N}) end
            );

        none ->
            []
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 150).
-spec bind_int_map(
    gleam@dict:dict(aarondb@fact:entity_id(), integer()),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
bind_int_map(Values, Entity_var, Value_var, Ctx) ->
    case gleam_stdlib:map_get(Ctx, Entity_var) of
        {ok, {ref, Eid}} ->
            case gleam_stdlib:map_get(Values, Eid) of
                {ok, Value} ->
                    [gleam@dict:insert(Ctx, Value_var, {int, Value})];

                {error, _} ->
                    []
            end;

        {ok, {int, Eid_int}} ->
            case gleam_stdlib:map_get(Values, {entity_id, Eid_int}) of
                {ok, Value@1} ->
                    [gleam@dict:insert(Ctx, Value_var, {int, Value@1})];

                {error, _} ->
                    []
            end;

        {error, _} ->
            gleam@dict:fold(
                Values,
                [],
                fun(Acc, Eid@1, Value@2) ->
                    New_ctx = gleam@dict:insert(Ctx, Entity_var, {ref, Eid@1}),
                    New_ctx@1 = gleam@dict:insert(
                        New_ctx,
                        Value_var,
                        {int, Value@2}
                    ),
                    [New_ctx@1 | Acc]
                end
            );

        _ ->
            []
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 70).
-spec connected_components(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
connected_components(Db_state, Edge, Entity_var, Component_var, Ctx) ->
    _pipe = aarondb@algo@graph:connected_components(Db_state, Edge),
    bind_int_map(_pipe, Entity_var, Component_var, Ctx).

-file("src/aarondb/engine/graph_clauses.gleam", 81).
-spec neighbors(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:part(),
    binary(),
    integer(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
neighbors(Db_state, From, Edge, Depth, Node_var, Ctx) ->
    case resolve_entity_id(From, Ctx) of
        {some, Eid} ->
            _pipe = aarondb@algo@graph:neighbors_khop(
                Db_state,
                Eid,
                Edge,
                Depth
            ),
            gleam@list:map(
                _pipe,
                fun(N) -> gleam@dict:insert(Ctx, Node_var, {ref, N}) end
            );

        none ->
            []
    end.

-file("src/aarondb/engine/graph_clauses.gleam", 98).
-spec strongly_connected(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
strongly_connected(Db_state, Edge, Entity_var, Component_var, Ctx) ->
    _pipe = aarondb@algo@graph:strongly_connected_components(Db_state, Edge),
    bind_int_map(_pipe, Entity_var, Component_var, Ctx).

-file("src/aarondb/engine/graph_clauses.gleam", 109).
-spec cycle_detect(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
cycle_detect(Db_state, Edge, Cycle_var, Ctx) ->
    _pipe = aarondb@algo@graph:cycle_detect(Db_state, Edge),
    gleam@list:map(
        _pipe,
        fun(Cycle) ->
            gleam@dict:insert(
                Ctx,
                Cycle_var,
                {list,
                    gleam@list:map(Cycle, fun(Field@0) -> {ref, Field@0} end)}
            )
        end
    ).

-file("src/aarondb/engine/graph_clauses.gleam", 121).
-spec betweenness(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
betweenness(Db_state, Edge, Entity_var, Score_var, Ctx) ->
    _pipe = aarondb@algo@graph:betweenness_centrality(Db_state, Edge),
    bind_score_map(_pipe, Entity_var, Score_var, Ctx).

-file("src/aarondb/engine/graph_clauses.gleam", 132).
-spec topological_sort(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
topological_sort(Db_state, Edge, Entity_var, Order_var, Ctx) ->
    case aarondb@algo@graph:topological_sort(Db_state, Edge) of
        {ok, Ordered} ->
            gleam@list:index_map(
                Ordered,
                fun(Node, Idx) ->
                    New_ctx = gleam@dict:insert(Ctx, Entity_var, {ref, Node}),
                    gleam@dict:insert(New_ctx, Order_var, {int, Idx})
                end
            );

        {error, _} ->
            []
    end.
