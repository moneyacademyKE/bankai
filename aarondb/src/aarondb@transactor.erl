-module(aarondb@transactor).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor.gleam").
-export([compute_next_state/4, start_with_timeout/2, start/1, start_named/2, start_distributed/2, retract_entity/3, log_query/2, get_state_with_timeout/2, get_state/1, set_schema_with_timeout/4, set_schema/3, register_function_with_timeout/4, register_function/3, register_composite_with_timeout/3, register_composite/2, register_predicate_with_timeout/4, register_predicate/3, store_rule_with_timeout/3, store_rule/2, set_config_with_timeout/3, set_config/2, transact_with_timeout/3, transact/2, retract/2, subscribe/1]).
-export_type([message/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type message() :: {transact,
        list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
        gleam@option:option(integer()),
        gleam@erlang@process:subject({ok, aarondb@shared@state:db_state()} |
            {error, binary()})} |
    {retract,
        list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
        gleam@option:option(integer()),
        gleam@erlang@process:subject({ok, aarondb@shared@state:db_state()} |
            {error, binary()})} |
    {get_state, gleam@erlang@process:subject(aarondb@shared@state:db_state())} |
    {set_schema,
        binary(),
        aarondb@fact:attribute_config(),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {register_function,
        binary(),
        fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
            binary(),
            aarondb@fact:value()})),
        gleam@erlang@process:subject(nil)} |
    {register_predicate,
        binary(),
        fun((aarondb@fact:value()) -> boolean()),
        gleam@erlang@process:subject(nil)} |
    {register_composite,
        list(binary()),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {store_rule,
        aarondb@shared@ast:rule(),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {set_reactive,
        gleam@erlang@process:subject(aarondb@shared@state:reactive_message())} |
    {join, gleam@erlang@process:pid_()} |
    {sync_datoms, list(aarondb@fact:datom())} |
    {compact, gleam@erlang@process:subject(nil)} |
    {set_config,
        aarondb@shared@state:config(),
        gleam@erlang@process:subject(nil)} |
    {sync, gleam@erlang@process:subject(nil)} |
    {boot,
        gleam@option:option(binary()),
        aarondb@storage:storage_adapter(),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {register_index_adapter,
        aarondb@shared@state:index_adapter(),
        gleam@erlang@process:subject(nil)} |
    {create_index,
        binary(),
        binary(),
        binary(),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {create_b_m25_index,
        binary(),
        gleam@erlang@process:subject({ok, nil} | {error, binary()})} |
    {subscribe, gleam@erlang@process:subject(list(aarondb@fact:datom()))} |
    {prune, integer(), list(binary()), gleam@erlang@process:subject(integer())} |
    {retract_entity,
        aarondb@fact:entity_id(),
        gleam@erlang@process:subject({ok, aarondb@shared@state:db_state()} |
            {error, binary()})} |
    tick |
    {log_query,
        aarondb@shared@state:query_context(),
        gleam@erlang@process:subject(nil)}.

-file("src/aarondb/transactor.gleam", 184).
-spec lifecycle_loop(gleam@erlang@process:subject(message())) -> any().
lifecycle_loop(Parent) ->
    gleam_erlang_ffi:sleep(5000),
    gleam@erlang@process:send(Parent, tick),
    lifecycle_loop(Parent).

-file("src/aarondb/transactor.gleam", 410).
-spec compute_next_state(
    aarondb@shared@state:db_state(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    gleam@option:option(integer()),
    aarondb@fact:operation()
) -> {ok, {aarondb@shared@state:db_state(), list(aarondb@fact:datom())}} |
    {error, binary()}.
compute_next_state(State, Facts, Valid_time, Op) ->
    aarondb@transactor@domain:compute_next_state(State, Facts, Valid_time, Op).

-file("src/aarondb/transactor.gleam", 419).
-spec handle_message(aarondb@shared@state:db_state(), message()) -> gleam@otp@actor:next(aarondb@shared@state:db_state(), message()).
handle_message(State, Msg) ->
    case Msg of
        {log_query, Ctx, Reply} ->
            aarondb@transactor@messages:log_query(State, Ctx, Reply);

        tick ->
            gleam@otp@actor:continue(
                aarondb@transactor@lifecycle:handle_tick(State)
            );

        {boot, Ets_name, _, Reply@1} ->
            case Ets_name of
                {some, Name} ->
                    aarondb@index@ets:init_tables(Name);

                none ->
                    nil
            end,
            Initialized = aarondb_mnesia_ffi:init(),
            case Initialized of
                {ok, nil} ->
                    New_state = aarondb@transactor@runtime:recover_state(State),
                    gleam@erlang@process:send(Reply@1, {ok, nil}),
                    gleam@otp@actor:continue(New_state);

                {error, Error} ->
                    gleam@erlang@process:send(Reply@1, {error, Error}),
                    gleam@otp@actor:continue(State)
            end;

        {transact, Facts, Vt, Reply_to} ->
            aarondb@transactor@runtime:do_handle_transact(
                State,
                Facts,
                Vt,
                assert,
                Reply_to,
                fun compute_next_state/4
            );

        {retract, Facts@1, Vt@1, Reply_to@1} ->
            aarondb@transactor@runtime:do_handle_transact(
                State,
                Facts@1,
                Vt@1,
                retract,
                Reply_to@1,
                fun compute_next_state/4
            );

        {retract_entity, Eid, Reply_to@2} ->
            Datoms = case erlang:element(14, State) of
                {some, Name@1} ->
                    aarondb@index@ets:lookup_datoms(
                        <<Name@1/binary, "_eavt"/utf8>>,
                        Eid
                    );

                none ->
                    aarondb@index:filter_by_entity(
                        erlang:element(3, State),
                        Eid
                    )
            end,
            Facts@2 = gleam@list:map(
                Datoms,
                fun(D) ->
                    {{uid, erlang:element(2, D)},
                        erlang:element(3, D),
                        erlang:element(4, D)}
                end
            ),
            aarondb@transactor@runtime:do_handle_transact(
                State,
                Facts@2,
                none,
                retract,
                Reply_to@2,
                fun compute_next_state/4
            );

        {get_state, Reply_to@3} ->
            gleam@erlang@process:send(Reply_to@3, State),
            gleam@otp@actor:continue(State);

        {set_schema, Attr, Config, Reply_to@4} ->
            Error@1 = case erlang:element(2, Config) of
                true ->
                    aarondb@transactor@schema:validate_unique(State, Attr);

                false ->
                    none
            end,
            Error@2 = case Error@1 of
                none ->
                    case erlang:element(5, Config) =:= one of
                        true ->
                            aarondb@transactor@schema:validate_cardinality_one(
                                State,
                                Attr
                            );

                        false ->
                            none
                    end;

                {some, E} ->
                    {some, E}
            end,
            aarondb@transactor@messages:set_schema(
                State,
                Attr,
                Config,
                Error@2,
                Reply_to@4
            );

        {register_function, Name@2, Func, Reply_to@5} ->
            aarondb@transactor@messages:register_function(
                State,
                Name@2,
                Func,
                Reply_to@5
            );

        {register_predicate, Name@3, Pred, Reply_to@6} ->
            aarondb@transactor@messages:register_predicate(
                State,
                Name@3,
                Pred,
                Reply_to@6
            );

        {register_composite, Attrs, Reply_to@7} ->
            aarondb@transactor@messages:register_composite(
                State,
                Attrs,
                aarondb@transactor@schema:validate_composite(State, Attrs),
                Reply_to@7
            );

        {store_rule, Rule, Reply_to@8} ->
            aarondb@transactor@messages:store_rule(
                State,
                Rule,
                Reply_to@8,
                fun compute_next_state/4
            );

        {subscribe, Reply_to@9} ->
            aarondb@transactor@messages:subscribe(State, Reply_to@9);

        {set_config, Config@1, Reply_to@10} ->
            aarondb@transactor@messages:set_config(State, Config@1, Reply_to@10);

        _ ->
            gleam@otp@actor:continue(State)
    end.

-file("src/aarondb/transactor.gleam", 111).
-spec do_start_after_reactive(
    aarondb@storage:storage_adapter(),
    boolean(),
    gleam@option:option(binary()),
    integer(),
    gleam@erlang@process:subject(aarondb@shared@state:reactive_message())
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
do_start_after_reactive(
    Store,
    Is_distributed,
    Ets_name,
    Timeout_ms,
    Reactive_subject
) ->
    Base_state = {db_state,
        Store,
        aarondb@index:new_index(),
        aarondb@index:new_aindex(),
        aarondb@index:new_avindex(),
        0,
        [],
        maps:new(),
        maps:new(),
        [],
        Reactive_subject,
        [],
        Is_distributed,
        Ets_name,
        aarondb@vec_index:new(),
        maps:new(),
        aarondb@index@art:new(),
        maps:new(),
        maps:new(),
        maps:new(),
        [],
        maps:new(),
        maps:new(),
        {config, 1000, 1000, false, 10000},
        []},
    Res = begin
        _pipe = gleam@otp@actor:new(Base_state),
        _pipe@1 = gleam@otp@actor:on_message(_pipe, fun handle_message/2),
        gleam@otp@actor:start(_pipe@1)
    end,
    case Res of
        {ok, Started} ->
            Subj = erlang:element(3, Started),
            Reply = gleam@erlang@process:new_subject(),
            gleam@erlang@process:send(Subj, {boot, Ets_name, Store, Reply}),
            case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
                {error, _} ->
                    {error, init_timeout};

                {ok, {error, _}} ->
                    {error, init_timeout};

                {ok, {ok, nil}} ->
                    Pid = aarondb_process_ffi:subject_to_pid(Subj),
                    _ = case Is_distributed of
                        true ->
                            nil;

                        false ->
                            _ = aarondb_global_ffi:register(
                                <<"aarondb_leader"/utf8>>,
                                Pid
                            ),
                            nil
                    end,
                    _ = proc_lib:spawn_link(fun() -> lifecycle_loop(Subj) end),
                    {ok, Subj}
            end;

        {error, E} ->
            {error, E}
    end.

-file("src/aarondb/transactor.gleam", 92).
-spec do_start_named(
    aarondb@storage:storage_adapter(),
    boolean(),
    gleam@option:option(binary()),
    integer()
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
do_start_named(Store, Is_distributed, Ets_name, Timeout_ms) ->
    case aarondb@reactive:start_link() of
        {error, Error} ->
            {error, Error};

        {ok, Reactive_subject} ->
            do_start_after_reactive(
                Store,
                Is_distributed,
                Ets_name,
                Timeout_ms,
                Reactive_subject
            )
    end.

-file("src/aarondb/transactor.gleam", 85).
-spec start_with_timeout(aarondb@storage:storage_adapter(), integer()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with_timeout(Store, Timeout_ms) ->
    do_start_named(Store, false, none, Timeout_ms).

-file("src/aarondb/transactor.gleam", 65).
-spec start(aarondb@storage:storage_adapter()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(Store) ->
    start_with_timeout(Store, 1000).

-file("src/aarondb/transactor.gleam", 71).
-spec start_named(binary(), aarondb@storage:storage_adapter()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_named(Name, Store) ->
    do_start_named(Store, false, {some, Name}, 1000).

-file("src/aarondb/transactor.gleam", 78).
-spec start_distributed(binary(), aarondb@storage:storage_adapter()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_distributed(Name, Store) ->
    do_start_named(Store, true, {some, Name}, 1000).

-file("src/aarondb/transactor.gleam", 190).
-spec retract_entity(
    gleam@erlang@process:subject(message()),
    aarondb@fact:entity_id(),
    gleam@erlang@process:subject({ok, aarondb@shared@state:db_state()} |
        {error, binary()})
) -> nil.
retract_entity(Subj, Eid, Reply) ->
    gleam@erlang@process:send(Subj, {retract_entity, Eid, Reply}).

-file("src/aarondb/transactor.gleam", 198).
-spec log_query(
    gleam@erlang@process:subject(message()),
    aarondb@shared@state:query_context()
) -> nil.
log_query(Subj, Ctx) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {log_query, Ctx, Reply}),
    _ = gleam@erlang@process:'receive'(Reply, 100),
    nil.

-file("src/aarondb/transactor.gleam", 211).
?DOC(
    " Read the current state before an explicit caller-supplied deadline.\n"
    " A non-positive deadline fails closed rather than hiding an invalid request.\n"
).
-spec get_state_with_timeout(gleam@erlang@process:subject(message()), integer()) -> {ok,
        aarondb@shared@state:db_state()} |
    {error, binary()}.
get_state_with_timeout(Subj, Timeout_ms) ->
    case Timeout_ms > 0 of
        false ->
            {error, <<"Timeout getting database state"/utf8>>};

        true ->
            Reply = gleam@erlang@process:new_subject(),
            gleam@erlang@process:send(Subj, {get_state, Reply}),
            case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
                {ok, Current_state} ->
                    {ok, Current_state};

                {error, _} ->
                    {error, <<"Timeout getting database state"/utf8>>}
            end
    end.

-file("src/aarondb/transactor.gleam", 231).
?DOC(
    " **Compatibility read helper.** This function uses the default five-second\n"
    " deadline and cannot report a timeout. New integrations should call\n"
    " `get_state_with_timeout/2` and handle its `Result`.\n"
).
-spec get_state(gleam@erlang@process:subject(message())) -> aarondb@shared@state:db_state().
get_state(Subj) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {get_state, Reply}),
    State@1 = case gleam@erlang@process:'receive'(Reply, 5000) of
        {ok, State} -> State;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/transactor"/utf8>>,
                        function => <<"get_state"/utf8>>,
                        line => 234,
                        value => _assert_fail,
                        start => 6761,
                        'end' => 6812,
                        pattern_start => 6772,
                        pattern_end => 6781})
    end,
    State@1.

-file("src/aarondb/transactor.gleam", 246).
-spec set_schema_with_timeout(
    gleam@erlang@process:subject(message()),
    binary(),
    aarondb@fact:attribute_config(),
    integer()
) -> {ok, nil} | {error, binary()}.
set_schema_with_timeout(Subj, Attr, Config, Timeout_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {set_schema, Attr, Config, Reply}),
    case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
        {ok, Res} ->
            Res;

        {error, _} ->
            {error, <<"Timeout setting schema"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 238).
-spec set_schema(
    gleam@erlang@process:subject(message()),
    binary(),
    aarondb@fact:attribute_config()
) -> {ok, nil} | {error, binary()}.
set_schema(Subj, Attr, Config) ->
    set_schema_with_timeout(Subj, Attr, Config, 5000).

-file("src/aarondb/transactor.gleam", 271).
-spec register_function_with_timeout(
    gleam@erlang@process:subject(message()),
    binary(),
    fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()})),
    integer()
) -> {ok, nil} | {error, binary()}.
register_function_with_timeout(Subj, Name, Func, Timeout_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {register_function, Name, Func, Reply}),
    case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, <<"Timeout registering function"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 262).
?DOC(
    " **Compatibility registration helper.** This function cannot surface an\n"
    " actor timeout. New integrations should use `register_function_with_timeout/4`.\n"
).
-spec register_function(
    gleam@erlang@process:subject(message()),
    binary(),
    fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()}))
) -> nil.
register_function(Subj, Name, Func) ->
    _ = register_function_with_timeout(Subj, Name, Func, 5000),
    nil.

