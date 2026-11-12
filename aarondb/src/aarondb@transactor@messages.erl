-module(aarondb@transactor@messages).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/messages.gleam").
-export([log_query/3, set_schema/5, register_function/4, register_predicate/4, register_composite/4, store_rule/4, subscribe/2, set_config/3]).

-file("src/aarondb/transactor/messages.gleam", 13).
-spec log_query(
    aarondb@shared@state:db_state(),
    aarondb@shared@state:query_context(),
    gleam@erlang@process:subject(nil)
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
log_query(Db_state, Ctx, Reply) ->
    History = lists:append(erlang:element(25, Db_state), [Ctx]),
    Trimmed = case erlang:length(History) > 100 of
        true ->
            gleam@list:drop(History, erlang:length(History) - 100);

        false ->
            History
    end,
    gleam@erlang@process:send(Reply, nil),
    gleam@otp@actor:continue(
        {db_state,
            erlang:element(2, Db_state),
            erlang:element(3, Db_state),
            erlang:element(4, Db_state),
            erlang:element(5, Db_state),
            erlang:element(6, Db_state),
            erlang:element(7, Db_state),
            erlang:element(8, Db_state),
            erlang:element(9, Db_state),
            erlang:element(10, Db_state),
            erlang:element(11, Db_state),
            erlang:element(12, Db_state),
            erlang:element(13, Db_state),
            erlang:element(14, Db_state),
            erlang:element(15, Db_state),
            erlang:element(16, Db_state),
            erlang:element(17, Db_state),
            erlang:element(18, Db_state),
            erlang:element(19, Db_state),
            erlang:element(20, Db_state),
            erlang:element(21, Db_state),
            erlang:element(22, Db_state),
            erlang:element(23, Db_state),
            erlang:element(24, Db_state),
            Trimmed}
    ).

-file("src/aarondb/transactor/messages.gleam", 27).
-spec set_schema(
    aarondb@shared@state:db_state(),
    binary(),
    aarondb@fact:attribute_config(),
    gleam@option:option(binary()),
    gleam@erlang@process:subject({ok, nil} | {error, binary()})
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
set_schema(Db_state, Attr, Config, Error, Reply_to) ->
    case Error of
        {some, E} ->
            gleam@erlang@process:send(Reply_to, {error, E}),
            gleam@otp@actor:continue(Db_state);

        none ->
            New_schema = gleam@dict:insert(
                erlang:element(8, Db_state),
                Attr,
                Config
            ),
            gleam@erlang@process:send(Reply_to, {ok, nil}),
            gleam@otp@actor:continue(
                {db_state,
                    erlang:element(2, Db_state),
                    erlang:element(3, Db_state),
                    erlang:element(4, Db_state),
                    erlang:element(5, Db_state),
                    erlang:element(6, Db_state),
                    erlang:element(7, Db_state),
                    New_schema,
                    erlang:element(9, Db_state),
                    erlang:element(10, Db_state),
                    erlang:element(11, Db_state),
                    erlang:element(12, Db_state),
                    erlang:element(13, Db_state),
                    erlang:element(14, Db_state),
                    erlang:element(15, Db_state),
                    erlang:element(16, Db_state),
                    erlang:element(17, Db_state),
                    erlang:element(18, Db_state),
                    erlang:element(19, Db_state),
                    erlang:element(20, Db_state),
                    erlang:element(21, Db_state),
                    erlang:element(22, Db_state),
                    erlang:element(23, Db_state),
                    erlang:element(24, Db_state),
                    erlang:element(25, Db_state)}
            )
    end.

-file("src/aarondb/transactor/messages.gleam", 47).
-spec register_function(
    aarondb@shared@state:db_state(),
    binary(),
    fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()})),
    gleam@erlang@process:subject(nil)
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
register_function(Db_state, Name, Func, Reply_to) ->
    New_funcs = gleam@dict:insert(erlang:element(9, Db_state), Name, Func),
    gleam@erlang@process:send(Reply_to, nil),
    gleam@otp@actor:continue(
        {db_state,
            erlang:element(2, Db_state),
            erlang:element(3, Db_state),
            erlang:element(4, Db_state),
            erlang:element(5, Db_state),
            erlang:element(6, Db_state),
            erlang:element(7, Db_state),
            erlang:element(8, Db_state),
            New_funcs,
            erlang:element(10, Db_state),
            erlang:element(11, Db_state),
            erlang:element(12, Db_state),
            erlang:element(13, Db_state),
            erlang:element(14, Db_state),
            erlang:element(15, Db_state),
            erlang:element(16, Db_state),
            erlang:element(17, Db_state),
            erlang:element(18, Db_state),
            erlang:element(19, Db_state),
            erlang:element(20, Db_state),
            erlang:element(21, Db_state),
            erlang:element(22, Db_state),
            erlang:element(23, Db_state),
            erlang:element(24, Db_state),
            erlang:element(25, Db_state)}
    ).

