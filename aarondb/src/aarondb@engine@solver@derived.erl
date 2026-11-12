-module(aarondb@engine@solver@derived).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/derived.gleam").
-export([solve_clause_with_derived/7, solve_with_context/4]).

-file("src/aarondb/engine/solver/derived.gleam", 45).
-spec solve_clause_with_derived(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@set:set(aarondb@fact:datom()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), list(aarondb@shared@ast:rule()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_clause_with_derived(
    Db_state,
    Clause,
    Ctx,
    All_derived,
    As_of_tx,
    As_of_valid,
    Solve_clause
) ->
    case Clause of
        {positive, Trip} ->
            {aarondb@engine@solver@triple:solve(
                    Db_state,
                    Trip,
                    Ctx,
                    All_derived,
                    As_of_tx,
                    As_of_valid
                ),
                none};

        {negative, Trip@1} ->
            case aarondb@engine@solver@triple:solve(
                Db_state,
                Trip@1,
                Ctx,
                All_derived,
                As_of_tx,
                As_of_valid
            ) of
                [] ->
                    {[Ctx], none};

                _ ->
                    {[], none}
            end;

        _ ->
            Solve_clause(
                Db_state,
                Clause,
                Ctx,
                erlang:element(21, Db_state),
                As_of_tx,
                As_of_valid
            )
    end.

-file("src/aarondb/engine/solver/derived.gleam", 25).
-spec solve_with_context(
    aarondb@engine@solver_context:solver_context(),
    aarondb@shared@ast:body_clause(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), list(aarondb@shared@ast:rule()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_with_context(Solver, Clause, Ctx, Solve_clause) ->
    solve_clause_with_derived(
        erlang:element(2, Solver),
        Clause,
        Ctx,
        erlang:element(4, Solver),
        erlang:element(5, Solver),
        erlang:element(6, Solver),
        Solve_clause
    ).