-file("src/aarondb/transactor.gleam", 292).
-spec register_composite_with_timeout(
    gleam@erlang@process:subject(message()),
    list(binary()),
    integer()
) -> {ok, nil} | {error, binary()}.
register_composite_with_timeout(Subj, Attrs, Timeout_ms) ->
    case Timeout_ms > 0 of
        false ->
            {error, <<"Timeout registering composite"/utf8>>};

        true ->
            Reply = gleam@erlang@process:new_subject(),
            gleam@erlang@process:send(Subj, {register_composite, Attrs, Reply}),
            case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
                {ok, Res} ->
                    Res;

                {error, _} ->
                    {error, <<"Timeout registering composite"/utf8>>}
            end
    end.

-file("src/aarondb/transactor.gleam", 285).
-spec register_composite(
    gleam@erlang@process:subject(message()),
    list(binary())
) -> {ok, nil} | {error, binary()}.
register_composite(Subj, Attrs) ->
    register_composite_with_timeout(Subj, Attrs, 5000).

-file("src/aarondb/transactor.gleam", 319).
-spec register_predicate_with_timeout(
    gleam@erlang@process:subject(message()),
    binary(),
    fun((aarondb@fact:value()) -> boolean()),
    integer()
) -> {ok, nil} | {error, binary()}.
register_predicate_with_timeout(Subj, Name, Pred, Timeout_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {register_predicate, Name, Pred, Reply}),
    case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, <<"Timeout registering predicate"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 310).
