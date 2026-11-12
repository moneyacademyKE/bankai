-module(aarondb@engine@aggregate_clause).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/aggregate_clause.gleam").
-export([solve/7]).

-file("src/aarondb/engine/aggregate_clause.gleam", 136).
-spec get_values_row_based(
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    binary(),
    fun((aarondb@engine@solver_context:solver_context(), list(aarondb@shared@ast:body_clause()), list(gleam@dict:dict(binary(), aarondb@fact:value()))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> list(aarondb@fact:value()).
get_values_row_based(Solver, Clauses, Ctx, Target_var, Nested_solve) ->
    {Sub_results, _} = case Clauses of
        [] ->
            {[Ctx], none};

        _ ->
            Nested_solve(Solver, Clauses, [Ctx])
    end,
    gleam@list:filter_map(
        Sub_results,
        fun(Res) -> gleam_stdlib:map_get(Res, Target_var) end
    ).

-file("src/aarondb/engine/aggregate_clause.gleam", 169).
-spec gleam_result_unwrap({ok, IUS} | {error, any()}, IUS) -> IUS.
gleam_result_unwrap(Res, Default) ->
    case Res of
        {ok, V} ->
            V;

        {error, _} ->
            Default
    end.

-file("src/aarondb/engine/aggregate_clause.gleam", 63).
-spec columnar_aggregate(
    gleam@dict:dict(binary(), aarondb@fact:value()),
    binary(),
    aarondb@shared@ast:agg_func(),
    binary(),
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    list(aarondb@shared@ast:body_clause()),
    fun((aarondb@engine@solver_context:solver_context(), list(aarondb@shared@ast:body_clause()), list(gleam@dict:dict(binary(), aarondb@fact:value()))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
columnar_aggregate(
    Ctx,
    Var,
    Func,
    Target_var,
    Solver,
    Clauses,
    Filters,
    Nested_solve
) ->
    Chunks = begin
        _pipe = gleam_stdlib:map_get(
            erlang:element(23, erlang:element(2, Solver)),
            Target_var
        ),
        gleam_result_unwrap(_pipe, [])
    end,
    Cracking_pivots = gleam@list:filter_map(Filters, fun(C) -> case C of
                {filter, {gt, {var, V}, {val, P}}} when V =:= Target_var ->
                    {ok, P};

                {filter, {lt, {var, V@1}, {val, P@1}}} when V@1 =:= Target_var ->
                    {ok, P@1};

                _ ->
                    {error, nil}
            end end),
    {Updated_chunks, Was_cracked} = case Cracking_pivots of
        [Pivot | _] ->
            Nc = gleam@list:map(
                Chunks,
                fun(C@1) -> aarondb@algo@cracking:crack_chunk(C@1, Pivot) end
            ),
            {Nc, true};

        _ ->
            {Chunks, false}
    end,
    Agg_val = case Func of
        sum ->
            {float,
                gleam@list:fold(
                    Updated_chunks,
                    +0.0,
                    fun(Acc, C@2) ->
                        Acc + aarondb@algo@vectorized:sum_column(C@2)
                    end
                )};

        avg ->
            Total_sum = gleam@list:fold(
                Updated_chunks,
                +0.0,
                fun(Acc@1, C@3) ->
                    Acc@1 + aarondb@algo@vectorized:sum_column(C@3)
                end
            ),
            Total_count = gleam@list:fold(
                Updated_chunks,
                0,
                fun(Acc@2, C@4) ->
                    Acc@2 + aarondb@algo@vectorized:count_node(
                        erlang:element(3, C@4)
                    )
                end
            ),
            case Total_count of
                0 ->
                    {float, +0.0};

                _ ->
                    {float, case erlang:float(Total_count) of
                            +0.0 -> +0.0;
                            -0.0 -> -0.0;
                            Gleam@denominator -> Total_sum / Gleam@denominator
                        end}
            end;

        _ ->
            Target_values = get_values_row_based(
                Solver,
                Clauses,
                Ctx,
                Target_var,
                Nested_solve
            ),
            case aarondb@algo@aggregate:aggregate(Target_values, Func) of
                {ok, Val} ->
                    Val;

                {error, _} ->
                    {int, 0}
            end
    end,
    Res_ctx = [gleam@dict:insert(Ctx, Var, Agg_val)],
    Updated_store = case Was_cracked of
        true ->
            {some, maps:from_list([{Target_var, Updated_chunks}])};

        false ->
            none
    end,
    {Res_ctx, Updated_store}.

-file("src/aarondb/engine/aggregate_clause.gleam", 151).
-spec schema_config(aarondb@shared@state:db_state(), binary()) -> aarondb@fact:attribute_config().
schema_config(Db_state, Attribute) ->
    _pipe = gleam_stdlib:map_get(erlang:element(8, Db_state), Attribute),
    gleam_result_unwrap(
        _pipe,
        {attribute_config,
            false,
            false,
            all,
            many,
            none,
            none,
            row,
            memory,
            always_in_memory}
    ).

-file("src/aarondb/engine/aggregate_clause.gleam", 25).
-spec solve(
    gleam@dict:dict(binary(), aarondb@fact:value()),
    binary(),
    aarondb@shared@ast:agg_func(),
    binary(),
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    fun((aarondb@engine@solver_context:solver_context(), list(aarondb@shared@ast:body_clause()), list(gleam@dict:dict(binary(), aarondb@fact:value()))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve(Ctx, Var, Func, Target_var, Solver, Clauses, Nested_solve) ->
    Config = schema_config(erlang:element(2, Solver), Target_var),
    case {erlang:element(8, Config), Clauses} of
        {columnar, Filters} ->
            columnar_aggregate(
                Ctx,
                Var,
                Func,
                Target_var,
                Solver,
                Clauses,
                Filters,
                Nested_solve
            );

        {_, _} ->
            Target_values = get_values_row_based(
                Solver,
                Clauses,
                Ctx,
                Target_var,
                Nested_solve
            ),
            case aarondb@algo@aggregate:aggregate(Target_values, Func) of
                {ok, Val} ->
                    {[gleam@dict:insert(Ctx, Var, Val)], none};

                {error, _} ->
                    {[], none}
            end
    end.
