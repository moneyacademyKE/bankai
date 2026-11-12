-module(aarondb@index).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/index.gleam").
-export([new_index/0, new_aindex/0, new_avindex/0, new_hybrid_index/1, insert_eavt/3, insert_hybrid/3, insert_aevt/3, insert_avet/2, get_datoms_by_entity_attr_val/4, get_datoms_by_entity/2, get_datoms_by_entity_attr/3, get_datoms_by_val/3, get_all_datoms_for_attr/2, get_all_datoms/1, get_all_datoms_aevt/1, get_all_datoms_avet/1, get_entity_by_av/3, filter_by_attribute/2, filter_by_entity/2, delete_eavt/2, delete_aevt/2, delete_avet/2, get_cold_datoms/2, evict_from_memory/2]).
-export_type([hybrid_index/0]).

-type hybrid_index() :: {hybrid_index,
        gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
        list(bitstring()),
        integer()}.

-file("src/aarondb/index.gleam", 25).
-spec new_index() -> gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())).
new_index() ->
    maps:new().

-file("src/aarondb/index.gleam", 29).
-spec new_aindex() -> gleam@dict:dict(binary(), list(aarondb@fact:datom())).
new_aindex() ->
    maps:new().

-file("src/aarondb/index.gleam", 33).
-spec new_avindex() -> gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())).
new_avindex() ->
    maps:new().

-file("src/aarondb/index.gleam", 37).
-spec new_hybrid_index(integer()) -> hybrid_index().
new_hybrid_index(Capacity) ->
    {hybrid_index, maps:new(), [], Capacity}.

-file("src/aarondb/index.gleam", 119).
-spec result_to_list({ok, list(FPL)} | {error, any()}) -> list(FPL).
result_to_list(Res) ->
    case Res of
        {ok, L} ->
            L;

        {error, _} ->
            []
    end.

-file("src/aarondb/index.gleam", 61).
-spec insert_eavt(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:datom(),
    aarondb@fact:retention()
) -> gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())).
insert_eavt(Index, Datom, Retention) ->
    Bucket = begin
        _pipe = gleam_stdlib:map_get(Index, erlang:element(2, Datom)),
        result_to_list(_pipe)
    end,
    New_bucket = case Retention of
        all ->
            [Datom | Bucket];

        latest_only ->
            Filtered = gleam@list:filter(
                Bucket,
                fun(D) -> erlang:element(3, D) /= erlang:element(3, Datom) end
            ),
            [Datom | Filtered];

        {last, N} ->
            Filtered@1 = gleam@list:filter(
                Bucket,
                fun(D@1) ->
                    erlang:element(3, D@1) /= erlang:element(3, Datom)
                end
            ),
            Existing = gleam@list:filter(
                Bucket,
                fun(D@2) ->
                    erlang:element(3, D@2) =:= erlang:element(3, Datom)
                end
            ),
            Kept = gleam@list:take(Existing, N - 1),
            [Datom | lists:append(Kept, Filtered@1)]
    end,
    gleam@dict:insert(Index, erlang:element(2, Datom), New_bucket).

-file("src/aarondb/index.gleam", 41).
-spec insert_hybrid(
    hybrid_index(),
    aarondb@fact:datom(),
    aarondb@fact:retention()
) -> hybrid_index().
insert_hybrid(Index, Datom, Retention) ->
    New_index = insert_eavt(erlang:element(2, Index), Datom, Retention),
    case maps:size(New_index) > erlang:element(4, Index) of
        true ->
            Index;

        false ->
            {hybrid_index,
                New_index,
                erlang:element(3, Index),
                erlang:element(4, Index)}
    end.

-file("src/aarondb/index.gleam", 87).
-spec insert_aevt(
    gleam@dict:dict(binary(), list(aarondb@fact:datom())),
    aarondb@fact:datom(),
    aarondb@fact:retention()
) -> gleam@dict:dict(binary(), list(aarondb@fact:datom())).
insert_aevt(Index, Datom, Retention) ->
    Bucket = begin
        _pipe = gleam_stdlib:map_get(Index, erlang:element(3, Datom)),
        result_to_list(_pipe)
    end,
    New_bucket = case Retention of
        all ->
            [Datom | Bucket];

        latest_only ->
            Filtered = gleam@list:filter(
                Bucket,
                fun(D) -> erlang:element(2, D) /= erlang:element(2, Datom) end
            ),
            [Datom | Filtered];

        {last, N} ->
            Filtered@1 = gleam@list:filter(
                Bucket,
                fun(D@1) ->
                    erlang:element(2, D@1) /= erlang:element(2, Datom)
                end
            ),
            Existing = gleam@list:filter(
                Bucket,
                fun(D@2) ->
                    erlang:element(2, D@2) =:= erlang:element(2, Datom)
                end
            ),
            Kept = gleam@list:take(Existing, N - 1),
            [Datom | lists:append(Kept, Filtered@1)]
    end,
    gleam@dict:insert(Index, erlang:element(3, Datom), New_bucket).

