-module(aarondb@engine@planner).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/planner.gleam").
-export([build/1, order_rows/2, page_rows/3]).
-export_type([query_plan/0]).

-type query_plan() :: {query_plan,
        aarondb@shared@ast:'query'(),
        list(aarondb@shared@ast:body_clause()),
        gleam@dict:dict(binary(), aarondb@shared@ast:agg_func())}.

-file("src/aarondb/engine/planner.gleam", 63).
-spec collect_aggregates(list(aarondb@shared@ast:body_clause())) -> gleam@dict:dict(binary(), aarondb@shared@ast:agg_func()).
collect_aggregates(Clauses) ->
    gleam@list:fold(Clauses, maps:new(), fun(Acc, Clause) -> case Clause of
                {aggregate, Var, Func, _, _} ->
                    gleam@dict:insert(Acc, Var, Func);

                _ ->
                    Acc
            end end).

-file("src/aarondb/engine/planner.gleam", 18).
-spec build(aarondb@shared@ast:'query'()) -> query_plan().
build(Query) ->
    Optimized = aarondb@shared@optimizer:optimize(Query),
    Clauses = erlang:element(3, Optimized),
    {query_plan, Optimized, Clauses, collect_aggregates(Clauses)}.

-file("src/aarondb/engine/planner.gleam", 74).
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

-file("src/aarondb/engine/planner.gleam", 28).
-spec order_rows(
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(aarondb@shared@ast:order_by())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
order_rows(Rows, Order_by) ->
    case Order_by of
        {some, {order_by, Var, Dir}} ->
            gleam@list:sort(
                Rows,
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
            );

        none ->
            Rows
    end.

-file("src/aarondb/engine/planner.gleam", 48).
-spec page_rows(
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
page_rows(Rows, Offset, Limit) ->
    Rows@1 = case Offset of
        {some, N} ->
            gleam@list:drop(Rows, N);

        none ->
            Rows
    end,
    case Limit of
        {some, N@1} ->
            gleam@list:take(Rows@1, N@1);

        none ->
            Rows@1
    end.
