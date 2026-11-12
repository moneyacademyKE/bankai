-module(aarondb@engine@retrieval).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/retrieval.gleam").
-export([similarity/7, custom_index/8, similarity_entity/5]).

-file("src/aarondb/engine/retrieval.gleam", 99).
-spec unbound_similarity(
    aarondb@shared@state:db_state(),
    binary(),
    list(float()),
    float(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
unbound_similarity(Db_state, Var, Vec, Threshold, Ctx, As_of_tx, As_of_valid) ->
    case aarondb@vec_index:size(erlang:element(15, Db_state)) > 0 of
        true ->
            Norm_vec = aarondb@vector:normalize(Vec),
            _pipe = aarondb@vec_index:search(
                erlang:element(15, Db_state),
                Norm_vec,
                Threshold,
                100
            ),
            gleam@list:filter_map(
                _pipe,
                fun(R) ->
                    case begin
                        _pipe@1 = aarondb@index:filter_by_entity(
                            erlang:element(3, Db_state),
                            erlang:element(2, R)
                        ),
                        _pipe@2 = aarondb@engine@entity:filter_by_time(
                            _pipe@1,
                            As_of_tx,
                            As_of_valid
                        ),
                        _pipe@3 = aarondb@engine@entity:filter_active(
                            _pipe@2,
                            Db_state
                        ),
                        gleam@list:filter(
                            _pipe@3,
                            fun(D) -> case erlang:element(4, D) of
                                    {vec, _} ->
                                        erlang:element(8, D) =:= assert;

                                    _ ->
                                        false
                                end end
                        )
                    end of
                        [D@1 | _] ->
                            {ok,
                                gleam@dict:insert(
                                    Ctx,
                                    Var,
                                    erlang:element(4, D@1)
                                )};

                        [] ->
                            {error, nil}
                    end
                end
            );

        false ->
            _pipe@4 = aarondb@index:get_all_datoms_avet(
                erlang:element(5, Db_state)
            ),
            _pipe@5 = aarondb@engine@entity:filter_by_time(
                _pipe@4,
                As_of_tx,
                As_of_valid
            ),
            _pipe@6 = aarondb@engine@entity:filter_active(_pipe@5, Db_state),
            _pipe@7 = gleam@list:filter_map(
                _pipe@6,
                fun(D@2) -> case erlang:element(4, D@2) of
                        {vec, V} ->
                            case aarondb@vector:dimensions(Vec) =:= aarondb@vector:dimensions(
                                V
                            ) of
                                false ->
                                    {error, nil};

                                true ->
                                    Dist = aarondb@vector:cosine_similarity(
                                        Vec,
                                        V
                                    ),
                                    case Dist >= Threshold of
                                        true ->
                                            {ok, D@2};

                                        false ->
                                            {error, nil}
                                    end
                            end;

                        _ ->
                            {error, nil}
                    end end
            ),
            gleam@list:map(
                _pipe@7,
                fun(D@3) ->
                    gleam@dict:insert(Ctx, Var, erlang:element(4, D@3))
                end
            )
    end.

-file("src/aarondb/engine/retrieval.gleam", 11).
-spec similarity(
    aarondb@shared@state:db_state(),
    binary(),
    list(float()),
    float(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
similarity(Db_state, Var, Vec, Threshold, Ctx, As_of_tx, As_of_valid) ->
    case gleam_stdlib:map_get(Ctx, Var) of
        {ok, {vec, V}} ->
            case aarondb@vector:dimensions(Vec) =:= aarondb@vector:dimensions(V) of
                false ->
                    [];

                true ->
                    Dist = aarondb@vector:cosine_similarity(
                        aarondb@vector:normalize(Vec),
                        aarondb@vector:normalize(V)
                    ),
                    case Dist >= Threshold of
                        true ->
                            [Ctx];

                        false ->
                            []
                    end
            end;

        {ok, _} ->
            [];

        {error, nil} ->
            unbound_similarity(
                Db_state,
                Var,
                Vec,
                Threshold,
                Ctx,
                As_of_tx,
                As_of_valid
            )
    end.

-file("src/aarondb/engine/retrieval.gleam", 155).
-spec bind(
    gleam@dict:dict(binary(), aarondb@fact:value()),
    binary(),
    aarondb@fact:value()
) -> {ok, gleam@dict:dict(binary(), aarondb@fact:value())} | {error, nil}.
bind(Ctx, Var, Val) ->
    case gleam_stdlib:map_get(Ctx, Var) of
        {ok, Existing} when Existing =:= Val ->
            {ok, Ctx};

        {ok, _} ->
            {error, nil};

        {error, nil} ->
            {ok, gleam@dict:insert(Ctx, Var, Val)}
    end.

-file("src/aarondb/engine/retrieval.gleam", 48).
-spec custom_index(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    aarondb@shared@state:index_query(),
    float(),
    gleam@dict:dict(binary(), aarondb@fact:value()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
custom_index(
    Db_state,
    Var,
    Index_name,
    Query,
    Threshold,
    Ctx,
    As_of_tx,
    As_of_valid
) ->
    case gleam_stdlib:map_get(erlang:element(19, Db_state), Index_name) of
        {ok, Instance} ->
            case gleam_stdlib:map_get(
                erlang:element(18, Db_state),
                erlang:element(2, Instance)
            ) of
                {ok, Adapter} ->
                    _pipe = (erlang:element(5, Adapter))(
                        erlang:element(4, Instance),
                        Query,
                        Threshold
                    ),
                    gleam@list:filter_map(
                        _pipe,
                        fun(Eid) ->
                            Active = begin
                                _pipe@1 = aarondb@index:get_datoms_by_entity(
                                    erlang:element(3, Db_state),
                                    Eid
                                ),
                                _pipe@2 = aarondb@engine@entity:filter_by_time(
                                    _pipe@1,
                                    As_of_tx,
                                    As_of_valid
                                ),
                                aarondb@engine@entity:filter_active(
                                    _pipe@2,
                                    Db_state
                                )
                            end,
                            case Active of
                                [D | _] ->
                                    bind(Ctx, Var, {ref, erlang:element(2, D)});

                                [] ->
                                    {error, nil}
                            end
                        end
                    );

                {error, _} ->
                    []
            end;

        {error, _} ->
            []
    end.

-file("src/aarondb/engine/retrieval.gleam", 82).
-spec similarity_entity(
    aarondb@shared@state:db_state(),
    binary(),
    list(float()),
    float(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
similarity_entity(Db_state, Var, Vec, Threshold, Ctx) ->
    case aarondb@vec_index:size(erlang:element(15, Db_state)) > 0 of
        true ->
            Norm_vec = aarondb@vector:normalize(Vec),
            _pipe = aarondb@vec_index:search(
                erlang:element(15, Db_state),
                Norm_vec,
                Threshold,
                100
            ),
            gleam@list:filter_map(
                _pipe,
                fun(R) -> bind(Ctx, Var, {ref, erlang:element(2, R)}) end
            );

        false ->
            []
    end.
