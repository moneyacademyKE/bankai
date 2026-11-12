-module(aarondb@engine@executor).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/executor.gleam").
-export([merge_stores/2, execute/4]).
-export_type([execution_result/0]).

-type execution_result() :: {execution_result,
        list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.

-file("src/aarondb/engine/executor.gleam", 60).
-spec merge_stores(
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))
) -> gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))).
merge_stores(S1, S2) ->
    case {S1, S2} of
        {{some, M1}, {some, M2}} ->
            {some, maps:merge(M1, M2)};

        {{some, _}, none} ->
            S1;

        {none, {some, _}} ->
            S2;

        {none, none} ->
            none
    end.

-file("src/aarondb/engine/executor.gleam", 72).
-spec solve_all_contexts(
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))),
    aarondb@shared@ast:body_clause(),
    fun((aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_all_contexts(Contexts, Current_store, Clause, Solve) ->
    gleam@list:fold(
        Contexts,
        {[], Current_store},
        fun(Acc, Ctx) ->
            {Acc_ctxs, Acc_store} = Acc,
            {New_ctxs, Clause_store} = Solve(Clause, Ctx, Acc_store),
            {lists:append(Acc_ctxs, New_ctxs),
                merge_stores(Acc_store, Clause_store)}
        end
    ).

-file("src/aarondb/engine/executor.gleam", 104).
-spec reverse_order(gleam@order:order()) -> gleam@order:order().
reverse_order(Ord) ->
    case Ord of
        lt ->
            gt;

        gt ->
            lt;

        eq ->
            eq
    end.

-file("src/aarondb/engine/executor.gleam", 88).
-spec order_by_clause(
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    binary(),
    aarondb@shared@ast:order_direction()
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
order_by_clause(Contexts, Var, Dir) ->
    gleam@list:sort(
        Contexts,
        fun(A, B) ->
            Val_a = begin
                _pipe = gleam_stdlib:map_get(A, Var),
                gleam@result:unwrap(_pipe, {int, 0})
            end,
            Val_b = begin
                _pipe@1 = gleam_stdlib:map_get(B, Var),
                gleam@result:unwrap(_pipe@1, {int, 0})
            end,
            Ord = aarondb@fact:compare(Val_a, Val_b),
            case Dir of
                asc ->
                    Ord;

                desc ->
                    reverse_order(Ord)
            end
        end
    ).

-file("src/aarondb/engine/executor.gleam", 29).
-spec execute(
    list(aarondb@shared@ast:body_clause()),
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))),
    fun((aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> execution_result().
execute(Clauses, Initial_contexts, Initial_store, Solve) ->
    {Rows, Store} = gleam@list:fold(
        Clauses,
        {Initial_contexts, Initial_store},
        fun(Acc, Clause) ->
            {Contexts, Current_store} = Acc,
            case Clause of
                {limit_clause, N} ->
                    {gleam@list:take(Contexts, N), Current_store};

                {offset_clause, N@1} ->
                    {gleam@list:drop(Contexts, N@1), Current_store};

                {order_by_clause, Var, Dir} ->
                    {order_by_clause(Contexts, Var, Dir), Current_store};

                {group_by, _} ->
                    {Contexts, Current_store};

                {filter, Expr} ->
                    Compiled_pred = aarondb@engine@predicate:compile(Expr),
                    {gleam@list:filter(
                            Contexts,
                            fun(Ctx) -> Compiled_pred(Ctx) end
                        ),
                        Current_store};

                _ ->
                    solve_all_contexts(Contexts, Current_store, Clause, Solve)
            end
        end
    ),
    {execution_result, Rows, Store}.
