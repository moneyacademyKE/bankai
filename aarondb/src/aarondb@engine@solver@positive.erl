-module(aarondb@engine@solver@positive).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/positive.gleam").
-export([positive_with_state/5, positive/5, negative/5]).

-file("src/aarondb/engine/solver/positive.gleam", 127).
-spec lookup_ets(
    aarondb@shared@state:db_state(),
    gleam@option:option(aarondb@fact:value()),
    binary(),
    gleam@option:option(aarondb@fact:value())
) -> list(aarondb@fact:datom()).
lookup_ets(Db_state, E_val, Attr, V_val) ->
    case erlang:element(14, Db_state) of
        {some, Name} ->
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
                    aarondb@index@ets:lookup_datoms(
                        <<Name/binary, "_aevt"/utf8>>,
                        Attr
                    );

                {{some, _}, _} ->
                    []
            end;

        none ->
            []
    end.

-file("src/aarondb/engine/solver/positive.gleam", 96).
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

-file("src/aarondb/engine/solver/positive.gleam", 17).
-spec positive_with_state(
    aarondb@shared@state:db_state(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()},
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> {list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.
positive_with_state(Db_state, Triple, Ctx, As_of_tx, As_of_valid) ->
    {E_p, Attr, V_p} = Triple,
    E_val = aarondb@engine@solver@bindings:resolve_part(E_p, Ctx),
    V_val = aarondb@engine@solver@bindings:resolve_part(V_p, Ctx),
    {Base_datoms@1, New_store} = case gleam_stdlib:map_get(
        erlang:element(23, Db_state),
        Attr
    ) of
        {ok, Chunks} ->
            Updated_chunks = case V_val of
                {some, V} ->
                    gleam@list:map(
                        Chunks,
                        fun(Chunk) ->
                            New_values = aarondb@algo@cracking:partition(
                                erlang:element(3, Chunk),
                                V
                            ),
                            {storage_chunk,
                                erlang:element(2, Chunk),
                                New_values,
                                erlang:element(4, Chunk),
                                erlang:element(5, Chunk)}
                        end
                    );

                none ->
                    Chunks
            end,
            Datoms = aarondb@algo@vectorized:chunks_to_datoms(Updated_chunks),
            {Datoms, {some, maps:from_list([{Attr, Updated_chunks}])}};

        {error, _} ->
            Adapter_datoms = case aarondb@storage:query_datoms(
                erlang:element(2, Db_state),
                Triple
            ) of
                {ok, Datoms@1} when Datoms@1 =/= [] ->
                    Datoms@1;

                _ ->
                    []
            end,
            Base_datoms = case Adapter_datoms of
                [] ->
                    Memory_datoms = lookup_memory(Db_state, E_val, Attr, V_val),
                    Disk_datoms = lookup_ets(Db_state, E_val, Attr, V_val),
                    lists:append(Memory_datoms, Disk_datoms);

                _ ->
                    Adapter_datoms
            end,
            {Base_datoms, none}
    end,
    Active = begin
        _pipe = Base_datoms@1,
        _pipe@1 = aarondb@engine@entity:filter_by_time(
            _pipe,
            As_of_tx,
            As_of_valid
        ),
        aarondb@engine@entity:filter_active(_pipe@1, Db_state)
    end,
    Results = aarondb@engine@morsel:execute_morsels(
        Active,
        [Ctx],
        E_p,
        V_p,
        erlang:element(3, erlang:element(24, Db_state))
    ),
    {Results, New_store}.

-file("src/aarondb/engine/solver/positive.gleam", 73).
-spec positive(
    aarondb@shared@state:db_state(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()},
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
positive(Db_state, Triple, Ctx, As_of_tx, As_of_valid) ->
    erlang:element(
        1,
        positive_with_state(Db_state, Triple, Ctx, As_of_tx, As_of_valid)
    ).

-file("src/aarondb/engine/solver/positive.gleam", 83).
-spec negative(
    aarondb@shared@state:db_state(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()},
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
negative(Db_state, Triple, Ctx, As_of_tx, As_of_valid) ->
    case positive(Db_state, Triple, Ctx, As_of_tx, As_of_valid) of
        [] ->
            [Ctx];

        _ ->
            []
    end.
