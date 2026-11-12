-module(aarondb@transactor@apply).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/apply.gleam").
-export([update_indices/2, apply_datom/3, resolve_transaction_functions/4]).

-file("src/aarondb/transactor/apply.gleam", 214).
-spec update_columnar_store(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom()
) -> gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())).
update_columnar_store(State, D) ->
    Chunks = begin
        _pipe = gleam_stdlib:map_get(
            erlang:element(23, State),
            erlang:element(3, D)
        ),
        gleam@result:unwrap(_pipe, [])
    end,
    case Chunks of
        [] ->
            Chunk = {storage_chunk,
                erlang:element(3, D),
                {leaf, [erlang:element(4, D)]},
                0,
                false},
            gleam@dict:insert(
                erlang:element(23, State),
                erlang:element(3, D),
                [Chunk]
            );

        [Last | Rest] ->
            Updated = case erlang:element(3, Last) of
                {leaf, L} ->
                    {leaf, lists:append(L, [erlang:element(4, D)])};

                Node ->
                    Node
            end,
            gleam@dict:insert(
                erlang:element(23, State),
                erlang:element(3, D),
                [{storage_chunk,
                        erlang:element(2, Last),
                        Updated,
                        erlang:element(4, Last),
                        erlang:element(5, Last)} |
                    Rest]
            )
    end.

-file("src/aarondb/transactor/apply.gleam", 37).
-spec update_indices(aarondb@shared@state:db_state(), aarondb@fact:datom()) -> aarondb@shared@state:db_state().
update_indices(State, D) ->
    Art_index = aarondb@index@art:insert(
        erlang:element(17, State),
        erlang:element(4, D),
        erlang:element(2, D)
    ),
    Vec_index = case erlang:element(4, D) of
        {vec, V} ->
            case erlang:element(8, D) of
                assert ->
                    aarondb@vec_index:insert(
                        erlang:element(15, State),
                        erlang:element(2, D),
                        V
                    );

                retract ->
                    erlang:element(15, State)
            end;

        _ ->
            erlang:element(15, State)
    end,
    Columnar_store = case erlang:element(8, D) of
        assert ->
            update_columnar_store(State, D);

        _ ->
            erlang:element(23, State)
    end,
    State@1 = {db_state,
        erlang:element(2, State),
        aarondb@index:insert_eavt(erlang:element(3, State), D, all),
        aarondb@index:insert_aevt(erlang:element(4, State), D, all),
        aarondb@index:insert_avet(erlang:element(5, State), D),
        erlang:element(6, State),
        erlang:element(7, State),
        erlang:element(8, State),
        erlang:element(9, State),
        erlang:element(10, State),
        erlang:element(11, State),
        erlang:element(12, State),
        erlang:element(13, State),
        erlang:element(14, State),
        Vec_index,
        erlang:element(16, State),
        Art_index,
        erlang:element(18, State),
        erlang:element(19, State),
        erlang:element(20, State),
        erlang:element(21, State),
        erlang:element(22, State),
        Columnar_store,
        erlang:element(24, State),
        erlang:element(25, State)},
    case erlang:element(14, State@1) of
        {some, Name} ->
            _ = aarondb@index@ets:insert_datom(
                <<Name/binary, "_eavt"/utf8>>,
                erlang:element(2, D),
                D
            ),
            _ = aarondb@index@ets:insert_datom(
                <<Name/binary, "_aevt"/utf8>>,
                erlang:element(3, D),
                D
            ),
            Avet_table = <<Name/binary, "_avet"/utf8>>,
            case erlang:element(8, D) of
                assert ->
                    aarondb@index@ets:insert_avet(
                        Avet_table,
                        {erlang:element(3, D), erlang:element(4, D)},
                        erlang:element(2, D)
                    );

                retract ->
                    aarondb@index@ets:delete(
                        Avet_table,
                        {erlang:element(3, D), erlang:element(4, D)}
                    )
            end,
            State@1;

        none ->
            State@1
    end.

