-module(aarondb@transactor@runtime).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/runtime.gleam").
-export([do_handle_transact/6, recover_state/1]).

-file("src/aarondb/transactor/runtime.gleam", 11).
-spec do_handle_transact(
    aarondb@shared@state:db_state(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    gleam@option:option(integer()),
    aarondb@fact:operation(),
    gleam@erlang@process:subject({ok, aarondb@shared@state:db_state()} |
        {error, binary()}),
    fun((aarondb@shared@state:db_state(), list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()}), gleam@option:option(integer()), aarondb@fact:operation()) -> {ok,
            {aarondb@shared@state:db_state(), list(aarondb@fact:datom())}} |
        {error, binary()})
) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), any()).
do_handle_transact(State, Facts, Valid_time, Op, Reply, _) ->
    case aarondb@transactor@domain:apply(
        State,
        {transaction, Facts, Valid_time, Op}
    ) of
        {ok, {outcome, Final_state, Datoms}} ->
            case aarondb@storage:insert(erlang:element(2, Final_state), Datoms) of
                {ok, nil} ->
                    Changed_attrs = begin
                        _pipe = gleam@list:map(
                            Datoms,
                            fun(D) -> erlang:element(3, D) end
                        ),
                        gleam@list:unique(_pipe)
                    end,
                    gleam@erlang@process:send(
                        erlang:element(11, State),
                        {notify, Changed_attrs, Final_state}
                    ),
                    gleam@list:each(
                        erlang:element(7, State),
                        fun(Sub) -> gleam@erlang@process:send(Sub, Datoms) end
                    ),
                    gleam@erlang@process:send(Reply, {ok, Final_state}),
                    gleam@otp@actor:continue(Final_state);

                {error, Error} ->
                    gleam@erlang@process:send(
                        Reply,
                        {error, aarondb@storage:error_message(Error)}
                    ),
                    gleam@otp@actor:continue(State)
            end;

        {error, E} ->
            gleam@erlang@process:send(Reply, {error, E}),
            gleam@otp@actor:continue(State)
    end.

-file("src/aarondb/transactor/runtime.gleam", 51).
-spec recover_state(aarondb@shared@state:db_state()) -> aarondb@shared@state:db_state().
recover_state(State) ->
    case aarondb@storage:read_all(erlang:element(2, State)) of
        {ok, Datoms} ->
            gleam@list:fold(
                Datoms,
                State,
                fun(Acc, D) ->
                    {S, _, _} = aarondb@transactor@apply:apply_datom(
                        Acc,
                        D,
                        erlang:element(6, D)
                    ),
                    S
                end
            );

        {error, _} ->
            State
    end.