-spec register_predicate(
    gleam@erlang@process:subject(message()),
    binary(),
    fun((aarondb@fact:value()) -> boolean())
) -> nil.
register_predicate(Subj, Name, Pred) ->
    _ = register_predicate_with_timeout(Subj, Name, Pred, 5000),
    nil.

-file("src/aarondb/transactor.gleam", 340).
-spec store_rule_with_timeout(
    gleam@erlang@process:subject(message()),
    aarondb@shared@ast:rule(),
    integer()
) -> {ok, nil} | {error, binary()}.
store_rule_with_timeout(Subj, Rule, Timeout_ms) ->
    case Timeout_ms > 0 of
        false ->
            {error, <<"Timeout storing rule"/utf8>>};

        true ->
            Reply = gleam@erlang@process:new_subject(),
            gleam@erlang@process:send(Subj, {store_rule, Rule, Reply}),
            case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
                {ok, Res} ->
                    Res;

                {error, _} ->
                    {error, <<"Timeout storing rule"/utf8>>}
            end
    end.

-file("src/aarondb/transactor.gleam", 333).
-spec store_rule(
    gleam@erlang@process:subject(message()),
    aarondb@shared@ast:rule()
) -> {ok, nil} | {error, binary()}.
store_rule(Subj, Rule) ->
    store_rule_with_timeout(Subj, Rule, 5000).

