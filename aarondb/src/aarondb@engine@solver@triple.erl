-module(aarondb@engine@solver@triple).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/triple.gleam").
-export([solve/6]).

-file("src/aarondb/engine/solver/triple.gleam", 119).
-spec filter_derived(
    gleam@set:set(aarondb@fact:datom()),
    binary(),
    gleam@option:option(aarondb@fact:value()),
    gleam@option:option(aarondb@fact:value())
) -> list(aarondb@fact:datom()).
filter_derived(Derived, Attr, E_val, V_val) ->
    _pipe = gleam@set:to_list(Derived),
    gleam@list:filter(
        _pipe,
        fun(D) ->
            Attr_match = erlang:element(3, D) =:= Attr,
            E_match = case E_val of
                {some, {ref, {entity_id, E}}} ->
                    {entity_id, Eid_int} = erlang:element(2, D),
                    Eid_int =:= E;

                {some, {int, E@1}} ->
                    {entity_id, Eid_int@1} = erlang:element(2, D),
                    Eid_int@1 =:= E@1;

                _ ->
                    true
            end,
            V_match = case V_val of
                {some, V} ->
                    erlang:element(4, D) =:= V;

                _ ->
                    true
            end,
            (Attr_match andalso E_match) andalso V_match
        end
    ).

-file("src/aarondb/engine/solver/triple.gleam", 88).
-spec lookup_memory(
    aarondb@shared@state:db_state(),
    gleam@option:option(aarondb@fact:value()),
    binary(),
    gleam@option:option(aarondb@fact:value())
) -> list(aarondb@fact:datom()).
lookup_memory(Db_state, E_val, Attr, V_val) ->
    case {E_val, V_val} of
        {{some, {ref, {entity_id, E}}}, {some, V}} ->
            aarondb@index:get_datoms_by_entity_attr_val(
                erlang:element(3, Db_state),
                {entity_id, E},
                Attr,
                V
            );

        {{some, {ref, {entity_id, E@1}}}, none} ->
            aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, Db_state),
                {entity_id, E@1},
                Attr
            );

        {{some, {int, E@2}}, {some, V@1}} ->
            aarondb@index:get_datoms_by_entity_attr_val(
                erlang:element(3, Db_state),
                {entity_id, E@2},
                Attr,
                V@1
            );

        {{some, {int, E@3}}, none} ->
            aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, Db_state),
                {entity_id, E@3},
                Attr
            );

        {none, {some, V@2}} ->
            aarondb@index:get_datoms_by_val(
                erlang:element(4, Db_state),
                Attr,
                V@2
            );

        {none, none} ->
            aarondb@index:get_all_datoms_for_attr(
                erlang:element(3, Db_state),
                Attr
            );

        {{some, _}, _} ->
            []
    end.

-file("src/aarondb/engine/solver/triple.gleam", 61).
-spec lookup_ets(
    binary(),
    gleam@option:option(aarondb@fact:value()),
    binary(),
    gleam@option:option(aarondb@fact:value())
) -> list(aarondb@fact:datom()).
lookup_ets(Name, E_val, Attr, V_val) ->
    case {E_val, V_val} of
        {{some, {ref, {entity_id, E}}}, {some, V}} ->
            _pipe = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                {entity_id, E}
            ),
            gleam@list:filter(
                _pipe,
                fun(D) ->
                    (erlang:element(3, D) =:= Attr) andalso (erlang:element(
                        4,
                        D
                    )
                    =:= V)
                end
            );

        {{some, {ref, {entity_id, E@1}}}, none} ->
            _pipe@1 = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                {entity_id, E@1}
            ),
            gleam@list:filter(
                _pipe@1,
                fun(D@1) -> erlang:element(3, D@1) =:= Attr end
            );

        {{some, {int, E@2}}, {some, V@1}} ->
            _pipe@2 = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                {entity_id, E@2}
            ),
            gleam@list:filter(
                _pipe@2,
                fun(D@2) ->
                    (erlang:element(3, D@2) =:= Attr) andalso (erlang:element(
                        4,
                        D@2
                    )
                    =:= V@1)
                end
            );

        {{some, {int, E@3}}, none} ->
            _pipe@3 = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                {entity_id, E@3}
            ),
            gleam@list:filter(
                _pipe@3,
                fun(D@3) -> erlang:element(3, D@3) =:= Attr end
            );

        {none, {some, V@2}} ->
            _pipe@4 = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_aevt"/utf8>>,
                Attr
            ),
            gleam@list:filter(
                _pipe@4,
                fun(D@4) -> erlang:element(4, D@4) =:= V@2 end
            );

        {none, none} ->
            aarondb@index@ets:lookup_datoms(<<Name/binary, "_aevt"/utf8>>, Attr);

        {{some, _}, _} ->
            []
    end.

-file("src/aarondb/engine/solver/triple.gleam", 49).
-spec lookup_base_datoms(
    aarondb@shared@state:db_state(),
    gleam@option:option(aarondb@fact:value()),
    binary(),
    gleam@option:option(aarondb@fact:value())
) -> list(aarondb@fact:datom()).
lookup_base_datoms(Db_state, E_val, Attr, V_val) ->
    case erlang:element(14, Db_state) of
        {some, Name} ->
            lookup_ets(Name, E_val, Attr, V_val);

        none ->
            lookup_memory(Db_state, E_val, Attr, V_val)
    end.

-file("src/aarondb/engine/solver/triple.gleam", 13).
-spec solve(
    aarondb@shared@state:db_state(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()},
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@set:set(aarondb@fact:datom()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
solve(Db_state, Triple, Ctx, Derived, As_of_tx, As_of_valid) ->
    {E_p, Attr, V_p} = Triple,
    E_val = aarondb@engine@solver@bindings:resolve_part(E_p, Ctx),
    V_val = aarondb@engine@solver@bindings:resolve_part(V_p, Ctx),
    Base_datoms = lookup_base_datoms(Db_state, E_val, Attr, V_val),
    Derived_datoms = filter_derived(Derived, Attr, E_val, V_val),
    All = lists:append(Base_datoms, Derived_datoms),
    Active = begin
        _pipe = All,
        _pipe@1 = aarondb@engine@entity:filter_by_time(
            _pipe,
            As_of_tx,
            As_of_valid
        ),
        _pipe@2 = aarondb@engine@entity:filter_active(_pipe@1, Db_state),
        gleam@list:filter(
            _pipe@2,
            fun(D) -> erlang:element(8, D) =:= assert end
        )
    end,
    gleam@list:map(
        Active,
        fun(D@1) ->
            B = Ctx,
            B@1 = case E_p of
                {var, N} ->
                    gleam@dict:insert(B, N, {ref, erlang:element(2, D@1)});

                _ ->
                    B
            end,
            B@2 = case V_p of
                {var, N@1} ->
                    gleam@dict:insert(B@1, N@1, erlang:element(4, D@1));

                _ ->
                    B@1
            end,
            B@2
        end
    ).
