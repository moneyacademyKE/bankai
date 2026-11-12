-module(aarondb@engine@rules).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/rules.gleam").
-export([derive_all_facts/6]).

-file("src/aarondb/engine/rules.gleam", 155).
-spec insert_if_new(
    gleam@set:set(aarondb@fact:datom()),
    gleam@set:set(aarondb@fact:datom()),
    binary(),
    integer(),
    aarondb@fact:value()
) -> gleam@set:set(aarondb@fact:datom()).
insert_if_new(All_derived, Acc, Attribute, Eid_val, Val) ->
    D = {datom, {entity_id, Eid_val}, Attribute, Val, 0, 0, 0, assert},
    case gleam@set:contains(All_derived, D) of
        true ->
            Acc;

        false ->
            gleam@set:insert(Acc, D)
    end.

-file("src/aarondb/engine/rules.gleam", 178).
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

-file("src/aarondb/engine/rules.gleam", 126).
-spec solve_rule_body_semi_naive(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:body_clause()),
    gleam@set:set(aarondb@fact:datom()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))})
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
solve_rule_body_semi_naive(
    Db_state,
    Body,
    All_derived,
    As_of_tx,
    As_of_valid,
    Solve_clause_with_derived
) ->
    gleam@list:fold(
        Body,
        {[maps:new()], none},
        fun(Acc, Clause_i) ->
            {Ctxs, Current_store} = Acc,
            gleam@list:fold(
                Ctxs,
                {[], Current_store},
                fun(Inner_acc, Ctx) ->
                    {Acc_ctxs, Acc_store} = Inner_acc,
                    {New_ctxs, Clause_store} = Solve_clause_with_derived(
                        Db_state,
                        Clause_i,
                        Ctx,
                        All_derived,
                        As_of_tx,
                        As_of_valid
                    ),
                    {lists:append(Acc_ctxs, New_ctxs),
                        merge_stores(Acc_store, Clause_store)}
                end
            )
        end
    ).

-file("src/aarondb/engine/rules.gleam", 68).
-spec do_derive_recursive(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    gleam@set:set(aarondb@fact:datom()),
    gleam@set:set(aarondb@fact:datom()),
    boolean(),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}),
    fun((aarondb@shared@ast:part(), gleam@dict:dict(binary(), aarondb@fact:value())) -> gleam@option:option(aarondb@fact:value()))
) -> gleam@set:set(aarondb@fact:datom()).
do_derive_recursive(
    Db_state,
    Rules,
    As_of_tx,
    As_of_valid,
    All_derived,
    Last_new_derived,
    First_run,
    Solve_clause_with_derived,
    Resolve_part_optional
) ->
    case not First_run andalso (gleam@set:size(Last_new_derived) =:= 0) of
        true ->
            All_derived;

        false ->
            Next_new = gleam@list:fold(
                Rules,
                gleam@set:new(),
                fun(Acc, R) ->
                    {Results, _} = solve_rule_body_semi_naive(
                        Db_state,
                        erlang:element(3, R),
                        All_derived,
                        As_of_tx,
                        As_of_valid,
                        Solve_clause_with_derived
                    ),
                    gleam@list:fold(
                        Results,
                        Acc,
                        fun(Inner_acc, Ctx) ->
                            E = Resolve_part_optional(
                                erlang:element(1, erlang:element(2, R)),
                                Ctx
                            ),
                            V = Resolve_part_optional(
                                erlang:element(3, erlang:element(2, R)),
                                Ctx
                            ),
                            case {E, V} of
                                {{some, {ref, {entity_id, Eid_val}}},
                                    {some, Val}} ->
                                    insert_if_new(
                                        All_derived,
                                        Inner_acc,
                                        erlang:element(2, erlang:element(2, R)),
                                        Eid_val,
                                        Val
                                    );

                                {{some, {int, Eid_val@1}}, {some, Val@1}} ->
                                    insert_if_new(
                                        All_derived,
                                        Inner_acc,
                                        erlang:element(2, erlang:element(2, R)),
                                        Eid_val@1,
                                        Val@1
                                    );

                                {_, _} ->
                                    Inner_acc
                            end
                        end
                    )
                end
            ),
            case gleam@set:size(Next_new) =:= 0 of
                true ->
                    All_derived;

                false ->
                    do_derive_recursive(
                        Db_state,
                        Rules,
                        As_of_tx,
                        As_of_valid,
                        gleam@set:union(All_derived, Next_new),
                        Next_new,
                        false,
                        Solve_clause_with_derived,
                        Resolve_part_optional
                    )
            end
    end.

-file("src/aarondb/engine/rules.gleam", 46).
-spec do_derive(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    gleam@set:set(aarondb@fact:datom()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}),
    fun((aarondb@shared@ast:part(), gleam@dict:dict(binary(), aarondb@fact:value())) -> gleam@option:option(aarondb@fact:value()))
) -> gleam@set:set(aarondb@fact:datom()).
do_derive(
    Db_state,
    Rules,
    As_of_tx,
    As_of_valid,
    Derived,
    Solve_clause_with_derived,
    Resolve_part_optional
) ->
    do_derive_recursive(
        Db_state,
        Rules,
        As_of_tx,
        As_of_valid,
        Derived,
        Derived,
        true,
        Solve_clause_with_derived,
        Resolve_part_optional
    ).

-file("src/aarondb/engine/rules.gleam", 27).
-spec derive_all_facts(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:rule()),
    gleam@option:option(integer()),
    gleam@option:option(integer()),
    fun((aarondb@shared@state:db_state(), aarondb@shared@ast:body_clause(), gleam@dict:dict(binary(), aarondb@fact:value()), gleam@set:set(aarondb@fact:datom()), gleam@option:option(integer()), gleam@option:option(integer())) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}),
    fun((aarondb@shared@ast:part(), gleam@dict:dict(binary(), aarondb@fact:value())) -> gleam@option:option(aarondb@fact:value()))
) -> gleam@set:set(aarondb@fact:datom()).
derive_all_facts(
    Db_state,
    Rules,
    As_of_tx,
    As_of_valid,
    Solve_clause_with_derived,
    Resolve_part_optional
) ->
    do_derive(
        Db_state,
        Rules,
        As_of_tx,
        As_of_valid,
        gleam@set:new(),
        Solve_clause_with_derived,
        Resolve_part_optional
    ).
