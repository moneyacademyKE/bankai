-module(aarondb@engine@entity).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/entity.gleam").
-export([entity_history/2, filter_active/2, pull/3, pull_result_to_value/1, diff/3, filter_by_time/3]).

-file("src/aarondb/engine/entity.gleam", 14).
-spec entity_history(aarondb@shared@state:db_state(), aarondb@fact:entity_id()) -> list(aarondb@fact:datom()).
entity_history(Db_state, Eid) ->
    _pipe = gleam_stdlib:map_get(erlang:element(3, Db_state), Eid),
    _pipe@1 = gleam@result:unwrap(_pipe, []),
    gleam@list:sort(
        _pipe@1,
        fun(A, B) ->
            case gleam@int:compare(erlang:element(5, A), erlang:element(5, B)) of
                eq ->
                    case {erlang:element(8, A), erlang:element(8, B)} of
                        {retract, assert} ->
                            lt;

                        {assert, retract} ->
                            gt;

                        {_, _} ->
                            eq
                    end;

                Other ->
                    Other
            end
        end
    ).

-file("src/aarondb/engine/entity.gleam", 183).
-spec attribute_config(aarondb@shared@state:db_state(), binary()) -> aarondb@fact:attribute_config().
attribute_config(Db_state, Attribute) ->
    _pipe = gleam_stdlib:map_get(erlang:element(8, Db_state), Attribute),
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

-file("src/aarondb/engine/entity.gleam", 34).
-spec filter_active(list(aarondb@fact:datom()), aarondb@shared@state:db_state()) -> list(aarondb@fact:datom()).
filter_active(Datoms, Db_state) ->
    Latest = gleam@list:fold(
        Datoms,
        maps:new(),
        fun(Acc, D) ->
            Config = attribute_config(Db_state, erlang:element(3, D)),
            Key = case erlang:element(5, Config) of
                many ->
                    {erlang:element(2, D),
                        erlang:element(3, D),
                        {some, erlang:element(4, D)}};

                one ->
                    {erlang:element(2, D), erlang:element(3, D), none}
            end,
            case gleam_stdlib:map_get(Acc, Key) of
                {ok, {Tx, Tx_idx, _}} ->
                    case (Tx > erlang:element(5, D)) orelse ((Tx =:= erlang:element(
                        5,
                        D
                    ))
                    andalso (Tx_idx > erlang:element(6, D))) of
                        true ->
                            Acc;

                        false ->
                            gleam@dict:insert(
                                Acc,
                                Key,
                                {erlang:element(5, D),
                                    erlang:element(6, D),
                                    erlang:element(8, D)}
                            )
                    end;

                _ ->
                    gleam@dict:insert(
                        Acc,
                        Key,
                        {erlang:element(5, D),
                            erlang:element(6, D),
                            erlang:element(8, D)}
                    )
            end
        end
    ),
    gleam@list:filter(
        Datoms,
        fun(D@1) ->
            Config@1 = attribute_config(Db_state, erlang:element(3, D@1)),
            Key@1 = case erlang:element(5, Config@1) of
                many ->
                    {erlang:element(2, D@1),
                        erlang:element(3, D@1),
                        {some, erlang:element(4, D@1)}};

                one ->
                    {erlang:element(2, D@1), erlang:element(3, D@1), none}
            end,
            case gleam_stdlib:map_get(Latest, Key@1) of
                {ok, {Tx@1, Tx_idx@1, Op}} ->
                    ((Tx@1 =:= erlang:element(5, D@1)) andalso (Tx_idx@1 =:= erlang:element(
                        6,
                        D@1
                    )))
                    andalso (Op =:= assert);

                _ ->
                    false
            end
        end
    ).

