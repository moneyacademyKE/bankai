-module(aarondb@engine@temporal_clause).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/temporal_clause.gleam").
-export([solve/9]).

-file("src/aarondb/engine/temporal_clause.gleam", 84).
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

-file("src/aarondb/engine/temporal_clause.gleam", 109).
-spec option_from_result({ok, LDW} | {error, any()}) -> gleam@option:option(LDW).
option_from_result(Res) ->
    case Res of
        {ok, V} ->
            {some, V};

        {error, _} ->
            none
    end.

-file("src/aarondb/engine/temporal_clause.gleam", 96).
-spec resolve_part(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:value()).
resolve_part(Part, Ctx) ->
    case Part of
        {var, Name} ->
            option_from_result(gleam_stdlib:map_get(Ctx, Name));

        {val, Val} ->
            {some, Val};

        {uid, Uid} ->
            {some, {ref, Uid}};

        {attr_val, S} ->
            {some, {str, S}};

        {lookup, {_, Val@1}} ->
            {some, Val@1}
    end.

-file("src/aarondb/engine/temporal_clause.gleam", 24).
-spec solve(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:temporal_type(),
    integer(),
    aarondb@shared@ast:temporal_op(),
    binary(),
    aarondb@shared@ast:part(),
    list(aarondb@shared@ast:body_clause()),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
solve(
    Db_state,
    Type_,
    Time,
    Op,
    Variable,
    Entity_p,
    Clauses,
    Ctx,
    Solve_with_derived
) ->
    _ = resolve_part(Entity_p, Ctx),
    As_of_tx = case Type_ of
        tx ->
            case Op of
                at ->
                    {some, Time};

                since ->
                    {some, Time};

                until ->
                    {some, Time};

                _ ->
                    none
            end;

        _ ->
            none
    end,
    As_of_valid = case Type_ of
        valid ->
            case Op of
                at ->
                    {some, Time};

                since ->
                    {some, Time};

                until ->
                    {some, Time};

                _ ->
                    none
            end;

        _ ->
            none
    end,
    Initial_context = [Ctx],
    {Rows, _} = gleam@list:fold(
        Clauses,
        {Initial_context, none},
        fun(Acc, Clause) ->
            {Contexts, Current_store} = Acc,
            gleam@list:fold(
                Contexts,
                {[], Current_store},
                fun(Inner_acc, C) ->
                    {Acc_ctxs, Acc_store} = Inner_acc,
                    {New_ctxs, Clause_store} = Solve_with_derived(
                        Db_state,
                        Clause,
                        C,
                        gleam@set:new(),
                        As_of_tx,
                        As_of_valid
                    ),
                    {lists:append(Acc_ctxs, New_ctxs),
                        merge_stores(Acc_store, Clause_store)}
                end
            )
        end
    ),
    gleam@list:map(
        Rows,
        fun(R) -> gleam@dict:insert(R, Variable, {int, Time}) end
    ).
