-module(aarondb@reactive).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/reactive.gleam").
-export([start_link/0]).
-export_type([reactive_message/0, active_query/0, reactive_state/0]).

-type reactive_message() :: {subscribe,
        aarondb@shared@ast:'query'(),
        list(binary()),
        gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()),
        aarondb@shared@query_types:query_result()} |
    {unsubscribe,
        gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta())} |
    {notify, list(binary()), aarondb@shared@state:db_state()}.

-type active_query() :: {active_query,
        aarondb@shared@ast:'query'(),
        list(binary()),
        gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()),
        aarondb@shared@query_types:query_result()}.

-type reactive_state() :: {reactive_state, list(active_query())}.

-file("src/aarondb/reactive.gleam", 103).
-spec diff(
    aarondb@shared@query_types:query_result(),
    aarondb@shared@query_types:query_result()
) -> {aarondb@shared@query_types:query_result(),
    aarondb@shared@query_types:query_result()}.
diff(Old, New) ->
    Old_set = gleam@set:from_list(erlang:element(2, Old)),
    New_set = gleam@set:from_list(erlang:element(2, New)),
    Added_rows = begin
        _pipe = gleam@set:difference(New_set, Old_set),
        gleam@set:to_list(_pipe)
    end,
    Removed_rows = begin
        _pipe@1 = gleam@set:difference(Old_set, New_set),
        gleam@set:to_list(_pipe@1)
    end,
    {{query_result, Added_rows, erlang:element(3, New), none},
        {query_result, Removed_rows, erlang:element(3, New), none}}.

-file("src/aarondb/reactive.gleam", 44).
-spec start_link() -> {ok,
        gleam@erlang@process:subject(aarondb@shared@state:reactive_message())} |
    {error, gleam@otp@actor:start_error()}.
start_link() ->
    _pipe = gleam@otp@actor:new({reactive_state, []}),
    _pipe@1 = gleam@otp@actor:on_message(_pipe, fun(St, Msg) -> case Msg of
                {subscribe, Query, Attrs, Sub, Initial_state} ->
                    gleam@erlang@process:send(Sub, {initial, Initial_state}),
                    New_query = {active_query, Query, Attrs, Sub, Initial_state},
                    gleam@otp@actor:continue(
                        {reactive_state, [New_query | erlang:element(2, St)]}
                    );

                {unsubscribe, Subscriber} ->
                    Remaining = gleam@list:filter(
                        erlang:element(2, St),
                        fun(Aq) -> erlang:element(4, Aq) /= Subscriber end
                    ),
                    gleam@otp@actor:continue({reactive_state, Remaining});

                {notify, Changed_attrs, Db_state} ->
                    New_queries = gleam@list:filter_map(
                        erlang:element(2, St),
                        fun(Aq@1) ->
                            case aarondb_process_ffi:is_alive(
                                erlang:element(4, Aq@1)
                            ) of
                                false ->
                                    {error, nil};

                                true ->
                                    Is_affected = gleam@list:any(
                                        Changed_attrs,
                                        fun(Ca) ->
                                            gleam@list:contains(
                                                erlang:element(3, Aq@1),
                                                Ca
                                            )
                                        end
                                    ),
                                    case Is_affected of
                                        true ->
                                            Current_result = aarondb@engine:run(
                                                Db_state,
                                                erlang:element(2, Aq@1),
                                                [],
                                                none,
                                                none
                                            ),
                                            {Added, Removed} = diff(
                                                erlang:element(5, Aq@1),
                                                Current_result
                                            ),
                                            case (erlang:element(2, Added) =:= [])
                                            andalso (erlang:element(2, Removed)
                                            =:= []) of
                                                true ->
                                                    {ok, Aq@1};

                                                false ->
                                                    gleam@erlang@process:send(
                                                        erlang:element(4, Aq@1),
                                                        {delta, Added, Removed}
                                                    ),
                                                    {ok,
                                                        {active_query,
                                                            erlang:element(
                                                                2,
                                                                Aq@1
                                                            ),
                                                            erlang:element(
                                                                3,
                                                                Aq@1
                                                            ),
                                                            erlang:element(
                                                                4,
                                                                Aq@1
                                                            ),
                                                            Current_result}}
                                            end;

                                        false ->
                                            {ok, Aq@1}
                                    end
                            end
                        end
                    ),
                    gleam@otp@actor:continue({reactive_state, New_queries})
            end end),
    _pipe@2 = gleam@otp@actor:start(_pipe@1),
    gleam@result:map(_pipe@2, fun(Started) -> erlang:element(3, Started) end).