-file("src/aarondb/index.gleam", 110).
-spec insert_avet(
    gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
    aarondb@fact:datom()
) -> gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())).
insert_avet(Index, Datom) ->
    V_dict = begin
        _pipe = gleam_stdlib:map_get(Index, erlang:element(3, Datom)),
        gleam@result:unwrap(_pipe, maps:new())
    end,
    New_v_dict = case erlang:element(8, Datom) of
        assert ->
            gleam@dict:insert(
                V_dict,
                erlang:element(4, Datom),
                erlang:element(2, Datom)
            );

        retract ->
            gleam@dict:delete(V_dict, erlang:element(4, Datom))
    end,
    gleam@dict:insert(Index, erlang:element(3, Datom), New_v_dict).

-file("src/aarondb/index.gleam", 126).
-spec get_datoms_by_entity_attr_val(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:entity_id(),
    binary(),
    aarondb@fact:value()
) -> list(aarondb@fact:datom()).
get_datoms_by_entity_attr_val(Index, Entity, Attr, Val) ->
    _pipe = gleam_stdlib:map_get(Index, Entity),
    _pipe@1 = result_to_list(_pipe),
    gleam@list:filter(
        _pipe@1,
        fun(D) ->
            (erlang:element(3, D) =:= Attr) andalso (erlang:element(4, D) =:= Val)
        end
    ).

-file("src/aarondb/index.gleam", 137).
-spec get_datoms_by_entity(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:entity_id()
) -> list(aarondb@fact:datom()).
get_datoms_by_entity(Index, Entity) ->
    _pipe = gleam_stdlib:map_get(Index, Entity),
    result_to_list(_pipe).

-file("src/aarondb/index.gleam", 145).
-spec get_datoms_by_entity_attr(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:entity_id(),
    binary()
) -> list(aarondb@fact:datom()).
get_datoms_by_entity_attr(Index, Entity, Attr) ->
    _pipe = gleam_stdlib:map_get(Index, Entity),
    _pipe@1 = result_to_list(_pipe),
    gleam@list:filter(_pipe@1, fun(D) -> erlang:element(3, D) =:= Attr end).

-file("src/aarondb/index.gleam", 155).
-spec get_datoms_by_val(
    gleam@dict:dict(binary(), list(aarondb@fact:datom())),
    binary(),
    aarondb@fact:value()
) -> list(aarondb@fact:datom()).
get_datoms_by_val(Index, Attr, Val) ->
    _pipe = gleam_stdlib:map_get(Index, Attr),
    _pipe@1 = result_to_list(_pipe),
    gleam@list:filter(_pipe@1, fun(D) -> erlang:element(4, D) =:= Val end).

-file("src/aarondb/index.gleam", 165).
-spec get_all_datoms_for_attr(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    binary()
) -> list(aarondb@fact:datom()).
get_all_datoms_for_attr(Index, Attr) ->
    _pipe = maps:values(Index),
    _pipe@1 = lists:append(_pipe),
    gleam@list:filter(_pipe@1, fun(D) -> erlang:element(3, D) =:= Attr end).

-file("src/aarondb/index.gleam", 171).
-spec get_all_datoms(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom()))
) -> list(aarondb@fact:datom()).
get_all_datoms(Index) ->
    _pipe = maps:values(Index),
    lists:append(_pipe).

-file("src/aarondb/index.gleam", 176).
-spec get_all_datoms_aevt(gleam@dict:dict(binary(), list(aarondb@fact:datom()))) -> list(aarondb@fact:datom()).
get_all_datoms_aevt(Index) ->
    _pipe = maps:values(Index),
    lists:append(_pipe).

-file("src/aarondb/index.gleam", 181).
-spec get_all_datoms_avet(
    gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id()))
) -> list(aarondb@fact:datom()).
get_all_datoms_avet(Index) ->
    _pipe = maps:values(Index),
    gleam@list:flat_map(_pipe, fun(V_dict) -> _pipe@1 = maps:to_list(V_dict),
            gleam@list:map(
                _pipe@1,
                fun(Pair) ->
                    {Val, Eid} = Pair,
                    {datom, Eid, <<"unknown"/utf8>>, Val, 0, 0, 0, assert}
                end
            ) end).