-file("src/aarondb/engine/entity.gleam", 239).
-spec pull_nested(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    gleam@dict:dict(binary(), aarondb@shared@query_types:pull_result()),
    binary(),
    list(aarondb@shared@ast:pull_item())
) -> gleam@dict:dict(binary(), aarondb@shared@query_types:pull_result()).
pull_nested(Db_state, Datoms, Acc, Name, Sub_pattern) ->
    Values = begin
        _pipe = gleam@list:filter(
            Datoms,
            fun(D) -> erlang:element(3, D) =:= Name end
        ),
        gleam@list:map(_pipe, fun(D@1) -> erlang:element(4, D@1) end)
    end,
    case Values of
        [{ref, Eid}] ->
            gleam@dict:insert(Acc, Name, pull(Db_state, Eid, Sub_pattern));

        [{int, Sub_id}] ->
            gleam@dict:insert(
                Acc,
                Name,
                pull(Db_state, {entity_id, Sub_id}, Sub_pattern)
            );

        [_ | _] ->
            Nested = gleam@list:map(Values, fun(V) -> case V of
                        {ref, Eid@1} ->
                            pull(Db_state, Eid@1, Sub_pattern);

                        {int, Sub_id@1} ->
                            pull(Db_state, {entity_id, Sub_id@1}, Sub_pattern);

                        _ ->
                            {pull_single, V}
                    end end),
            case Nested of
                [R] ->
                    gleam@dict:insert(Acc, Name, R);

                [_ | _] ->
                    gleam@dict:insert(Acc, Name, {pull_nested_many, Nested});

                _ ->
                    Acc
            end;

        _ ->
            Acc
    end.

-file("src/aarondb/engine/entity.gleam", 201).
-spec pull_recursion(
    aarondb@shared@state:db_state(),
    list(aarondb@fact:datom()),
    gleam@dict:dict(binary(), aarondb@shared@query_types:pull_result()),
    binary(),
    integer()
) -> gleam@dict:dict(binary(), aarondb@shared@query_types:pull_result()).
pull_recursion(Db_state, Datoms, Acc, Attr, Depth) ->
    case Depth =< 0 of
        true ->
            Acc;

        false ->
            Values = begin
                _pipe = gleam@list:filter(
                    Datoms,
                    fun(D) -> erlang:element(3, D) =:= Attr end
                ),
                gleam@list:map(_pipe, fun(D@1) -> erlang:element(4, D@1) end)
            end,
            Results = gleam@list:map(Values, fun(V) -> case V of
                        {ref, Next_id} ->
                            pull(
                                Db_state,
                                Next_id,
                                [wildcard, {pull_recursion, Attr, Depth - 1}]
                            );

                        {int, Next_id_int} ->
                            pull(
                                Db_state,
                                {entity_id, Next_id_int},
                                [wildcard, {pull_recursion, Attr, Depth - 1}]
                            );

                        _ ->
                            {pull_single, V}
                    end end),
            case Results of
                [R] ->
                    gleam@dict:insert(Acc, Attr, R);

                [_ | _] ->
                    gleam@dict:insert(Acc, Attr, {pull_nested_many, Results});

                [] ->
                    Acc
            end
    end.

