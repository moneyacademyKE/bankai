-module(aarondb@engine@cognitive).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/cognitive.gleam").
-export([solve/8]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/engine/cognitive.gleam", 97).
-spec relevance_value(aarondb@fact:datom()) -> {ok, float()} | {error, nil}.
relevance_value(Datom) ->
    case erlang:element(4, Datom) of
        {float, Value} ->
            {ok, Value};

        {int, Value@1} ->
            {ok, erlang:float(Value@1)};

        _ ->
            {error, nil}
    end.

-file("src/aarondb/engine/cognitive.gleam", 82).
-spec max_numeric_relevance(list(aarondb@fact:datom())) -> gleam@option:option(float()).
max_numeric_relevance(Datoms) ->
    _pipe = Datoms,
    _pipe@1 = gleam@list:filter_map(_pipe, fun relevance_value/1),
    gleam@list:fold(_pipe@1, none, fun(Best, Value) -> case Best of
                none ->
                    {some, Value};

                {some, Previous} ->
                    case Value > Previous of
                        true ->
                            {some, Value};

                        false ->
                            {some, Previous}
                    end
            end end).

-file("src/aarondb/engine/cognitive.gleam", 105).
-spec resolve_part(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:value()).
resolve_part(Part, Ctx) ->
    case Part of
        {var, Name} ->
            gleam@option:from_result(gleam_stdlib:map_get(Ctx, Name));

        {val, Val} ->
            {some, Val};

        {uid, Uid} ->
            {some, {ref, Uid}};

        {attr_val, S} ->
            {some, {str, S}};

        {lookup, {_, Val@1}} ->
            {some, Val@1}
    end.

-file("src/aarondb/engine/cognitive.gleam", 24).
?DOC(
    " Solve AaronDB's local cognitive clause over explicit engram facts.\n"
    "\n"
    " An entity matches only when it has active `engram/concept` and\n"
    " `engram/context` facts matching the supplied parts. Its relevance is the\n"
    " maximum active numeric `engram/relevance` value; an entity with no relevance\n"
    " fact has relevance `1.0`, while one with only non-numeric relevance facts has\n"
    " relevance `0.0`. The threshold comparison is inclusive.\n"
    "\n"
    " This module performs no learning, decay, vector embedding, or external\n"
    " retrieval. Relevance changes only through ordinary fact assertions and\n"
    " retractions, and temporal bases select the active facts visible at that\n"
    " basis.\n"
).
-spec solve(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    float(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
solve(
    Db_state,
    Concept,
    Context,
    Threshold,
    Engram_var,
    Ctx,
    As_of_tx,
    As_of_valid
) ->
    Concept_val = resolve_part(Concept, Ctx),
    Context_val = resolve_part(Context, Ctx),
    Active_concept = begin
        _pipe = case Concept_val of
            {some, V} ->
                aarondb@index:get_datoms_by_val(
                    erlang:element(4, Db_state),
                    <<"engram/concept"/utf8>>,
                    V
                );

            none ->
                aarondb@index:get_all_datoms_for_attr(
                    erlang:element(3, Db_state),
                    <<"engram/concept"/utf8>>
                )
        end,
        _pipe@1 = aarondb@engine@entity:filter_by_time(
            _pipe,
            As_of_tx,
            As_of_valid
        ),
        aarondb@engine@entity:filter_active(_pipe@1, Db_state)
    end,
    Active_context = begin
        _pipe@2 = case Context_val of
            {some, V@1} ->
                aarondb@index:get_datoms_by_val(
                    erlang:element(4, Db_state),
                    <<"engram/context"/utf8>>,
                    V@1
                );

            none ->
                aarondb@index:get_all_datoms_for_attr(
                    erlang:element(3, Db_state),
                    <<"engram/context"/utf8>>
                )
        end,
        _pipe@3 = aarondb@engine@entity:filter_by_time(
            _pipe@2,
            As_of_tx,
            As_of_valid
        ),
        aarondb@engine@entity:filter_active(_pipe@3, Db_state)
    end,
    Concept_eids = begin
        _pipe@4 = gleam@list:map(
            Active_concept,
            fun(D) -> erlang:element(2, D) end
        ),
        gleam@set:from_list(_pipe@4)
    end,
    Context_eids = begin
        _pipe@5 = gleam@list:map(
            Active_context,
            fun(D@1) -> erlang:element(2, D@1) end
        ),
        gleam@set:from_list(_pipe@5)
    end,
    _pipe@6 = gleam@set:intersection(Concept_eids, Context_eids),
    _pipe@7 = gleam@set:to_list(_pipe@6),
    gleam@list:filter_map(
        _pipe@7,
        fun(Eid) ->
            Relevance_datoms = begin
                _pipe@8 = aarondb@index:get_datoms_by_entity_attr(
                    erlang:element(3, Db_state),
                    Eid,
                    <<"engram/relevance"/utf8>>
                ),
                _pipe@9 = aarondb@engine@entity:filter_by_time(
                    _pipe@8,
                    As_of_tx,
                    As_of_valid
                ),
                aarondb@engine@entity:filter_active(_pipe@9, Db_state)
            end,
            Score = case Relevance_datoms of
                [] ->
                    1.0;

                Datoms ->
                    case max_numeric_relevance(Datoms) of
                        {some, Value} ->
                            Value;

                        none ->
                            +0.0
                    end
            end,
            case Score >= Threshold of
                true ->
                    {ok, gleam@dict:insert(Ctx, Engram_var, {ref, Eid})};

                false ->
                    {error, nil}
            end
        end
    ).
