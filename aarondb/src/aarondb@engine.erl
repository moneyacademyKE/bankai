-module(aarondb@engine).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine.gleam").
-export([run/5, entity_history/2, pull/3, pull_result_to_value/1, traverse/4, diff/3, diff_ordered/3, explain/1, filter_by_time/3, solve_cognitive/8]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/engine.gleam", 167).
-spec solve_clause_with_derived(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@set:set(aarondb@fact:datom()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_clause_with_derived(
    Db_state,
    Clause,
    Ctx,
    All_derived,
    As_of_tx,
    As_of_valid
) ->
    aarondb@engine@solver@derived:solve_clause_with_derived(
        Db_state,
        Clause,
        Ctx,
        All_derived,
        As_of_tx,
        As_of_valid,
        fun solve_clause/6
    ).

-file("src/aarondb/engine.gleam", 122).
-spec nested_solve(
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    list(gleam@dict:dict(binary(), aarondb@fact:value()))
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
nested_solve(Solver, Clauses, Contexts) ->
    aarondb@engine@solver@recursive:nested_solve(
        Solver,
        Clauses,
        Contexts,
        fun solve_clause/6
    ).

-file("src/aarondb/engine.gleam", 133).
-spec solve_clause(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_clause(Db_state, Clause, Ctx, Rules, As_of_tx, As_of_valid) ->
    aarondb@engine@solver@core:solve_clause(
        Db_state,
        Clause,
        Ctx,
        Rules,
        As_of_tx,
        As_of_valid,
        fun nested_solve/3,
        fun solve_clause_with_derived/6
    ).

-file("src/aarondb/engine.gleam", 156).
-spec solve_with_context(
    aarondb@engine@solver_context:solver_context(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_with_context(Solver, Clause, Ctx) ->
    aarondb@engine@solver@derived:solve_with_context(
        Solver,
        Clause,
        Ctx,
        fun solve_clause/6
    ).

-file("src/aarondb/engine.gleam", 32).
-spec run(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:'query'(),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> aarondb@shared@query_types:query_result().
run(Db_state, Query, Rules, As_of_tx, As_of_valid) ->
    _ = erlang:element(3, Query),
    As_of_v = case As_of_valid of
        {some, Vt} ->
            {some, Vt};

        none ->
            {some, 2147483647}
    end,
    All_rules = lists:append(Rules, erlang:element(21, Db_state)),
    All_derived = aarondb@engine@rules:derive_all_facts(
        Db_state,
        All_rules,
        As_of_tx,
        As_of_v,
        fun solve_clause_with_derived/6,
        fun aarondb@engine@solver@bindings:resolve_part_optional/2
    ),
    Solver = {solver_context,
        Db_state,
        All_rules,
        All_derived,
        As_of_tx,
        As_of_v},
    Initial_context = [maps:new()],
    Plan = aarondb@engine@planner:build(Query),
    Planned_clauses = erlang:element(3, Plan),
    gleam@list:each(Planned_clauses, fun(C) -> case C of
                {page_rank, _, Edge, _, _, _} ->
                    Config = gleam_stdlib:map_get(
                        erlang:element(8, Db_state),
                        Edge
                    ),
                    case Config of
                        {ok, Conf} when erlang:element(5, Conf) =/= many ->
                            _ = io:format(
                                <<<<"⚠️ Warning: Graph edge '"/utf8,
                                        Edge/binary>>/binary,
                                    "' should be Ref(EntityId) for optimal performance."/utf8>>
                            );

                        _ ->
                            nil
                    end;

                {cycle_detect, Edge, _} ->
                    Config = gleam_stdlib:map_get(
                        erlang:element(8, Db_state),
                        Edge
                    ),
                    case Config of
                        {ok, Conf} when erlang:element(5, Conf) =/= many ->
                            _ = io:format(
                                <<<<"⚠️ Warning: Graph edge '"/utf8,
                                        Edge/binary>>/binary,
                                    "' should be Ref(EntityId) for optimal performance."/utf8>>
                            );

                        _ ->
                            nil
                    end;

                {strongly_connected_components, Edge, _, _} ->
                    Config = gleam_stdlib:map_get(
                        erlang:element(8, Db_state),
                        Edge
                    ),
                    case Config of
                        {ok, Conf} when erlang:element(5, Conf) =/= many ->
                            _ = io:format(
                                <<<<"⚠️ Warning: Graph edge '"/utf8,
                                        Edge/binary>>/binary,
                                    "' should be Ref(EntityId) for optimal performance."/utf8>>
                            );

                        _ ->
                            nil
                    end;

                {topological_sort, Edge, _, _} ->
                    Config = gleam_stdlib:map_get(
                        erlang:element(8, Db_state),
                        Edge
                    ),
                    case Config of
                        {ok, Conf} when erlang:element(5, Conf) =/= many ->
                            _ = io:format(
                                <<<<"⚠️ Warning: Graph edge '"/utf8,
                                        Edge/binary>>/binary,
                                    "' should be Ref(EntityId) for optimal performance."/utf8>>
                            );

                        _ ->
                            nil
                    end;

                _ ->
                    nil
            end end),
    Execution = aarondb@engine@executor:execute(
        Planned_clauses,
        Initial_context,
        none,
        fun(Clause, Ctx, _) -> solve_with_context(Solver, Clause, Ctx) end
    ),
    Rows = begin
        _pipe = erlang:element(2, Execution),
        _pipe@1 = aarondb@engine@planner:order_rows(
            _pipe,
            erlang:element(4, erlang:element(2, Plan))
        ),
        aarondb@engine@planner:page_rows(
            _pipe@1,
            erlang:element(6, erlang:element(2, Plan)),
            erlang:element(5, erlang:element(2, Plan))
        )
    end,
    {query_result,
        begin
            _pipe@2 = Rows,
            gleam@list:unique(_pipe@2)
        end,
        {query_metadata,
            As_of_tx,
            As_of_valid,
            0,
            0,
            <<""/utf8>>,
            none,
            erlang:element(4, Plan)},
        erlang:element(3, Execution)}.

-file("src/aarondb/engine.gleam", 189).
-spec entity_history(aarondb@shared@state:db_state(), aarondb@fact:entity_id()) -> list(aarondb@fact:datom()).
entity_history(Db_state, Eid) ->
    aarondb@engine@entity:entity_history(Db_state, Eid).

-file("src/aarondb/engine.gleam", 196).
-spec pull(
    aarondb@shared@state:db_state(),
    aarondb@fact:entity_id(),
    list(aarondb@shared@ast:pull_item())
) -> aarondb@shared@query_types:pull_result().
pull(Db_state, Eid, Pattern) ->
    aarondb@engine@entity:pull(Db_state, Eid, Pattern).

-file("src/aarondb/engine.gleam", 204).
-spec pull_result_to_value(aarondb@shared@query_types:pull_result()) -> aarondb@fact:value().
pull_result_to_value(Res) ->
    aarondb@engine@entity:pull_result_to_value(Res).

-file("src/aarondb/engine.gleam", 208).
-spec traverse(
    aarondb@shared@state:db_state(),
    integer(),
    list(aarondb@shared@query_types:traversal_step()),
    integer()
) -> {ok, list(aarondb@fact:value())} | {error, binary()}.
traverse(Db_state, Start_id, Expr, Max_depth) ->
    aarondb@engine@traversal:traverse(Db_state, Start_id, Expr, Max_depth).

-file("src/aarondb/engine.gleam", 247).
-spec diff(aarondb@shared@state:db_state(), integer(), integer()) -> list(aarondb@fact:datom()).
diff(Db_state, From_tx, To_tx) ->
    _pipe = aarondb@index:get_all_datoms(erlang:element(3, Db_state)),
    gleam@list:filter(
        _pipe,
        fun(D) ->
            (erlang:element(5, D) > From_tx) andalso (erlang:element(5, D) =< To_tx)
        end
    ).

-file("src/aarondb/engine.gleam", 268).
-spec compare_diff_datoms(aarondb@fact:datom(), aarondb@fact:datom()) -> gleam@order:order().
compare_diff_datoms(Left, Right) ->
    case gleam@int:compare(erlang:element(5, Left), erlang:element(5, Right)) of
        eq ->
            case gleam@int:compare(
                erlang:element(6, Left),
                erlang:element(6, Right)
            ) of
                eq ->
                    case aarondb@fact:compare(
                        erlang:element(4, Left),
                        erlang:element(4, Right)
                    ) of
                        eq ->
                            gleam@string:compare(
                                erlang:element(3, Left),
                                erlang:element(3, Right)
                            );

                        Other ->
                            Other
                    end;

                Other@1 ->
                    Other@1
            end;

        Other@2 ->
            Other@2
    end.

-file("src/aarondb/engine.gleam", 259).
?DOC(
    " Returns `(from_tx, to_tx]` ordered by transaction, transaction-local index,\n"
    " then a stable datom tie-breaker. This is the ordering used by the bounded\n"
    " public diff contract.\n"
).
-spec diff_ordered(aarondb@shared@state:db_state(), integer(), integer()) -> list(aarondb@fact:datom()).
diff_ordered(Db_state, From_tx, To_tx) ->
    _pipe = diff(Db_state, From_tx, To_tx),
    gleam@list:sort(_pipe, fun compare_diff_datoms/2).

-file("src/aarondb/engine.gleam", 285).
-spec explain(list(aarondb@shared@ast:body_clause())) -> binary().
explain(Clauses) ->
    aarondb@engine@navigator:explain(Clauses).

-file("src/aarondb/engine.gleam", 289).
-spec filter_by_time(
    list(aarondb@fact:datom()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(aarondb@fact:datom()).
filter_by_time(Datoms, Tx_limit, Valid_limit) ->
    _pipe = Datoms,
    gleam@list:filter(
        _pipe,
        fun(D) ->
            Tx_ok = case Tx_limit of
                {some, Tx} ->
                    erlang:element(5, D) =< Tx;

                none ->
                    true
            end,
            Valid_ok = case Valid_limit of
                {some, Vt} ->
                    erlang:element(7, D) =< Vt;

                none ->
                    true
            end,
            Tx_ok andalso Valid_ok
        end
    ).

-file("src/aarondb/engine.gleam", 308).
-spec solve_cognitive(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    float(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
solve_cognitive(
    Db_state,
    Concept,
    Context,
    Threshold,
    Engram_var,
    Ctx,
    As_of_tx,
    As_of_valid
) ->
    aarondb@engine@cognitive:solve(
        Db_state,
        Concept,
        Context,
        Threshold,
        Engram_var,
        Ctx,
        As_of_tx,
        As_of_valid
    ).
