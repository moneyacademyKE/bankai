-module(aarondb@transactor@validation).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/validation.gleam").
-export([validate_datom/3]).

-file("src/aarondb/transactor/validation.gleam", 186).
-spec check_composite_uniqueness(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    aarondb@fact:datom(),
    list(binary()),
    list({binary(), aarondb@fact:value()})
) -> gleam@list:continue_or_stop({ok, nil} | {error, binary()}).
check_composite_uniqueness(State, Tx_datoms, D, Attrs, Vs) ->
    Entities_per_attr = gleam@list:map(
        Vs,
        fun(Pair) ->
            In_db = begin
                _pipe = aarondb@index:get_datoms_by_val(
                    erlang:element(4, State),
                    erlang:element(1, Pair),
                    erlang:element(2, Pair)
                ),
                gleam@list:map(
                    _pipe,
                    fun(Datom) -> erlang:element(2, Datom) end
                )
            end,
            In_flight = begin
                _pipe@1 = gleam@list:filter(
                    Tx_datoms,
                    fun(Td) ->
                        ((erlang:element(3, Td) =:= erlang:element(1, Pair))
                        andalso (erlang:element(4, Td) =:= erlang:element(
                            2,
                            Pair
                        )))
                        andalso (erlang:element(8, Td) =:= assert)
                    end
                ),
                gleam@list:map(
                    _pipe@1,
                    fun(Td@1) -> erlang:element(2, Td@1) end
                )
            end,
            gleam@list:unique(lists:append(In_db, In_flight))
        end
    ),
    Common_entities = case Entities_per_attr of
        [First | Rest] ->
            gleam@list:fold(
                Rest,
                First,
                fun(Acc, Eids) ->
                    gleam@list:filter(
                        Acc,
                        fun(Eid) -> gleam@list:contains(Eids, Eid) end
                    )
                end
            );

        [] ->
            []
    end,
    Violation = gleam@list:filter(
        Common_entities,
        fun(E) -> E /= erlang:element(2, D) end
    ),
    case Violation of
        [] ->
            {continue, {ok, nil}};

        _ ->
            {stop,
                {error,
                    <<"Composite uniqueness violation: "/utf8,
                        (gleam@string:inspect(
                            gleam@list:sort(Attrs, fun gleam@string:compare/2)
                        ))/binary>>}}
    end.

-file("src/aarondb/transactor/validation.gleam", 107).
-spec validate_composite(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    aarondb@fact:datom(),
    aarondb@fact:attribute_config(),
    {ok, nil} | {error, binary()}
) -> {ok, nil} | {error, binary()}.
validate_composite(State, Tx_datoms, D, Config, Prev) ->
    case Prev of
        {ok, _} ->
            Registered_groups = erlang:element(10, State),
            Schema_groups = case erlang:element(7, Config) of
                {some, Group_name} ->
                    Attrs = begin
                        _pipe = maps:to_list(erlang:element(8, State)),
                        _pipe@1 = gleam@list:filter(
                            _pipe,
                            fun(Item) ->
                                erlang:element(7, (erlang:element(2, Item))) =:= {some,
                                    Group_name}
                            end
                        ),
                        gleam@list:map(
                            _pipe@1,
                            fun(Item@1) -> erlang:element(1, Item@1) end
                        )
                    end,
                    [Attrs];

                none ->
                    []
            end,
            All_groups = lists:append(Registered_groups, Schema_groups),
            Groups = gleam@list:filter(
                All_groups,
                fun(C) -> gleam@list:contains(C, erlang:element(3, D)) end
            ),
            gleam@list:fold_until(
                Groups,
                {ok, nil},
                fun(_, Attrs@1) ->
                    Current_values = gleam@list:fold_until(
                        Attrs@1,
                        {ok, []},
                        fun(Acc_res, Attr) ->
                            Acc@1 = case Acc_res of
                                {ok, Acc} -> Acc;
                                _assert_fail ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"aarondb/transactor/validation"/utf8>>,
                                                function => <<"validate_composite"/utf8>>,
                                                line => 137,
                                                value => _assert_fail,
                                                start => 3725,
                                                'end' => 3753,
                                                pattern_start => 3736,
                                                pattern_end => 3743})
                            end,
                            case Attr =:= erlang:element(3, D) of
                                true ->
                                    {continue,
                                        {ok,
                                            [{Attr, erlang:element(4, D)} |
                                                Acc@1]}};

                                false ->
                                    In_flight = gleam@list:find(
                                        Tx_datoms,
                                        fun(Td) ->
                                            ((erlang:element(2, Td) =:= erlang:element(
                                                2,
                                                D
                                            ))
                                            andalso (erlang:element(3, Td) =:= Attr))
                                            andalso (erlang:element(8, Td) =:= assert)
                                        end
                                    ),
                                    case In_flight of
                                        {ok, Ifd} ->
                                            {continue,
                                                {ok,
                                                    [{Attr,
                                                            erlang:element(
                                                                4,
                                                                Ifd
                                                            )} |
                                                        Acc@1]}};

                                        {error, _} ->
                                            case begin
                                                _pipe@2 = aarondb@index:get_datoms_by_entity_attr(
                                                    erlang:element(3, State),
                                                    erlang:element(2, D),
                                                    Attr
                                                ),
                                                gleam@list:filter(
                                                    _pipe@2,
                                                    fun(D@1) ->
                                                        erlang:element(8, D@1)
                                                        =:= assert
                                                    end
                                                )
                                            end of
                                                [Existing_d | _] ->
                                                    {continue,
                                                        {ok,
                                                            [{Attr,
                                                                    erlang:element(
                                                                        4,
                                                                        Existing_d
                                                                    )} |
                                                                Acc@1]}};

                                                [] ->
                                                    {stop,
                                                        {error,
                                                            <<"Missing attribute for composite: "/utf8,
                                                                Attr/binary>>}}
                                            end
                                    end
                            end
                        end
                    ),
                    case Current_values of
                        {ok, Vs} ->
                            case erlang:length(Vs) =:= erlang:length(Attrs@1) of
                                true ->
                                    check_composite_uniqueness(
                                        State,
                                        Tx_datoms,
                                        D,
                                        Attrs@1,
                                        Vs
                                    );

                                false ->
                                    {continue, {ok, nil}}
                            end;

                        _ ->
                            {continue, {ok, nil}}
                    end
                end
            );

        {error, E} ->
            {error, E}
    end.

