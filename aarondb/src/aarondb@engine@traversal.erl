-module(aarondb@engine@traversal).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/traversal.gleam").
-export([traverse/4]).

-file("src/aarondb/engine/traversal.gleam", 67).
-spec incoming(aarondb@shared@state:db_state(), integer(), binary()) -> list(integer()).
incoming(Db_state, Id, Attr) ->
    Datoms = case erlang:element(14, Db_state) of
        {some, Name} ->
            _pipe = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_aevt"/utf8>>,
                Attr
            ),
            gleam@list:filter(_pipe, fun(D) -> case erlang:element(4, D) of
                        {ref, {entity_id, V_id}} ->
                            V_id =:= Id;

                        {int, V_id@1} ->
                            V_id@1 =:= Id;

                        _ ->
                            false
                    end end);

        none ->
            aarondb@index:get_datoms_by_val(
                erlang:element(4, Db_state),
                Attr,
                {ref, {entity_id, Id}}
            )
    end,
    _pipe@1 = aarondb@engine@entity:filter_active(Datoms, Db_state),
    gleam@list:map(
        _pipe@1,
        fun(D@1) ->
            {entity_id, E} = erlang:element(2, D@1),
            E
        end
    ).

-file("src/aarondb/engine/traversal.gleam", 48).
-spec outgoing(aarondb@shared@state:db_state(), integer(), binary()) -> list(integer()).
outgoing(Db_state, Id, Attr) ->
    Datoms = case erlang:element(14, Db_state) of
        {some, Name} ->
            _pipe = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                {entity_id, Id}
            ),
            gleam@list:filter(
                _pipe,
                fun(D) -> erlang:element(3, D) =:= Attr end
            );

        none ->
            aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, Db_state),
                {entity_id, Id},
                Attr
            )
    end,
    _pipe@1 = aarondb@engine@entity:filter_active(Datoms, Db_state),
    gleam@list:filter_map(_pipe@1, fun(D@1) -> case erlang:element(4, D@1) of
                {ref, {entity_id, V_id}} ->
                    {ok, V_id};

                {int, V_id@1} ->
                    {ok, V_id@1};

                _ ->
                    {error, nil}
            end end).

-file("src/aarondb/engine/traversal.gleam", 25).
-spec do_traverse(
    aarondb@shared@state:db_state(),
    list(integer()),
    list(aarondb@shared@query_types:traversal_step())
) -> list(integer()).
do_traverse(Db_state, Current_ids, Expr) ->
    case Expr of
        [] ->
            Current_ids;

        [Step | Rest] ->
            Next_ids = begin
                _pipe = gleam@list:fold(
                    Current_ids,
                    [],
                    fun(Acc, Id) ->
                        Step_results = case Step of
                            {out, Attr} ->
                                outgoing(Db_state, Id, Attr);

                            {in, Attr@1} ->
                                incoming(Db_state, Id, Attr@1)
                        end,
                        lists:append(Step_results, Acc)
                    end
                ),
                gleam@list:unique(_pipe)
            end,
            do_traverse(Db_state, Next_ids, Rest)
    end.

-file("src/aarondb/engine/traversal.gleam", 10).
-spec traverse(
    aarondb@shared@state:db_state(),
    integer(),
    list(aarondb@shared@query_types:traversal_step()),
    integer()
) -> {ok, list(aarondb@fact:value())} | {error, binary()}.
traverse(Db_state, Start_id, Expr, Max_depth) ->
    case erlang:length(Expr) > Max_depth of
        true ->
            {error, <<"DepthLimitExceeded"/utf8>>};

        false ->
            Result_eids = do_traverse(Db_state, [Start_id], Expr),
            {ok,
                gleam@list:map(
                    Result_eids,
                    fun(Id) -> {ref, {entity_id, Id}} end
                )}
    end.