-file("src/aarondb/transactor.gleam", 365).
-spec set_config_with_timeout(
    gleam@erlang@process:subject(message()),
    aarondb@shared@state:config(),
    integer()
) -> {ok, nil} | {error, binary()}.
set_config_with_timeout(Subj, Config, Timeout_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {set_config, Config, Reply}),
    case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, <<"Timeout setting configuration"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 360).
?DOC(
    " **Compatibility configuration helper.** This function cannot surface an\n"
    " actor timeout. New integrations should use `set_config_with_timeout/3`.\n"
).
-spec set_config(
    gleam@erlang@process:subject(message()),
    aarondb@shared@state:config()
) -> nil.
set_config(Subj, Config) ->
    _ = set_config_with_timeout(Subj, Config, 5000),
    nil.

-file("src/aarondb/transactor.gleam", 385).
-spec transact_with_timeout(
    gleam@erlang@process:subject(message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    integer()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact_with_timeout(Subj, Facts, Timeout_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {transact, Facts, none, Reply}),
    case gleam@erlang@process:'receive'(Reply, Timeout_ms) of
        {ok, Res} ->
            Res;

        {error, _} ->
            {error, <<"Transaction timeout"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 378).
-spec transact(
    gleam@erlang@process:subject(message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact(Subj, Facts) ->
    transact_with_timeout(Subj, Facts, 5000).

-file("src/aarondb/transactor.gleam", 398).
-spec retract(
    gleam@erlang@process:subject(message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
retract(Subj, Facts) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {retract, Facts, none, Reply}),
    case gleam@erlang@process:'receive'(Reply, 5000) of
        {ok, Res} ->
            Res;

        {error, _} ->
            {error, <<"Retraction timeout"/utf8>>}
    end.

-file("src/aarondb/transactor.gleam", 531).
-spec subscribe(gleam@erlang@process:subject(message())) -> gleam@erlang@process:subject(list(aarondb@fact:datom())).
subscribe(Subj) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subj, {subscribe, Reply}),
    Reply.
