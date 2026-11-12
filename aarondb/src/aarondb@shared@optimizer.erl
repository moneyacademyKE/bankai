-module(aarondb@shared@optimizer).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/optimizer.gleam").
-export([optimize/1, explain/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/shared/optimizer.gleam", 200).
-spec get_var_name(aarondb@shared@ast:part()) -> {ok, binary()} | {error, nil}.
get_var_name(Part) ->
    case Part of
        {var, Name} ->
            {ok, Name};

        _ ->
            {error, nil}
    end.

-file("src/aarondb/shared/optimizer.gleam", 207).
-spec get_expr_vars(aarondb@shared@ast:expression()) -> gleam@set:set(binary()).
get_expr_vars(Expr) ->
    case Expr of
        {eq, A, B} ->
            gleam@set:from_list(
                gleam@list:filter_map([A, B], fun get_var_name/1)
            );

        {neq, A, B} ->
            gleam@set:from_list(
                gleam@list:filter_map([A, B], fun get_var_name/1)
            );

        {gt, A, B} ->
            gleam@set:from_list(
                gleam@list:filter_map([A, B], fun get_var_name/1)
            );

        {lt, A, B} ->
            gleam@set:from_list(
                gleam@list:filter_map([A, B], fun get_var_name/1)
            );

        {'and', L, R} ->
            gleam@set:union(get_expr_vars(L), get_expr_vars(R));

        {'or', L, R} ->
            gleam@set:union(get_expr_vars(L), get_expr_vars(R))
    end.

-file("src/aarondb/shared/optimizer.gleam", 124).
-spec get_clause_vars(aarondb@shared@ast:body_clause()) -> gleam@set:set(binary()).
get_clause_vars(Clause) ->
    case Clause of
        {positive, {E, _, V}} ->
            gleam@set:from_list(
                gleam@list:filter_map([E, V], fun get_var_name/1)
            );

        {negative, {E@1, _, V@1}} ->
            gleam@set:from_list(
                gleam@list:filter_map([E@1, V@1], fun get_var_name/1)
            );

        {filter, Expr} ->
            get_expr_vars(Expr);

        {bind, Var, Val} ->
            S = case get_var_name(Var) of
                {ok, N} ->
                    gleam@set:from_list([N]);

                {error, _} ->
                    gleam@set:new()
            end,
            case get_var_name(Val) of
                {ok, N@1} ->
                    gleam@set:insert(S, N@1);

                {error, _} ->
                    S
            end;

        {aggregate, Var@1, _, Target, Filter} ->
            Sub_vars = begin
                _pipe = gleam@list:map(Filter, fun get_clause_vars/1),
                gleam@list:fold(_pipe, gleam@set:new(), fun gleam@set:union/2)
            end,
            S@1 = gleam@set:insert(Sub_vars, Var@1),
            case get_var_name(Target) of
                {ok, N@2} ->
                    gleam@set:insert(S@1, N@2);

                {error, _} ->
                    S@1
            end;

        {starts_with, Var@2, _} ->
            gleam@set:from_list([Var@2]);

        {similarity, Var@3, Target@1, _} ->
            S@2 = gleam@set:from_list([Var@3]),
            case get_var_name(Target@1) of
                {ok, N@3} ->
                    gleam@set:insert(S@2, N@3);

                {error, _} ->
                    S@2
            end;

        {temporal, _, _, _, Var@4, Entity, _} ->
            S@3 = gleam@set:from_list([Var@4]),
            case get_var_name(Entity) of
                {ok, Name} ->
                    gleam@set:insert(S@3, Name);

                {error, _} ->
                    S@3
            end;

        {cognitive, Concept, Context, _, Engram_var} ->
            S@4 = gleam@set:from_list([Engram_var]),
            S@5 = case get_var_name(Concept) of
                {ok, N@4} ->
                    gleam@set:insert(S@4, N@4);

                {error, _} ->
                    S@4
            end,
            case get_var_name(Context) of
                {ok, N@5} ->
                    gleam@set:insert(S@5, N@5);

                {error, _} ->
                    S@5
            end;

        {shortest_path, From, To, _, Path_var, Cost_var, _} ->
            S@6 = gleam@set:from_list([Path_var]),
            S@7 = case Cost_var of
                {some, Cv} ->
                    gleam@set:insert(S@6, Cv);

                none ->
                    S@6
            end,
            S@8 = case get_var_name(From) of
                {ok, N@6} ->
                    gleam@set:insert(S@7, N@6);

                {error, _} ->
                    S@7
            end,
            case get_var_name(To) of
                {ok, N@7} ->
                    gleam@set:insert(S@8, N@7);

                {error, _} ->
                    S@8
            end;

        {page_rank, Entity_var, _, Rank_var, _, _} ->
            gleam@set:from_list([Entity_var, Rank_var]);

        {virtual, _, Args, Outputs} ->
            Arg_vars = begin
                _pipe@1 = gleam@list:filter_map(Args, fun get_var_name/1),
                gleam@set:from_list(_pipe@1)
            end,
            Output_vars = gleam@set:from_list(Outputs),
            gleam@set:union(Arg_vars, Output_vars);

        _ ->
            gleam@set:new()
    end.

-file("src/aarondb/shared/optimizer.gleam", 114).
-spec is_part_bound(aarondb@shared@ast:part(), gleam@set:set(binary())) -> boolean().
is_part_bound(Part, Bound_vars) ->
    case Part of
        {val, _} ->
            true;

        {var, Name} ->
            gleam@set:contains(Bound_vars, Name);

        {uid, _} ->
            true;

        {attr_val, _} ->
            true;

        {lookup, _} ->
            true
    end.

-file("src/aarondb/shared/optimizer.gleam", 69).
-spec estimate_cost(aarondb@shared@ast:body_clause(), gleam@set:set(binary())) -> integer().
estimate_cost(Clause, Bound_vars) ->
    case Clause of
        {positive, {E, _, V}} ->
            E_bound = is_part_bound(E, Bound_vars),
            V_bound = is_part_bound(V, Bound_vars),
            case {E_bound, V_bound} of
                {true, true} ->
                    1;

                {true, false} ->
                    10;

                {false, true} ->
                    100;

                {false, false} ->
                    1000
            end;

        {negative, _} ->
            5000;

        {filter, Expr} ->
            Expr_vars = get_expr_vars(Expr),
            All_bound = gleam@set:fold(
                Expr_vars,
                true,
                fun(Acc, V@1) ->
                    Acc andalso gleam@set:contains(Bound_vars, V@1)
                end
            ),
            case All_bound of
                true ->
                    2;

                false ->
                    8000
            end;

        {bind, _, _} ->
            2;

        {aggregate, _, _, _, Sub_filter} ->
            2000 + (erlang:length(Sub_filter) * 100);

        {similarity, _, _, _} ->
            50;

        {temporal, _, _, _, _, _, _} ->
            150;

        {shortest_path, _, _, _, _, _, _} ->
            500;

        {page_rank, _, _, _, _, _} ->
            1000;

        {cognitive, _, _, _, _} ->
            500;

        {starts_with, Var, _} ->
            case gleam@set:contains(Bound_vars, Var) of
                true ->
                    10;

                false ->
                    50
            end;

        {virtual, _, Args, _} ->
            Bound_args = gleam@list:filter(
                Args,
                fun(A) -> is_part_bound(A, Bound_vars) end
            ),
            1000 - (erlang:length(Bound_args) * 100);

        _ ->
            9999
    end.

-file("src/aarondb/shared/optimizer.gleam", 56).
-spec find_best_clause(
    list(aarondb@shared@ast:body_clause()),
    gleam@set:set(binary())
) -> {ok,
        {aarondb@shared@ast:body_clause(),
            list(aarondb@shared@ast:body_clause())}} |
    {error, nil}.
find_best_clause(Clauses, Bound_vars) ->
    Scored = gleam@list:map(
        Clauses,
        fun(C) -> {C, estimate_cost(C, Bound_vars)} end
    ),
    Sorted = gleam@list:sort(
        Scored,
        fun(A, B) ->
            gleam@int:compare(erlang:element(2, A), erlang:element(2, B))
        end
    ),
    case Sorted of
        [{Best, _} | Rest] ->
            {ok,
                {Best,
                    gleam@list:map(
                        Rest,
                        fun(Pair) -> erlang:element(1, Pair) end
                    )}};

        [] ->
            {error, nil}
    end.

-file("src/aarondb/shared/optimizer.gleam", 42).
-spec greedy_reorder(
    list(aarondb@shared@ast:body_clause()),
    gleam@set:set(binary())
) -> list(aarondb@shared@ast:body_clause()).
greedy_reorder(Remaining, Bound_vars) ->
    case find_best_clause(Remaining, Bound_vars) of
        {ok, {Best, Others}} ->
            Clause_vars = get_clause_vars(Best),
            Next_bound = gleam@set:union(Bound_vars, Clause_vars),
            [Best | greedy_reorder(Others, Next_bound)];

        {error, nil} ->
            []
    end.

-file("src/aarondb/shared/optimizer.gleam", 35).
-spec is_control_clause(aarondb@shared@ast:body_clause()) -> boolean().
is_control_clause(Clause) ->
    case Clause of
        {graph_group_by, _} ->
            true;

        _ ->
            false
    end.

-file("src/aarondb/shared/optimizer.gleam", 29).
-spec plan(list(aarondb@shared@ast:body_clause())) -> list(aarondb@shared@ast:body_clause()).
plan(Clauses) ->
    {Control, Data} = gleam@list:partition(Clauses, fun is_control_clause/1),
    Ordered_data = greedy_reorder(Data, gleam@set:new()),
    lists:append(Ordered_data, Control).

-file("src/aarondb/shared/optimizer.gleam", 16).
?DOC(
    " Optimizes a Query by reordering its where clauses for efficient execution.\n"
    " Rich Hickey alignment: \"Query optimization is a pure data transformation.\"\n"
).
-spec optimize(aarondb@shared@ast:'query'()) -> aarondb@shared@ast:'query'().
optimize(Query) ->
    Planned_clauses = plan(erlang:element(3, Query)),
    {'query',
        erlang:element(2, Query),
        Planned_clauses,
        erlang:element(4, Query),
        erlang:element(5, Query),
        erlang:element(6, Query)}.

-file("src/aarondb/shared/optimizer.gleam", 261).
-spec part_to_string(aarondb@shared@ast:part()) -> binary().
part_to_string(P) ->
    case P of
        {var, N} ->
            <<"?"/utf8, N/binary>>;

        {val, V} ->
            aarondb@fact:to_string(V);

        {uid, _} ->
            <<"UID"/utf8>>;

        {attr_val, V@1} ->
            V@1;

        {lookup, _} ->
            <<"Lookup"/utf8>>
    end.

-file("src/aarondb/shared/optimizer.gleam", 217).
-spec clause_to_string(aarondb@shared@ast:body_clause()) -> binary().
clause_to_string(Clause) ->
    case Clause of
        {positive, {E, A, V}} ->
            <<<<<<<<<<<<"Positive("/utf8, (part_to_string(E))/binary>>/binary,
                                ", "/utf8>>/binary,
                            A/binary>>/binary,
                        ", "/utf8>>/binary,
                    (part_to_string(V))/binary>>/binary,
                ")"/utf8>>;

        {negative, {E@1, A@1, V@1}} ->
            <<<<<<<<<<<<"Negative("/utf8, (part_to_string(E@1))/binary>>/binary,
                                ", "/utf8>>/binary,
                            A@1/binary>>/binary,
                        ", "/utf8>>/binary,
                    (part_to_string(V@1))/binary>>/binary,
                ")"/utf8>>;

        {filter, _} ->
            <<"Filter(...)"/utf8>>;

        {similarity, V@2, _, _} ->
            <<<<"Similarity("/utf8, V@2/binary>>/binary, ")"/utf8>>;

        {temporal, _, _, _, V@3, E@2, _} ->
            <<<<<<<<"Temporal("/utf8, V@3/binary>>/binary, ", "/utf8>>/binary,
                    (part_to_string(E@2))/binary>>/binary,
                ")"/utf8>>;

        {cognitive, Concept, Context, _, Var} ->
            <<<<<<<<<<<<"Cognitive(concept="/utf8,
                                    (part_to_string(Concept))/binary>>/binary,
                                ", context="/utf8>>/binary,
                            (part_to_string(Context))/binary>>/binary,
                        ", var="/utf8>>/binary,
                    Var/binary>>/binary,
                ")"/utf8>>;

        {virtual, P, Args, Outputs} ->
            <<<<<<<<<<<<"Virtual("/utf8, P/binary>>/binary, ", count="/utf8>>/binary,
                            (erlang:integer_to_binary(erlang:length(Args)))/binary>>/binary,
                        ", outputs="/utf8>>/binary,
                    (gleam@string:inspect(Outputs))/binary>>/binary,
                ")"/utf8>>;

        {shortest_path, _, _, E@3, V@4, _, _} ->
            <<<<<<<<"ShortestPath(edge="/utf8, E@3/binary>>/binary,
                        ", var="/utf8>>/binary,
                    V@4/binary>>/binary,
                ")"/utf8>>;

        _ ->
            <<"OtherClause"/utf8>>
    end.

-file("src/aarondb/shared/optimizer.gleam", 21).
-spec explain(list(aarondb@shared@ast:body_clause())) -> binary().
explain(Clauses) ->
    Planned = plan(Clauses),
    _pipe = gleam@list:map(
        Planned,
        fun(C) -> <<"  - "/utf8, (clause_to_string(C))/binary>> end
    ),
    _pipe@1 = gleam@list:prepend(_pipe, <<"Query Plan:"/utf8>>),
    _pipe@2 = gleam@list:intersperse(_pipe@1, <<"\n"/utf8>>),
    gleam@list:fold(
        _pipe@2,
        <<""/utf8>>,
        fun(Acc, S) -> <<Acc/binary, S/binary>> end
    ).
