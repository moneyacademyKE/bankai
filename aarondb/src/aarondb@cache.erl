-module(aarondb@cache).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/cache.gleam").
-export([start/1, get/2, set/3, invalidate/2, start_reactive/2]).
-export_type([message/2, cache_config/2, state/2]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type message(OQT, OQU) :: {get,
        OQT,
        gleam@erlang@process:subject(gleam@option:option(OQU))} |
    {set, OQT, OQU} |
    {invalidate, OQT} |
    clear |
    {handle_wal, list(aarondb@fact:datom())}.

-type cache_config(OQV, OQW) :: {cache_config,
        integer(),
        fun((aarondb@fact:datom(), OQV) -> boolean())} |
    {gleam_phantom, OQW}.

-type state(OQX, OQY) :: {state,
        gleam@dict:dict(OQX, OQY),
        list(OQX),
        cache_config(OQX, OQY)}.

-file("src/aarondb/cache.gleam", 41).
-spec handle_message(state(ORI, ORJ), message(ORI, ORJ)) -> gleam@otp@actor:next(state(ORI, ORJ), message(ORI, ORJ)).
handle_message(State, Msg) ->
    case Msg of
        {get, Key, Reply_to} ->
            case gleam_stdlib:map_get(erlang:element(2, State), Key) of
                {ok, Val} ->
                    gleam@erlang@process:send(Reply_to, {some, Val}),
                    gleam@otp@actor:continue(State);

                {error, nil} ->
                    gleam@erlang@process:send(Reply_to, none),
                    gleam@otp@actor:continue(State)
            end;

        {set, Key@1, Val@1} ->
            Entries = gleam@dict:insert(erlang:element(2, State), Key@1, Val@1),
            Order = [Key@1 |
                gleam@list:filter(
                    erlang:element(3, State),
                    fun(X) -> X /= Key@1 end
                )],
            {Entries@2, Order@2} = case erlang:length(Order) > erlang:element(
                2,
                erlang:element(4, State)
            ) of
                true ->
                    Last = begin
                        _pipe = gleam@list:last(Order),
                        gleam@result:unwrap(_pipe, Key@1)
                    end,
                    Order@1 = gleam@list:filter(
                        Order,
                        fun(X@1) -> X@1 /= Last end
                    ),
                    Entries@1 = gleam@dict:delete(Entries, Last),
                    {Entries@1, Order@1};

                false ->
                    {Entries, Order}
            end,
            gleam@otp@actor:continue(
                {state, Entries@2, Order@2, erlang:element(4, State)}
            );

        {invalidate, Key@2} ->
            Entries@3 = gleam@dict:delete(erlang:element(2, State), Key@2),
            Order@3 = gleam@list:filter(
                erlang:element(3, State),
                fun(X@2) -> X@2 /= Key@2 end
            ),
            gleam@otp@actor:continue(
                {state, Entries@3, Order@3, erlang:element(4, State)}
            );

        clear ->
            gleam@otp@actor:continue(
                {state, maps:new(), [], erlang:element(4, State)}
            );

        {handle_wal, Datoms} ->
            Invalid_keys = begin
                _pipe@1 = gleam@list:fold(
                    Datoms,
                    [],
                    fun(Acc, D) ->
                        gleam@list:fold(
                            maps:keys(erlang:element(2, State)),
                            Acc,
                            fun(Inner_acc, K) ->
                                case (erlang:element(
                                    3,
                                    erlang:element(4, State)
                                ))(D, K) of
                                    true ->
                                        [K | Inner_acc];

                                    false ->
                                        Inner_acc
                                end
                            end
                        )
                    end
                ),
                gleam@list:unique(_pipe@1)
            end,
            Entries@4 = gleam@list:fold(
                Invalid_keys,
                erlang:element(2, State),
                fun(Acc@1, K@1) -> gleam@dict:delete(Acc@1, K@1) end
            ),
            Order@4 = gleam@list:filter(
                erlang:element(3, State),
                fun(K@2) -> not gleam@list:contains(Invalid_keys, K@2) end
            ),
            gleam@otp@actor:continue(
                {state, Entries@4, Order@4, erlang:element(4, State)}
            )
    end.

-file("src/aarondb/cache.gleam", 27).
?DOC(" Start a new LRU cache actor with the given configuration.\n").
-spec start(cache_config(OQZ, ORA)) -> {ok,
        gleam@erlang@process:subject(message(OQZ, ORA))} |
    {error, gleam@otp@actor:start_error()}.
start(Config) ->
    Res = begin
        _pipe = gleam@otp@actor:new({state, maps:new(), [], Config}),
        _pipe@1 = gleam@otp@actor:on_message(_pipe, fun handle_message/2),
        gleam@otp@actor:start(_pipe@1)
    end,
    case Res of
        {ok, Started} ->
            {ok, erlang:element(3, Started)};

        {error, E} ->
            {error, E}
    end.

-file("src/aarondb/cache.gleam", 107).
?DOC(" Convenience function to wrap a cache in a simple get/set interface.\n").
-spec get(gleam@erlang@process:subject(message(ORU, ORV)), ORU) -> gleam@option:option(ORV).
get(Cache, Key) ->
    Reply_to = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Cache, {get, Key, Reply_to}),
    case gleam@erlang@process:'receive'(Reply_to, 5000) of
        {ok, Res} ->
            Res;

        {error, _} ->
            none
    end.

-file("src/aarondb/cache.gleam", 116).
-spec set(gleam@erlang@process:subject(message(OSA, OSB)), OSA, OSB) -> nil.
set(Cache, Key, Value) ->
    gleam@erlang@process:send(Cache, {set, Key, Value}).

-file("src/aarondb/cache.gleam", 120).
-spec invalidate(gleam@erlang@process:subject(message(OSF, any())), OSF) -> nil.
invalidate(Cache, Key) ->
    gleam@erlang@process:send(Cache, {invalidate, Key}).

-file("src/aarondb/cache.gleam", 143).
-spec wal_loop(
    gleam@erlang@process:subject(list(aarondb@fact:datom())),
    gleam@erlang@process:subject(message(any(), any()))
) -> any().
wal_loop(Wal_subject, Cache) ->
    case gleam@erlang@process:'receive'(Wal_subject, 60000) of
        {ok, Datoms} ->
            gleam@erlang@process:send(Cache, {handle_wal, Datoms}),
            wal_loop(Wal_subject, Cache);

        {error, _} ->
            wal_loop(Wal_subject, Cache)
    end.

-file("src/aarondb/cache.gleam", 125).
?DOC(" Start a reactive cache that automatically invalidates based on database changes.\n").
-spec start_reactive(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    cache_config(OSL, OSM)
) -> {ok, gleam@erlang@process:subject(message(OSL, OSM))} |
    {error, gleam@otp@actor:start_error()}.
start_reactive(Db, Config) ->
    case start(Config) of
        {ok, Cache} ->
            proc_lib:spawn_link(
                fun() ->
                    Wal_subject = gleam@erlang@process:new_subject(),
                    gleam@erlang@process:send(Db, {subscribe, Wal_subject}),
                    wal_loop(Wal_subject, Cache)
                end
            ),
            {ok, Cache};

        {error, E} ->
            {error, E}
    end.