-file("src/aarondb/transactor/apply.gleam", 197).
-spec retention_policy(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom(),
    aarondb@fact:attribute_config()
) -> aarondb@shared@state:db_state().
retention_policy(State, D, Config) ->
    case (erlang:element(4, Config) =:= latest_only) andalso (erlang:element(
        8,
        D
    )
    =:= assert) of
        true ->
            Existing = aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, State),
                erlang:element(2, D),
                erlang:element(3, D)
            ),
            gleam@list:fold(
                Existing,
                State,
                fun(Acc, Old_d) ->
                    {db_state,
                        erlang:element(2, Acc),
                        aarondb@index:evict_from_memory(
                            erlang:element(3, Acc),
                            [Old_d]
                        ),
                        erlang:element(4, Acc),
                        erlang:element(5, Acc),
                        erlang:element(6, Acc),
                        erlang:element(7, Acc),
                        erlang:element(8, Acc),
                        erlang:element(9, Acc),
                        erlang:element(10, Acc),
                        erlang:element(11, Acc),
                        erlang:element(12, Acc),
                        erlang:element(13, Acc),
                        erlang:element(14, Acc),
                        erlang:element(15, Acc),
                        erlang:element(16, Acc),
                        erlang:element(17, Acc),
                        erlang:element(18, Acc),
                        erlang:element(19, Acc),
                        erlang:element(20, Acc),
                        erlang:element(21, Acc),
                        erlang:element(22, Acc),
                        erlang:element(23, Acc),
                        erlang:element(24, Acc),
                        erlang:element(25, Acc)}
                end
            );

        false ->
            State
    end.

-file("src/aarondb/transactor/apply.gleam", 165).
-spec cardinality_one(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom(),
    integer(),
    aarondb@fact:attribute_config()
) -> {aarondb@shared@state:db_state(), list(aarondb@fact:datom()), integer()}.
cardinality_one(State, D, Tx_idx_counter, Config) ->
    case (erlang:element(5, Config) =:= one) andalso (erlang:element(8, D) =:= assert) of
        true ->
            All_datoms = aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, State),
                erlang:element(2, D),
                erlang:element(3, D)
            ),
            Asserts = gleam@list:filter(
                All_datoms,
                fun(D@1) -> erlang:element(8, D@1) =:= assert end
            ),
            Retractions = gleam@list:filter(
                All_datoms,
                fun(D@2) -> erlang:element(8, D@2) =:= retract end
            ),
            Active_asserts = gleam@list:filter(
                Asserts,
                fun(Ad) ->
                    not gleam@list:any(
                        Retractions,
                        fun(Rd) ->
                            (erlang:element(4, Rd) =:= erlang:element(4, Ad))
                            andalso (erlang:element(5, Rd) >= erlang:element(
                                5,
                                Ad
                            ))
                        end
                    )
                end
            ),
            gleam@list:fold(
                Active_asserts,
                {State, [], Tx_idx_counter},
                fun(Acc, Old_d) ->
                    {S, Ds, I} = Acc,
                    R_d = {datom,
                        erlang:element(2, Old_d),
                        erlang:element(3, Old_d),
                        erlang:element(4, Old_d),
                        erlang:element(5, D),
                        I,
                        erlang:element(7, Old_d),
                        retract},
                    {update_indices(S, R_d), [R_d | Ds], I + 1}
                end
            );

        false ->
            {State, [], Tx_idx_counter}
    end.

