-module(aarondb@engine@solver@recursive).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/recursive.gleam").
-export([solve_clauses/5, nested_solve/4]).

-file("src/aarondb/engine/solver/recursive.gleam", 26).
-spec solve_clauses(
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), list(aarondb@shared@ast:rule()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_clauses(Solver, Clauses, Contexts, Initial_store, Solve) ->
    case Clauses of
        [] ->
            {Contexts, Initial_store};

        [First | Rest] ->
            {Next_contexts, Next_store} = case erlang:length(Contexts) > erlang:element(
                2,
                erlang:element(24, erlang:element(2, Solver))
            ) of
                true ->
                    Subject = gleam@erlang@process:new_subject(),
                    proc_lib:spawn_link(
                        fun() ->
                            Res = gleam@list:fold(
                                Contexts,
                                {[], Initial_store},
                                fun(Acc, Ctx) ->
                                    {Acc_ctxs, Acc_store} = Acc,
                                    {New_ctxs, Clause_store} = Solve(
                                        erlang:element(2, Solver),
                                        First,
                                        Ctx,
                                        erlang:element(3, Solver),
                                        erlang:element(5, Solver),
                                        erlang:element(6, Solver)
                                    ),
                                    {lists:append(Acc_ctxs, New_ctxs),
                                        aarondb@engine@solver@stores:merge_optional_stores(
                                            Acc_store,
                                            Clause_store
                                        )}
                                end
                            ),
                            gleam@erlang@process:send(Subject, Res)
                        end
                    ),
                    Res@2 = case gleam@erlang@process:'receive'(Subject, 60000) of
                        {ok, Res@1} -> Res@1;
                        _assert_fail ->
                            erlang:error(#{gleam_error => let_assert,
                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                        file => <<?FILEPATH/utf8>>,
                                        module => <<"aarondb/engine/solver/recursive"/utf8>>,
                                        function => <<"solve_clauses"/utf8>>,
                                        line => 64,
                                        value => _assert_fail,
                                        start => 1865,
                                        'end' => 1918,
                                        pattern_start => 1876,
                                        pattern_end => 1883})
                    end,
                    Res@2;

                false ->
                    gleam@list:fold(
                        Contexts,
                        {[], Initial_store},
                        fun(Acc@1, Ctx@1) ->
                            {Acc_ctxs@1, Acc_store@1} = Acc@1,
                            {New_ctxs@1, Clause_store@1} = Solve(
                                erlang:element(2, Solver),
                                First,
                                Ctx@1,
                                erlang:element(3, Solver),
                                erlang:element(5, Solver),
                                erlang:element(6, Solver)
                            ),
                            {lists:append(Acc_ctxs@1, New_ctxs@1),
                                aarondb@engine@solver@stores:merge_optional_stores(
                                    Acc_store@1,
                                    Clause_store@1
                                )}
                        end
                    )
            end,
            solve_clauses(Solver, Rest, Next_contexts, Next_store, Solve)
    end.

-file("src/aarondb/engine/solver/recursive.gleam", 91).
-spec nested_solve(
    aarondb@engine@solver_context:solver_context(),
    list(aarondb@shared@ast:body_clause()),
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), list(aarondb@shared@ast:rule()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
nested_solve(Solver, Clauses, Contexts, Solve) ->
    solve_clauses(Solver, Clauses, Contexts, none, Solve).
