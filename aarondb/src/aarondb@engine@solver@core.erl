-module(aarondb@engine@solver@core).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/core.gleam").
-export([solve_clause/8]).

-file("src/aarondb/engine/solver/core.gleam", 26).
-spec solve_clause(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    fun((aarondb@engine@solver_context:solver_context(), list(aarondb@shared@ast:body_clause()), list(gleam@dict:dict(binary(), aarondb@fact:value()))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_clause(
    Db_state,
    Clause,
    Ctx,
    Rules,
    As_of_tx,
    As_of_valid,
    Nested_solve,
    Solve_clause_with_derived
) ->
    case Clause of
        {positive, C} ->
            {Res, Store} = aarondb@engine@solver@positive:positive_with_state(
                Db_state,
                C,
                Ctx,
                As_of_tx,
                As_of_valid
            ),
            {Res, Store};

        {negative, C@1} ->
            {aarondb@engine@solver@positive:negative(
                    Db_state,
                    C@1,
                    Ctx,
                    As_of_tx,
                    As_of_valid
                ),
                none};

        {aggregate, Var, Func, Target_p, Filter_clauses} ->
            Target_var = case Target_p of
                {var, N} ->
                    N;

                _ ->
                    <<""/utf8>>
            end,
            aarondb@engine@aggregate_clause:solve(
                Ctx,
                Var,
                Func,
                Target_var,
                {solver_context,
                    Db_state,
                    Rules,
                    gleam@set:new(),
                    As_of_tx,
                    As_of_valid},
                Filter_clauses,
                Nested_solve
            );

        {similarity, Var@1, Target_p@1, Threshold} ->
            Vec = aarondb@engine@solver@vector_input:vector_from_part(
                Target_p@1,
                Ctx
            ),
            {aarondb@engine@retrieval:similarity(
                    Db_state,
                    Var@1,
                    Vec,
                    Threshold,
                    Ctx,
                    As_of_tx,
                    As_of_valid
                ),
                none};

        {similarity_entity, Var@2, Target_p@2, Threshold@1} ->
            Vec@1 = aarondb@engine@solver@vector_input:vector_from_part(
                Target_p@2,
                Ctx
            ),
            {aarondb@engine@retrieval:similarity_entity(
                    Db_state,
                    Var@2,
                    Vec@1,
                    Threshold@1,
                    Ctx
                ),
                none};

        {cognitive, Concept, Context, Threshold@2, Engram_var} ->
            {aarondb@engine@cognitive:solve(
                    Db_state,
                    Concept,
                    Context,
                    Threshold@2,
                    Engram_var,
                    Ctx,
                    As_of_tx,
                    As_of_valid
                ),
                none};

        {custom_index, Var@3, Name, Q, T} ->
            State_q = case Q of
                {text_query, Txt} ->
                    {text_query, Txt};

                {numeric_range, Min, Max} ->
                    {numeric_range, Min, Max};

                {custom, Data} ->
                    {custom, Data}
            end,
            {aarondb@engine@retrieval:custom_index(
                    Db_state,
                    Var@3,
                    Name,
                    State_q,
                    T,
                    Ctx,
                    As_of_tx,
                    As_of_valid
                ),
                none};

        {filter, Expr} ->
            Compiled_pred = aarondb@engine@predicate:compile(Expr),
            case Compiled_pred(Ctx) of
                true ->
                    {[Ctx], none};

                false ->
                    {[], none}
            end;

        {bind, Var_p, Val_p} ->
            Var_name = case Var_p of
                {var, N@1} ->
                    N@1;

                _ ->
                    <<""/utf8>>
            end,
            Val = begin
                _pipe = aarondb@engine@solver@bindings:resolve_part(Val_p, Ctx),
                gleam@option:unwrap(_pipe, {int, 0})
            end,
            {[gleam@dict:insert(Ctx, Var_name, Val)], none};

        {temporal, Type_, Time, Op, Var@4, Entity_p, Clauses} ->
            {aarondb@engine@temporal_clause:solve(
                    Db_state,
                    Type_,
                    Time,
                    Op,
                    Var@4,
                    Entity_p,
                    Clauses,
                    Ctx,
                    Solve_clause_with_derived
                ),
                none};

        {shortest_path, From, To, Edge, Path_var, Cost_var, Max_depth} ->
            {aarondb@engine@graph_clauses:shortest_path(
                    Db_state,
                    From,
                    To,
                    Edge,
                    Path_var,
                    Cost_var,
                    Max_depth,
                    Ctx
                ),
                none};

        {page_rank, Entity_var, Edge@1, Rank_var, Damping, Iterations} ->
            {aarondb@engine@graph_clauses:pagerank(
                    Db_state,
                    Entity_var,
                    Edge@1,
                    Rank_var,
                    Damping,
                    Iterations,
                    Ctx
                ),
                none};

        {virtual, Pred, Args, Outputs} ->
            {aarondb@engine@virtual:solve(Db_state, Pred, Args, Outputs, Ctx),
                none};

        {reachable, From@1, Edge@2, Node_var} ->
            {aarondb@engine@graph_clauses:reachable(
                    Db_state,
                    From@1,
                    Edge@2,
                    Node_var,
                    Ctx
                ),
                none};

        {connected_components, Edge@3, Entity_var@1, Component_var} ->
            {aarondb@engine@graph_clauses:connected_components(
                    Db_state,
                    Edge@3,
                    Entity_var@1,
                    Component_var,
                    Ctx
                ),
                none};

        {neighbors, From@2, Edge@4, Depth, Node_var@1} ->
            {aarondb@engine@graph_clauses:neighbors(
                    Db_state,
                    From@2,
                    Edge@4,
                    Depth,
                    Node_var@1,
                    Ctx
                ),
                none};

        {cycle_detect, Edge@5, Cycle_var} ->
            {aarondb@engine@graph_clauses:cycle_detect(
                    Db_state,
                    Edge@5,
                    Cycle_var,
                    Ctx
                ),
                none};

        {betweenness_centrality, Edge@6, Entity_var@2, Score_var} ->
            {aarondb@engine@graph_clauses:betweenness(
                    Db_state,
                    Edge@6,
                    Entity_var@2,
                    Score_var,
                    Ctx
                ),
                none};

        {topological_sort, Edge@7, Entity_var@3, Order_var} ->
            {aarondb@engine@graph_clauses:topological_sort(
                    Db_state,
                    Edge@7,
                    Entity_var@3,
                    Order_var,
                    Ctx
                ),
                none};

        {strongly_connected_components, Edge@8, Entity_var@4, Component_var@1} ->
            {aarondb@engine@graph_clauses:strongly_connected(
                    Db_state,
                    Edge@8,
                    Entity_var@4,
                    Component_var@1,
                    Ctx
                ),
                none};

        {starts_with, Var@5, Prefix} ->
            {aarondb@engine@string_clause:starts_with(
                    Db_state,
                    Var@5,
                    Prefix,
                    Ctx
                ),
                none};

        {pull, Var@6, Entity_p@1, Pattern} ->
            case aarondb@engine@solver@bindings:resolve_part(Entity_p@1, Ctx) of
                {some, {ref, Eid}} ->
                    Res@1 = aarondb@engine@entity:pull(Db_state, Eid, Pattern),
                    {[gleam@dict:insert(
                                Ctx,
                                Var@6,
                                aarondb@engine@entity:pull_result_to_value(
                                    Res@1
                                )
                            )],
                        none};

                {some, {int, Eid_int}} ->
                    Res@2 = aarondb@engine@entity:pull(
                        Db_state,
                        {entity_id, Eid_int},
                        Pattern
                    ),
                    {[gleam@dict:insert(
                                Ctx,
                                Var@6,
                                aarondb@engine@entity:pull_result_to_value(
                                    Res@2
                                )
                            )],
                        none};

                _ ->
                    {[], none}
            end;

        _ ->
            {[Ctx], none}
    end.