-file("src/aarondb/transactor/apply.gleam", 137).
-spec component_cascade(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom(),
    integer(),
    aarondb@fact:attribute_config()
) -> {aarondb@shared@state:db_state(), list(aarondb@fact:datom()), integer()}.
component_cascade(State, D, Tx_idx_counter, Config) ->
    case erlang:element(3, Config) andalso (erlang:element(8, D) =:= retract) of
        true ->
            Children = case erlang:element(4, D) of
                {ref, Eid} ->
                    [Eid];

                {int, Eid_int} ->
                    [{entity_id, Eid_int}];

                _ ->
                    []
            end,
            gleam@list:fold(
                Children,
                {State, [], Tx_idx_counter},
                fun(Acc, Child_eid) ->
                    {Curr_state, Curr_datoms, Idx} = Acc,
                    Child_datoms = aarondb@index:filter_by_entity(
                        erlang:element(3, Curr_state),
                        Child_eid
                    ),
                    gleam@list:fold(
                        Child_datoms,
                        {Curr_state, Curr_datoms, Idx},
                        fun(Acc2, Cd) ->
                            {S2, D2, I2} = Acc2,
                            R_d = {datom,
                                erlang:element(2, Cd),
                                erlang:element(3, Cd),
                                erlang:element(4, Cd),
                                erlang:element(5, D),
                                I2,
                                erlang:element(7, Cd),
                                retract},
                            {update_indices(S2, R_d), [R_d | D2], I2 + 1}
                        end
                    )
                end
            );

        false ->
            {State, [], Tx_idx_counter}
    end.

-file("src/aarondb/transactor/apply.gleam", 119).
-spec attribute_config(aarondb@shared@state:db_state(), binary()) -> aarondb@fact:attribute_config().
attribute_config(State, Attribute) ->
    _pipe = gleam_stdlib:map_get(erlang:element(8, State), Attribute),
    gleam@result:unwrap(
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

-file("src/aarondb/transactor/apply.gleam", 13).
-spec apply_datom(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom(),
    integer()
) -> {aarondb@shared@state:db_state(), list(aarondb@fact:datom()), integer()}.
apply_datom(State, D, Tx_idx_counter) ->
    Config = attribute_config(State, erlang:element(3, D)),
    {State_after_cascade, Cascade_datoms, Cascade_idx} = component_cascade(
        State,
        D,
        Tx_idx_counter,
        Config
    ),
    {State_after_card, Card_datoms, Card_idx} = cardinality_one(
        State_after_cascade,
        D,
        Cascade_idx,
        Config
    ),
    State_after_retention = retention_policy(State_after_card, D, Config),
    D_with_idx = {datom,
        erlang:element(2, D),
        erlang:element(3, D),
        erlang:element(4, D),
        erlang:element(5, D),
        Card_idx,
        erlang:element(7, D),
        erlang:element(8, D)},
    Final_state = update_indices(State_after_retention, D_with_idx),
    {Final_state,
        lists:append(lists:append(Cascade_datoms, Card_datoms), [D_with_idx]),
        Card_idx + 1}.

-file("src/aarondb/transactor/apply.gleam", 80).
-spec resolve_transaction_functions(
    aarondb@shared@state:db_state(),
    integer(),
    integer(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> list({aarondb@fact:eid(), binary(), aarondb@fact:value()}).
resolve_transaction_functions(State, Tx_id, Vt, Facts) ->
    gleam@list:flat_map(Facts, fun(F) -> case erlang:element(1, F) of
                {lookup, Lu} ->
                    {A, V} = Lu,
                    case A =:= <<"db/fn"/utf8>> of
                        true ->
                            Func_name = case V of
                                {str, S} ->
                                    S;

                                _ ->
                                    aarondb@fact:to_string(V)
                            end,
                            case gleam_stdlib:map_get(
                                erlang:element(9, State),
                                Func_name
                            ) of
                                {ok, Func} ->
                                    Args = case erlang:element(3, F) of
                                        {list, L} ->
                                            L;

                                        _ ->
                                            []
                                    end,
                                    Func(State, Tx_id, Vt, Args);

                                {error, _} ->
                                    [F]
                            end;

                        false ->
                            [F]
                    end;

                _ ->
                    case erlang:element(3, F) of
                        {list, [{str, <<"db/id"/utf8>>} | _]} ->
                            [{erlang:element(1, F),
                                    erlang:element(2, F),
                                    {int, Tx_id}}];

                        _ ->
                            [F]
                    end
            end end).