-file("src/aarondb/transactor/validation.gleam", 83).
-spec validate_check_constraint(
    aarondb@shared@state:db_state(),
    aarondb@fact:datom(),
    aarondb@fact:attribute_config(),
    {ok, nil} | {error, binary()}
) -> {ok, nil} | {error, binary()}.
validate_check_constraint(State, D, Config, Prev) ->
    case Prev of
        {ok, _} ->
            case erlang:element(6, Config) of
                {some, Pred_name} ->
                    case gleam_stdlib:map_get(
                        erlang:element(20, State),
                        Pred_name
                    ) of
                        {ok, Pred} ->
                            case Pred(erlang:element(4, D)) of
                                true ->
                                    {ok, nil};

                                false ->
                                    {error,
                                        <<"Check constraint failed: "/utf8,
                                            Pred_name/binary>>}
                            end;

                        {error, _} ->
                            {ok, nil}
                    end;

                none ->
                    {ok, nil}
            end;

        {error, E} ->
            {error, E}
    end.

-file("src/aarondb/transactor/validation.gleam", 40).
-spec validate_uniqueness(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    aarondb@fact:datom(),
    aarondb@fact:attribute_config()
) -> {ok, nil} | {error, binary()}.
validate_uniqueness(State, Tx_datoms, D, Config) ->
    case erlang:element(2, Config) andalso (erlang:element(8, D) =:= assert) of
        true ->
            Existing = aarondb@index:get_datoms_by_val(
                erlang:element(4, State),
                erlang:element(3, D),
                erlang:element(4, D)
            ),
            Effectively_existing = gleam@list:filter(
                Existing,
                fun(Ed) ->
                    (erlang:element(8, Ed) =:= assert) andalso not gleam@list:any(
                        Tx_datoms,
                        fun(Td) ->
                            ((erlang:element(2, Td) =:= erlang:element(2, Ed))
                            andalso (erlang:element(3, Td) =:= erlang:element(
                                3,
                                Ed
                            )))
                            andalso (erlang:element(8, Td) =:= retract)
                        end
                    )
                end
            ),
            case Effectively_existing of
                [Ed@1 | _] when erlang:element(2, Ed@1) =/= erlang:element(2, D) ->
                    {error,
                        <<"Uniqueness violation for "/utf8,
                            (erlang:element(3, D))/binary>>};

                _ ->
                    In_flight_violation = gleam@list:any(
                        Tx_datoms,
                        fun(Td@1) ->
                            ((((erlang:element(3, Td@1) =:= erlang:element(3, D))
                            andalso (erlang:element(4, Td@1) =:= erlang:element(
                                4,
                                D
                            )))
                            andalso (erlang:element(2, Td@1) /= erlang:element(
                                2,
                                D
                            )))
                            andalso (erlang:element(8, Td@1) =:= assert))
                            andalso (erlang:element(6, Td@1) < erlang:element(
                                6,
                                D
                            ))
                        end
                    ),
                    case In_flight_violation of
                        true ->
                            {error,
                                <<"Uniqueness violation (in-flight) for "/utf8,
                                    (erlang:element(3, D))/binary>>};

                        false ->
                            {ok, nil}
                    end
            end;

        false ->
            {ok, nil}
    end.

-file("src/aarondb/transactor/validation.gleam", 22).
-spec schema_config(aarondb@shared@state:db_state(), binary()) -> aarondb@fact:attribute_config().
schema_config(State, Attribute) ->
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

-file("src/aarondb/transactor/validation.gleam", 10).
-spec validate_datom(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    aarondb@fact:datom()
) -> {ok, nil} | {error, binary()}.
validate_datom(State, Tx_datoms, D) ->
    Config = schema_config(State, erlang:element(3, D)),
    Res = validate_uniqueness(State, Tx_datoms, D, Config),
    Res@1 = validate_check_constraint(State, D, Config, Res),
    validate_composite(State, Tx_datoms, D, Config, Res@1).