-file("src/aarondb/transactor/messages.gleam", 58).
-spec register_predicate(
    aarondb@shared@state:db_state(),
    binary(),
    fun((aarondb@fact:value()) -> boolean()),
    gleam@erlang@process:subject(nil)
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
register_predicate(Db_state, Name, Pred, Reply_to) ->
    New_preds = gleam@dict:insert(erlang:element(20, Db_state), Name, Pred),
    gleam@erlang@process:send(Reply_to, nil),
    gleam@otp@actor:continue(
        {db_state,
            erlang:element(2, Db_state),
            erlang:element(3, Db_state),
            erlang:element(4, Db_state),
            erlang:element(5, Db_state),
            erlang:element(6, Db_state),
            erlang:element(7, Db_state),
            erlang:element(8, Db_state),
            erlang:element(9, Db_state),
            erlang:element(10, Db_state),
            erlang:element(11, Db_state),
            erlang:element(12, Db_state),
            erlang:element(13, Db_state),
            erlang:element(14, Db_state),
            erlang:element(15, Db_state),
            erlang:element(16, Db_state),
            erlang:element(17, Db_state),
            erlang:element(18, Db_state),
            erlang:element(19, Db_state),
            New_preds,
            erlang:element(21, Db_state),
            erlang:element(22, Db_state),
            erlang:element(23, Db_state),
            erlang:element(24, Db_state),
            erlang:element(25, Db_state)}
    ).

-file("src/aarondb/transactor/messages.gleam", 69).
-spec register_composite(
    aarondb@shared@state:db_state(),
    list(binary()),
    boolean(),
    gleam@erlang@process:subject({ok, nil} | {error, binary()})
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
register_composite(Db_state, Attrs, Has_violations, Reply_to) ->
    case Has_violations of
        true ->
            gleam@erlang@process:send(
                Reply_to,
                {error,
                    <<"Existing data violates new composite: "/utf8,
                        (gleam@string:inspect(
                            gleam@list:sort(Attrs, fun gleam@string:compare/2)
                        ))/binary>>}
            ),
            gleam@otp@actor:continue(Db_state);

        false ->
            New_composites = [Attrs | erlang:element(10, Db_state)],
            gleam@erlang@process:send(Reply_to, {ok, nil}),
            gleam@otp@actor:continue(
                {db_state,
                    erlang:element(2, Db_state),
                    erlang:element(3, Db_state),
                    erlang:element(4, Db_state),
                    erlang:element(5, Db_state),
                    erlang:element(6, Db_state),
                    erlang:element(7, Db_state),
                    erlang:element(8, Db_state),
                    erlang:element(9, Db_state),
                    New_composites,
                    erlang:element(11, Db_state),
                    erlang:element(12, Db_state),
                    erlang:element(13, Db_state),
                    erlang:element(14, Db_state),
                    erlang:element(15, Db_state),
                    erlang:element(16, Db_state),
                    erlang:element(17, Db_state),
                    erlang:element(18, Db_state),
                    erlang:element(19, Db_state),
                    erlang:element(20, Db_state),
                    erlang:element(21, Db_state),
                    erlang:element(22, Db_state),
                    erlang:element(23, Db_state),
                    erlang:element(24, Db_state),
                    erlang:element(25, Db_state)}
            )
    end.

-file("src/aarondb/transactor/messages.gleam", 96).
-spec store_rule(
    aarondb@shared@state:db_state(),
    aarondb@shared@ast:rule(),
    gleam@erlang@process:subject({ok, nil} | {error, binary()}),
    fun((aarondb@shared@state:db_state(), list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()}), gleam@option:option(integer()), aarondb@fact:operation()) -> {ok,
            {aarondb@shared@state:db_state(), list(aarondb@fact:datom())}} |
        {error, binary()})
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
store_rule(Db_state, Rule, Reply_to, Compute_next_state) ->
    New_rules = [Rule | erlang:element(21, Db_state)],
    Rule_fact = {{uid, {entity_id, gleam@int:random(1000000000)}},
        <<"_rule/content"/utf8>>,
        {str, gleam@string:inspect(Rule)}},
    case Compute_next_state(Db_state, [Rule_fact], none, assert) of
        {ok, {Final_state, Datoms}} ->
            case aarondb@storage:insert(erlang:element(2, Final_state), Datoms) of
                {ok, nil} ->
                    Final_state_with_rules = {db_state,
                        erlang:element(2, Final_state),
                        erlang:element(3, Final_state),
                        erlang:element(4, Final_state),
                        erlang:element(5, Final_state),
                        erlang:element(6, Final_state),
                        erlang:element(7, Final_state),
                        erlang:element(8, Final_state),
                        erlang:element(9, Final_state),
                        erlang:element(10, Final_state),
                        erlang:element(11, Final_state),
                        erlang:element(12, Final_state),
                        erlang:element(13, Final_state),
                        erlang:element(14, Final_state),
                        erlang:element(15, Final_state),
                        erlang:element(16, Final_state),
                        erlang:element(17, Final_state),
                        erlang:element(18, Final_state),
                        erlang:element(19, Final_state),
                        erlang:element(20, Final_state),
                        New_rules,
                        erlang:element(22, Final_state),
                        erlang:element(23, Final_state),
                        erlang:element(24, Final_state),
                        erlang:element(25, Final_state)},
                    gleam@erlang@process:send(Reply_to, {ok, nil}),
                    gleam@otp@actor:continue(Final_state_with_rules);

                {error, Error} ->
                    gleam@erlang@process:send(
                        Reply_to,
                        {error, aarondb@storage:error_message(Error)}
                    ),
                    gleam@otp@actor:continue(Db_state)
            end;

        {error, E} ->
            gleam@erlang@process:send(Reply_to, {error, E}),
            gleam@otp@actor:continue(Db_state)
    end.

-file("src/aarondb/transactor/messages.gleam", 136).
-spec subscribe(
    aarondb@shared@state:db_state(),
    gleam@erlang@process:subject(list(aarondb@fact:datom()))
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
subscribe(Db_state, Reply_to) ->
    New_subscribers = [Reply_to | erlang:element(7, Db_state)],
    gleam@otp@actor:continue(
        {db_state,
            erlang:element(2, Db_state),
            erlang:element(3, Db_state),
            erlang:element(4, Db_state),
            erlang:element(5, Db_state),
            erlang:element(6, Db_state),
            New_subscribers,
            erlang:element(8, Db_state),
            erlang:element(9, Db_state),
            erlang:element(10, Db_state),
            erlang:element(11, Db_state),
            erlang:element(12, Db_state),
            erlang:element(13, Db_state),
            erlang:element(14, Db_state),
            erlang:element(15, Db_state),
            erlang:element(16, Db_state),
            erlang:element(17, Db_state),
            erlang:element(18, Db_state),
            erlang:element(19, Db_state),
            erlang:element(20, Db_state),
            erlang:element(21, Db_state),
            erlang:element(22, Db_state),
            erlang:element(23, Db_state),
            erlang:element(24, Db_state),
            erlang:element(25, Db_state)}
    ).

-file("src/aarondb/transactor/messages.gleam", 144).
-spec set_config(
    aarondb@shared@state:db_state(),
    aarondb@shared@state:config(),
    gleam@erlang@process:subject(nil)
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
set_config(Db_state, Config, Reply_to) ->
    New_state = {db_state,
        erlang:element(2, Db_state),
        erlang:element(3, Db_state),
        erlang:element(4, Db_state),
        erlang:element(5, Db_state),
        erlang:element(6, Db_state),
        erlang:element(7, Db_state),
        erlang:element(8, Db_state),
        erlang:element(9, Db_state),
        erlang:element(10, Db_state),
        erlang:element(11, Db_state),
        erlang:element(12, Db_state),
        erlang:element(13, Db_state),
        erlang:element(14, Db_state),
        erlang:element(15, Db_state),
        erlang:element(16, Db_state),
        erlang:element(17, Db_state),
        erlang:element(18, Db_state),
        erlang:element(19, Db_state),
        erlang:element(20, Db_state),
        erlang:element(21, Db_state),
        erlang:element(22, Db_state),
        erlang:element(23, Db_state),
        Config,
        erlang:element(25, Db_state)},
    gleam@erlang@process:send(Reply_to, nil),
    gleam@otp@actor:continue(New_state).