-file("src/aarondb/index.gleam", 200).
-spec get_entity_by_av(
    gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
    binary(),
    aarondb@fact:value()
) -> {ok, aarondb@fact:entity_id()} | {error, nil}.
get_entity_by_av(Index, Attr, Val) ->
    case gleam_stdlib:map_get(Index, Attr) of
        {ok, V_dict} ->
            gleam_stdlib:map_get(V_dict, Val);

        {error, _} ->
            {error, nil}
    end.

-file("src/aarondb/index.gleam", 211).
-spec filter_by_attribute(
    gleam@dict:dict(binary(), list(aarondb@fact:datom())),
    binary()
) -> list(aarondb@fact:datom()).
filter_by_attribute(Index, Attr) ->
    _pipe = gleam_stdlib:map_get(Index, Attr),
    result_to_list(_pipe).

-file("src/aarondb/index.gleam", 216).
-spec filter_by_entity(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:entity_id()
) -> list(aarondb@fact:datom()).
filter_by_entity(Index, Entity) ->
    _pipe = gleam_stdlib:map_get(Index, Entity),
    result_to_list(_pipe).

-file("src/aarondb/index.gleam", 221).
-spec delete_eavt(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aarondb@fact:datom()
) -> gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())).
delete_eavt(Index, Datom) ->
    case gleam_stdlib:map_get(Index, erlang:element(2, Datom)) of
        {ok, Bucket} ->
            New_bucket = gleam@list:filter(
                Bucket,
                fun(D) ->
                    ((erlang:element(3, D) /= erlang:element(3, Datom)) orelse (erlang:element(
                        4,
                        D
                    )
                    /= erlang:element(4, Datom)))
                    orelse (erlang:element(5, D) /= erlang:element(5, Datom))
                end
            ),
            case New_bucket of
                [] ->
                    gleam@dict:delete(Index, erlang:element(2, Datom));

                _ ->
                    gleam@dict:insert(
                        Index,
                        erlang:element(2, Datom),
                        New_bucket
                    )
            end;

        {error, _} ->
            Index
    end.

-file("src/aarondb/index.gleam", 239).
-spec delete_aevt(
    gleam@dict:dict(binary(), list(aarondb@fact:datom())),
    aarondb@fact:datom()
) -> gleam@dict:dict(binary(), list(aarondb@fact:datom())).
delete_aevt(Index, Datom) ->
    case gleam_stdlib:map_get(Index, erlang:element(3, Datom)) of
        {ok, Bucket} ->
            New_bucket = gleam@list:filter(
                Bucket,
                fun(D) ->
                    ((erlang:element(2, D) /= erlang:element(2, Datom)) orelse (erlang:element(
                        4,
                        D
                    )
                    /= erlang:element(4, Datom)))
                    orelse (erlang:element(5, D) /= erlang:element(5, Datom))
                end
            ),
            case New_bucket of
                [] ->
                    gleam@dict:delete(Index, erlang:element(3, Datom));

                _ ->
                    gleam@dict:insert(
                        Index,
                        erlang:element(3, Datom),
                        New_bucket
                    )
            end;

        {error, _} ->
            Index
    end.

-file("src/aarondb/index.gleam", 255).
-spec delete_avet(
    gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
    aarondb@fact:datom()
) -> gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())).
delete_avet(Index, Datom) ->
    case gleam_stdlib:map_get(Index, erlang:element(3, Datom)) of
        {ok, V_dict} ->
            New_v_dict = gleam@dict:delete(V_dict, erlang:element(4, Datom)),
            gleam@dict:insert(Index, erlang:element(3, Datom), New_v_dict);

        {error, _} ->
            Index
    end.

-file("src/aarondb/index.gleam", 267).
-spec get_cold_datoms(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    integer()
) -> list(aarondb@fact:datom()).
get_cold_datoms(Eavt, Cut_off_tx) ->
    _pipe = maps:values(Eavt),
    _pipe@1 = lists:append(_pipe),
    gleam@list:filter(_pipe@1, fun(D) -> erlang:element(5, D) < Cut_off_tx end).

-file("src/aarondb/index.gleam", 274).
-spec evict_from_memory(
    gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    list(aarondb@fact:datom())
) -> gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())).
evict_from_memory(Eavt, Datoms) ->
    gleam@list:fold(Datoms, Eavt, fun(Acc, D) -> delete_eavt(Acc, D) end).