-file("src/aarondb/engine/entity.gleam", 72).
-spec pull(
    aarondb@shared@state:db_state(),
    aarondb@fact:entity_id(),
    list(aarondb@shared@ast:pull_item())
) -> aarondb@shared@query_types:pull_result().
pull(Db_state, Eid, Pattern) ->
    Datoms = case erlang:element(14, Db_state) of
        {some, Name} ->
            aarondb@index@ets:lookup_datoms(<<Name/binary, "_eavt"/utf8>>, Eid);

        none ->
            _pipe = aarondb@index:filter_by_entity(
                erlang:element(3, Db_state),
                Eid
            ),
            lists:reverse(_pipe)
    end,
    case erlang:length(Datoms) > erlang:element(5, erlang:element(24, Db_state)) of
        true ->
            case erlang:element(14, Db_state) of
                {some, Name@1} ->
                    case aarondb@index@ets:get_raw_binary(
                        <<Name@1/binary, "_eavt"/utf8>>,
                        Eid
                    ) of
                        {ok, Bin} ->
                            {pull_raw_binary, Bin};

                        {error, _} ->
                            {pull_raw_binary,
                                aarondb@index@ets:serialize_term(Datoms)}
                    end;

                none ->
                    {pull_raw_binary, aarondb@index@ets:serialize_term(Datoms)}
            end;

        false ->
            Active = filter_active(Datoms, Db_state),
            Mapped = gleam@list:fold(
                Pattern,
                maps:new(),
                fun(Acc, Item) -> case Item of
                        wildcard ->
                            gleam@list:fold(
                                Active,
                                Acc,
                                fun(Inner_acc, D) ->
                                    gleam@dict:insert(
                                        Inner_acc,
                                        erlang:element(3, D),
                                        {pull_single, erlang:element(4, D)}
                                    )
                                end
                            );

                        {attr, Name@2} ->
                            Values = begin
                                _pipe@1 = gleam@list:filter(
                                    Active,
                                    fun(D@1) ->
                                        erlang:element(3, D@1) =:= Name@2
                                    end
                                ),
                                gleam@list:map(
                                    _pipe@1,
                                    fun(D@2) -> erlang:element(4, D@2) end
                                )
                            end,
                            case Values of
                                [V] ->
                                    gleam@dict:insert(
                                        Acc,
                                        Name@2,
                                        {pull_single, V}
                                    );

                                [_ | _] ->
                                    gleam@dict:insert(
                                        Acc,
                                        Name@2,
                                        {pull_many, Values}
                                    );

                                [] ->
                                    Acc
                            end;

                        {except, Exclusions} ->
                            gleam@list:fold(
                                Active,
                                Acc,
                                fun(Inner_acc@1, D@3) ->
                                    case gleam@list:contains(
                                        Exclusions,
                                        erlang:element(3, D@3)
                                    ) of
                                        true ->
                                            Inner_acc@1;

                                        false ->
                                            gleam@dict:insert(
                                                Inner_acc@1,
                                                erlang:element(3, D@3),
                                                {pull_single,
                                                    erlang:element(4, D@3)}
                                            )
                                    end
                                end
                            );

                        {pull_recursion, Attr, Depth} ->
                            pull_recursion(Db_state, Active, Acc, Attr, Depth);

                        {nested, Name@3, Sub_pattern} ->
                            pull_nested(
                                Db_state,
                                Active,
                                Acc,
                                Name@3,
                                Sub_pattern
                            )
                    end end
            ),
            {pull_map, Mapped}
    end.

-file("src/aarondb/engine/entity.gleam", 143).
-spec pull_result_to_value(aarondb@shared@query_types:pull_result()) -> aarondb@fact:value().
pull_result_to_value(Res) ->
    case Res of
        {pull_single, V} ->
            V;

        {pull_many, Vs} ->
            {list, Vs};

        {pull_nested_many, Res_list} ->
            {list, gleam@list:map(Res_list, fun pull_result_to_value/1)};

        {pull_map, M} ->
            {map,
                gleam@dict:map_values(
                    M,
                    fun(_, V@1) -> pull_result_to_value(V@1) end
                )};

        {pull_raw_binary, Bin} ->
            {blob, Bin}
    end.

-file("src/aarondb/engine/entity.gleam", 155).
-spec diff(aarondb@shared@state:db_state(), integer(), integer()) -> list(aarondb@fact:datom()).
diff(Db_state, From_tx, To_tx) ->
    _pipe = aarondb@index:get_all_datoms(erlang:element(3, Db_state)),
    gleam@list:filter(
        _pipe,
        fun(D) ->
            (erlang:element(5, D) > From_tx) andalso (erlang:element(5, D) =< To_tx)
        end
    ).

-file("src/aarondb/engine/entity.gleam", 164).
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
