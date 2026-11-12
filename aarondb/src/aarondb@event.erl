-module(aarondb@event).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/event.gleam").
-export([record/4, on_event/3]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/event.gleam", 13).
?DOC(
    " Records a new event into the database.\n"
    " An event is modeled as an entity with a type, timestamp, and optional payload attributes.\n"
).
-spec record(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    integer(),
    list({binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
record(Db, Event_type, Timestamp, Payload) ->
    Eid = aarondb@fact:event_uid(Event_type, Timestamp),
    Event_facts = [{Eid, <<"event/type"/utf8>>, {str, Event_type}},
        {Eid, <<"event/timestamp"/utf8>>, {int, Timestamp}} |
        gleam@list:map(
            Payload,
            fun(P) -> {Eid, erlang:element(1, P), erlang:element(2, P)} end
        )],
    aarondb@transactor:transact(Db, Event_facts).

-file("src/aarondb/event.gleam", 78).
-spec process_results(
    aarondb@shared@query_types:query_result(),
    aarondb@shared@state:db_state(),
    fun((aarondb@shared@state:db_state(), aarondb@fact:eid()) -> nil)
) -> nil.
process_results(Results, State, Callback) ->
    gleam@list:each(
        erlang:element(2, Results),
        fun(Binding) -> case gleam_stdlib:map_get(Binding, <<"e"/utf8>>) of
                {ok, {ref, Eid}} ->
                    Callback(State, {uid, Eid});

                _ ->
                    nil
            end end
    ).

-file("src/aarondb/event.gleam", 56).
-spec event_loop(
    gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()),
    fun((aarondb@shared@state:db_state(), aarondb@fact:eid()) -> nil),
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta())
) -> any().
event_loop(Sub, Callback, Db, Proxy) ->
    case gleam_erlang_ffi:'receive'(Sub) of
        {initial, Results} ->
            State = aarondb@transactor:get_state(Db),
            process_results(Results, State, Callback),
            gleam@erlang@process:send(Proxy, {initial, Results}),
            event_loop(Sub, Callback, Db, Proxy);

        {delta, Added, Removed} ->
            State@1 = aarondb@transactor:get_state(Db),
            process_results(Added, State@1, Callback),
            gleam@erlang@process:send(Proxy, {delta, Added, Removed}),
            event_loop(Sub, Callback, Db, Proxy)
    end.

-file("src/aarondb/event.gleam", 32).
?DOC(
    " Convenience function to create an event listener.\n"
    " This subscribes to the database's reactive system for assertions of the specified event type.\n"
).
-spec on_event(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    fun((aarondb@shared@state:db_state(), aarondb@fact:eid()) -> nil)
) -> gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()).
on_event(Db, Event_type, Callback) ->
    Proxy = gleam@erlang@process:new_subject(),
    proc_lib:spawn_link(
        fun() ->
            Sub = gleam@erlang@process:new_subject(),
            Query = begin
                _pipe = aarondb@q:new(),
                _pipe@1 = aarondb@q:where(
                    _pipe,
                    aarondb@q:v(<<"e"/utf8>>),
                    <<"event/type"/utf8>>,
                    aarondb@q:s(Event_type)
                ),
                aarondb@q:to_query(_pipe@1)
            end,
            aarondb:subscribe(Db, Query, Sub),
            event_loop(Sub, Callback, Db, Proxy)
        end
    ),
    Proxy.
