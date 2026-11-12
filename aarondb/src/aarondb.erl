-module(aarondb).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb.gleam").
-export([diff_scan_limits/1, temporal_scan_limits/1, start_link/2, new_with_adapter_and_timeout/2, new_with_adapter/1, new/0, start_named/2, start_distributed/2, connect/1, transact/2, transact_at/3, transact_with_timeout/3, retract/2, retract_at/3, prune/3, trigger_eviction/1, retract_entity/2, with_facts/2, explain_speculation/1, get/3, get_one/3, set_schema/3, set_schema_with_timeout/4, history/2, pull/3, diff/3, diff_bounded/4, pull_all/0, pull_attr/1, pull_except/1, pull_recursive/2, 'query'/2, q/2, query_at/4, query_state/2, query_state_at/4, execute/2, query_state_with_rules/3, query_with_rules/3, as_of/3, as_of_valid/3, as_of_bounded/4, as_of_valid_bounded/4, as_of_bitemporal/4, as_of_bitemporal_bounded/5, p/1, register_function/3, register_function_with_timeout/4, register_composite/2, register_composite_with_timeout/3, register_predicate/3, register_predicate_with_timeout/4, store_rule/2, store_rule_with_timeout/3, set_config/2, set_config_with_timeout/3, subscribe/3, unsubscribe/2, subscribe_wal/2, get_state/1, sync/1, traverse/4]).
-export_type([temporal_scan_limits/0, temporal_scan_error/0, diff_scan_limits/0, diff_scan_error/0, speculative_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type temporal_scan_limits() :: {temporal_scan_limits, integer()}.

-type temporal_scan_error() :: invalid_temporal_scan_limit |
    temporal_scan_budget_exceeded.

-type diff_scan_limits() :: {diff_scan_limits, integer()}.

-type diff_scan_error() :: invalid_diff_range |
    invalid_diff_scan_limit |
    diff_scan_budget_exceeded.

-type speculative_result() :: {speculative_result,
        aarondb@shared@state:db_state(),
        list(aarondb@fact:datom())}.

-file("src/aarondb.gleam", 66).
-spec diff_scan_limits(integer()) -> {ok, diff_scan_limits()} |
    {error, diff_scan_error()}.
diff_scan_limits(Max_datoms) ->
    case Max_datoms > 0 of
        true ->
            {ok, {diff_scan_limits, Max_datoms}};

        false ->
            {error, invalid_diff_scan_limit}
    end.

-file("src/aarondb.gleam", 75).
-spec temporal_scan_limits(integer()) -> {ok, temporal_scan_limits()} |
    {error, temporal_scan_error()}.
temporal_scan_limits(Max_datoms) ->
    case Max_datoms > 0 of
        true ->
            {ok, {temporal_scan_limits, Max_datoms}};

        false ->
            {error, invalid_temporal_scan_limit}
    end.

-file("src/aarondb.gleam", 107).
-spec start_link(
    gleam@option:option(aarondb@storage:storage_adapter()),
    integer()
) -> {ok, gleam@erlang@process:subject(aarondb@transactor:message())} |
    {error, gleam@otp@actor:start_error()}.
start_link(Adapter, Timeout_ms) ->
    Store = case Adapter of
        {some, S} ->
            S;

        none ->
            aarondb@storage:ephemeral()
    end,
    aarondb@transactor:start_with_timeout(Store, Timeout_ms).

-file("src/aarondb.gleam", 99).
-spec new_with_adapter_and_timeout(
    gleam@option:option(aarondb@storage:storage_adapter()),
    integer()
) -> gleam@erlang@process:subject(aarondb@transactor:message()).
new_with_adapter_and_timeout(Adapter, Timeout_ms) ->
    Db@1 = case start_link(Adapter, Timeout_ms) of
        {ok, Db} -> Db;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb"/utf8>>,
                        function => <<"new_with_adapter_and_timeout"/utf8>>,
                        line => 103,
                        value => _assert_fail,
                        start => 2566,
                        'end' => 2617,
                        pattern_start => 2577,
                        pattern_end => 2583})
    end,
    Db@1.

-file("src/aarondb.gleam", 95).
-spec new_with_adapter(gleam@option:option(aarondb@storage:storage_adapter())) -> gleam@erlang@process:subject(aarondb@transactor:message()).
new_with_adapter(Adapter) ->
    new_with_adapter_and_timeout(Adapter, 5000).

-file("src/aarondb.gleam", 91).
?DOC(
    " **Compatibility constructor.** This convenience API returns a `Db` directly\n"
    " and therefore cannot report actor startup failures. New integrations should\n"
    " call `start_link/2` and handle its `Result` instead.\n"
).
-spec new() -> gleam@erlang@process:subject(aarondb@transactor:message()).
new() ->
    new_with_adapter(none).

-file("src/aarondb.gleam", 119).
-spec start_named(
    binary(),
    gleam@option:option(aarondb@storage:storage_adapter())
) -> {ok, gleam@erlang@process:subject(aarondb@transactor:message())} |
    {error, gleam@otp@actor:start_error()}.
start_named(Name, Adapter) ->
    Store = case Adapter of
        {some, S} ->
            S;

        none ->
            aarondb@storage:ephemeral()
    end,
    aarondb@transactor:start_named(Name, Store).

-file("src/aarondb.gleam", 130).
-spec start_distributed(
    binary(),
    gleam@option:option(aarondb@storage:storage_adapter())
) -> {ok, gleam@erlang@process:subject(aarondb@transactor:message())} |
    {error, gleam@otp@actor:start_error()}.
start_distributed(Name, Adapter) ->
    Store = case Adapter of
        {some, S} ->
            S;

        none ->
            aarondb@storage:ephemeral()
    end,
    aarondb@transactor:start_distributed(Name, Store).

-file("src/aarondb.gleam", 141).
-spec connect(binary()) -> {ok,
        gleam@erlang@process:subject(aarondb@transactor:message())} |
    {error, binary()}.
connect(Name) ->
    case aarondb_global_ffi:whereis(<<"aarondb_"/utf8, Name/binary>>) of
        {ok, Pid} ->
            {ok, aarondb_process_ffi:pid_to_subject(Pid)};

        {error, _} ->
            {error, <<"Could not find database named "/utf8, Name/binary>>}
    end.

-file("src/aarondb.gleam", 148).
-spec transact(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact(Db, Facts) ->
    aarondb@transactor:transact(Db, Facts).

-file("src/aarondb.gleam", 152).
-spec transact_at(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    integer()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact_at(Db, Facts, Valid_time) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Db, {transact, Facts, {some, Valid_time}, Reply}),
    case gleam@erlang@process:'receive'(Reply, 5000) of
        {ok, Res} ->
            Res;

        {error, _} ->
            {error, <<"Timeout"/utf8>>}
    end.

-file("src/aarondb.gleam", 165).
-spec transact_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    integer()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact_with_timeout(Db, Facts, Timeout_ms) ->
    aarondb@transactor:transact_with_timeout(Db, Facts, Timeout_ms).

-file("src/aarondb.gleam", 173).
-spec retract(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
retract(Db, Facts) ->
    aarondb@transactor:retract(Db, Facts).

-file("src/aarondb.gleam", 177).
-spec retract_at(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    integer()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
retract_at(Db, Facts, Valid_time) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Db, {retract, Facts, {some, Valid_time}, Reply}),
    case gleam@erlang@process:'receive'(Reply, 5000) of
        {ok, Res} ->
            Res;

        {error, _} ->
            {error, <<"Timeout"/utf8>>}
    end.

-file("src/aarondb.gleam", 190).
-spec prune(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    list(binary())
) -> integer().
prune(Db, Threshold, Sovereign) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Db, {prune, Threshold, Sovereign, Reply}),
    case gleam@erlang@process:'receive'(Reply, 5000) of
        {ok, Count} ->
            Count;

        {error, _} ->
            0
    end.

-file("src/aarondb.gleam", 199).
-spec trigger_eviction(
    gleam@erlang@process:subject(aarondb@transactor:message())
) -> {ok, nil} | {error, binary()}.
trigger_eviction(Db) ->
    gleam@erlang@process:send(Db, tick),
    {ok, nil}.

-file("src/aarondb.gleam", 204).
-spec retract_entity(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
retract_entity(Db, Eid) ->
    case Eid of
        {uid, Entity} ->
            Reply = gleam@erlang@process:new_subject(),
            gleam@erlang@process:send(Db, {retract_entity, Entity, Reply}),
            case gleam@erlang@process:'receive'(Reply, 5000) of
                {ok, Res} ->
                    Res;

                {error, _} ->
                    {error, <<"Timeout"/utf8>>}
            end;

        _ ->
            {error, <<"Only Uid supported for retract_entity"/utf8>>}
    end.

-file("src/aarondb.gleam", 218).
-spec with_facts(
    aarondb@shared@state:db_state(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, speculative_result()} | {error, binary()}.
with_facts(State, Facts) ->
    _pipe = aarondb@transactor@domain:compute_next_state(
        State,
        Facts,
        none,
        assert
    ),
    gleam@result:map(
        _pipe,
        fun(Res) ->
            {speculative_result, erlang:element(1, Res), erlang:element(2, Res)}
        end
    ).

-file("src/aarondb.gleam", 227).
?DOC(" Provides a human-readable explanation of a speculative result or failure.\n").
-spec explain_speculation({ok, speculative_result()} | {error, binary()}) -> binary().
explain_speculation(Res) ->
    case Res of
        {ok, S} ->
            <<<<"Speculation successful: "/utf8,
                    (erlang:integer_to_binary(
                        erlang:length(erlang:element(3, S))
                    ))/binary>>/binary,
                " datoms predicted."/utf8>>;

        {error, E} ->
            <<"Speculation failed: "/utf8, E/binary>>
    end.

-file("src/aarondb.gleam", 237).
-spec get(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid(),
    binary()
) -> list(aarondb@fact:value()).
get(Db, Eid, Attr) ->
    State = aarondb@transactor:get_state(Db),
    Id = case Eid of
        {uid, I} ->
            I;

        {lookup, {A, V}} ->
            _pipe = aarondb@index:get_entity_by_av(
                erlang:element(5, State),
                A,
                V
            ),
            gleam@result:unwrap(_pipe, {entity_id, 0})
    end,
    case erlang:element(14, State) of
        {some, Name} ->
            _pipe@1 = aarondb@index@ets:lookup_datoms(
                <<Name/binary, "_eavt"/utf8>>,
                Id
            ),
            _pipe@2 = gleam@list:filter(
                _pipe@1,
                fun(D) -> erlang:element(3, D) =:= Attr end
            ),
            gleam@list:map(_pipe@2, fun(D@1) -> erlang:element(4, D@1) end);

        none ->
            _pipe@3 = aarondb@index:get_datoms_by_entity_attr(
                erlang:element(3, State),
                Id,
                Attr
            ),
            gleam@list:map(_pipe@3, fun(D@2) -> erlang:element(4, D@2) end)
    end.

-file("src/aarondb.gleam", 259).
-spec get_one(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid(),
    binary()
) -> {ok, aarondb@fact:value()} | {error, nil}.
get_one(Db, Eid, Attr) ->
    _pipe = get(Db, Eid, Attr),
    gleam@list:first(_pipe).

-file("src/aarondb.gleam", 263).
-spec set_schema(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    aarondb@fact:attribute_config()
) -> {ok, nil} | {error, binary()}.
set_schema(Db, Attr, Config) ->
    aarondb@transactor:set_schema(Db, Attr, Config).

-file("src/aarondb.gleam", 271).
-spec set_schema_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    aarondb@fact:attribute_config(),
    integer()
) -> {ok, nil} | {error, binary()}.
set_schema_with_timeout(Db, Attr, Config, Timeout_ms) ->
    aarondb@transactor:set_schema_with_timeout(Db, Attr, Config, Timeout_ms).

-file("src/aarondb.gleam", 280).
-spec history(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid()
) -> list(aarondb@fact:datom()).
history(Db, Eid) ->
    State = aarondb@transactor:get_state(Db),
    Id = case Eid of
        {uid, I} ->
            I;

        {lookup, {A, V}} ->
            _pipe = aarondb@index:get_entity_by_av(
                erlang:element(5, State),
                A,
                V
            ),
            gleam@result:unwrap(_pipe, {entity_id, 0})
    end,
    case erlang:element(14, State) of
        {some, Name} ->
            aarondb@index@ets:lookup_datoms(<<Name/binary, "_eavt"/utf8>>, Id);

        none ->
            aarondb@index:get_datoms_by_entity(erlang:element(3, State), Id)
    end.

-file("src/aarondb.gleam", 295).
-spec extract_pull_attributes(list(aarondb@shared@ast:pull_item())) -> list(binary()).
extract_pull_attributes(Pattern) ->
    gleam@list:fold(Pattern, [], fun(Acc, P) -> case P of
                {attr, A} ->
                    [A | Acc];

                {nested, A@1, Inner} ->
                    [A@1 | lists:append(extract_pull_attributes(Inner), Acc)];

                _ ->
                    Acc
            end end).

-file("src/aarondb.gleam", 308).
-spec pull(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid(),
    list(aarondb@shared@ast:pull_item())
) -> aarondb@shared@query_types:pull_result().
pull(Db, Eid, Pattern) ->
    State = aarondb@transactor:get_state(Db),
    case erlang:element(4, erlang:element(24, State)) of
        true ->
            Attrs = extract_pull_attributes(Pattern),
            Ctx = {query_context, Attrs, [], 0},
            aarondb@transactor:log_query(Db, Ctx);

        false ->
            nil
    end,
    Id = case Eid of
        {uid, I} ->
            I;

        {lookup, {A, V}} ->
            _pipe = aarondb@index:get_entity_by_av(
                erlang:element(5, State),
                A,
                V
            ),
            gleam@result:unwrap(_pipe, {entity_id, 0})
    end,
    aarondb@engine:pull(State, Id, Pattern).

-file("src/aarondb.gleam", 333).
?DOC(
    " Returns all local datoms committed in `(from_tx, to_tx]`.\n"
    "\n"
    " This compatibility API has no scan budget and may return index-dependent\n"
    " order. Use `diff_bounded` for a typed, deterministically ordered result.\n"
).
-spec diff(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    integer()
) -> list(aarondb@fact:datom()).
diff(Db, From_tx, To_tx) ->
    State = aarondb@transactor:get_state(Db),
    aarondb@engine:diff(State, From_tx, To_tx).

-file("src/aarondb.gleam", 340).
?DOC(
    " Returns a complete, transaction-ordered diff for `(from_tx, to_tx]` or a\n"
    " typed error. The bounded API never returns a partial change set.\n"
).
-spec diff_bounded(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    integer(),
    diff_scan_limits()
) -> {ok, list(aarondb@fact:datom())} | {error, diff_scan_error()}.
diff_bounded(Db, From_tx, To_tx, Limits) ->
    case From_tx >= To_tx of
        true ->
            {error, invalid_diff_range};

        false ->
            {diff_scan_limits, Max_datoms} = Limits,
            State = aarondb@transactor:get_state(Db),
            case erlang:length(
                aarondb@index:get_all_datoms(erlang:element(3, State))
            )
            > Max_datoms of
                true ->
                    {error, diff_scan_budget_exceeded};

                false ->
                    {ok, aarondb@engine:diff_ordered(State, From_tx, To_tx)}
            end
    end.

-file("src/aarondb.gleam", 359).
-spec pull_all() -> list(aarondb@shared@ast:pull_item()).
pull_all() ->
    [wildcard].

-file("src/aarondb.gleam", 363).
-spec pull_attr(binary()) -> list(aarondb@shared@ast:pull_item()).
pull_attr(Attr) ->
    [{attr, Attr}].

-file("src/aarondb.gleam", 367).
-spec pull_except(list(binary())) -> list(aarondb@shared@ast:pull_item()).
pull_except(Exclusions) ->
    [{except, Exclusions}].

-file("src/aarondb.gleam", 371).
-spec pull_recursive(binary(), integer()) -> list(aarondb@shared@ast:pull_item()).
pull_recursive(Attr, Depth) ->
    [{pull_recursion, Attr, Depth}].

-file("src/aarondb.gleam", 375).
-spec 'query'(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
'query'(Db, Q_clauses) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, [], none, none).

-file("src/aarondb.gleam", 388).
-spec q(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@q:query_builder()
) -> aarondb@shared@query_types:query_result().
q(Db, Q_builder) ->
    State = aarondb@transactor:get_state(Db),
    Q = aarondb@q:to_query(Q_builder),
    aarondb@engine:run(State, Q, [], none, none).

-file("src/aarondb.gleam", 394).
-spec query_at(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list(aarondb@shared@ast:body_clause()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> aarondb@shared@query_types:query_result().
query_at(Db, Q_clauses, As_of_tx, As_of_valid) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(
        State,
        Q,
        erlang:element(21, State),
        As_of_tx,
        As_of_valid
    ).

-file("src/aarondb.gleam", 412).
-spec query_state(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
query_state(State, Q_clauses) ->
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, [], none, none).

-file("src/aarondb.gleam", 424).
-spec query_state_at(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:body_clause()),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> aarondb@shared@query_types:query_result().
query_state_at(State, Q_clauses, As_of_tx, As_of_valid) ->
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, [], As_of_tx, As_of_valid).

-file("src/aarondb.gleam", 441).
-spec execute(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@ast:'query'()
) -> aarondb@shared@query_types:query_result().
execute(Db, Query) ->
    State = aarondb@transactor:get_state(Db),
    aarondb@engine:run(State, Query, [], none, none).

-file("src/aarondb.gleam", 446).
-spec query_state_with_rules(
    aarondb@shared@state:db_state(),
    list(aarondb@shared@ast:body_clause()),
    list(aarondb@shared@ast:rule())
) -> aarondb@shared@query_types:query_result().
query_state_with_rules(State, Q_clauses, Rules) ->
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, Rules, none, none).

-file("src/aarondb.gleam", 462).
-spec query_with_rules(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list(aarondb@shared@ast:body_clause()),
    list(aarondb@shared@ast:rule())
) -> aarondb@shared@query_types:query_result().
query_with_rules(Db, Q_clauses, Rules) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, Rules, none, none).

-file("src/aarondb.gleam", 479).
-spec as_of(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
as_of(Db, Tx, Q_clauses) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(State, Q, erlang:element(21, State), {some, Tx}, none).

-file("src/aarondb.gleam", 492).
-spec as_of_valid(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
as_of_valid(Db, Valid_time, Q_clauses) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(
        State,
        Q,
        erlang:element(21, State),
        none,
        {some, Valid_time}
    ).

-file("src/aarondb.gleam", 509).
-spec as_of_bounded(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    list(aarondb@shared@ast:body_clause()),
    temporal_scan_limits()
) -> {ok, aarondb@shared@query_types:query_result()} |
    {error, temporal_scan_error()}.
as_of_bounded(Db, Tx, Q_clauses, Limits) ->
    {temporal_scan_limits, Max_datoms} = Limits,
    State = aarondb@transactor:get_state(Db),
    case erlang:length(aarondb@index:get_all_datoms(erlang:element(3, State))) > Max_datoms of
        true ->
            {error, temporal_scan_budget_exceeded};

        false ->
            {ok, as_of(Db, Tx, Q_clauses)}
    end.

-file("src/aarondb.gleam", 524).
?DOC(" Runs a valid-time snapshot after checking the local history scan budget.\n").
-spec as_of_valid_bounded(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    list(aarondb@shared@ast:body_clause()),
    temporal_scan_limits()
) -> {ok, aarondb@shared@query_types:query_result()} |
    {error, temporal_scan_error()}.
as_of_valid_bounded(Db, Valid_time, Q_clauses, Limits) ->
    {temporal_scan_limits, Max_datoms} = Limits,
    State = aarondb@transactor:get_state(Db),
    case erlang:length(aarondb@index:get_all_datoms(erlang:element(3, State))) > Max_datoms of
        true ->
            {error, temporal_scan_budget_exceeded};

        false ->
            {ok, as_of_valid(Db, Valid_time, Q_clauses)}
    end.

-file("src/aarondb.gleam", 554).
-spec as_of_bitemporal(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    integer(),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
as_of_bitemporal(Db, Tx, Valid_time, Q_clauses) ->
    State = aarondb@transactor:get_state(Db),
    Q = {'query', [], Q_clauses, none, none, none},
    aarondb@engine:run(
        State,
        Q,
        erlang:element(21, State),
        {some, Tx},
        {some, Valid_time}
    ).

-file("src/aarondb.gleam", 539).
?DOC(" Runs a bitemporal snapshot after checking the local history scan budget.\n").
-spec as_of_bitemporal_bounded(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    integer(),
    list(aarondb@shared@ast:body_clause()),
    temporal_scan_limits()
) -> {ok, aarondb@shared@query_types:query_result()} |
    {error, temporal_scan_error()}.
as_of_bitemporal_bounded(Db, Tx, Valid_time, Q_clauses, Limits) ->
    {temporal_scan_limits, Max_datoms} = Limits,
    State = aarondb@transactor:get_state(Db),
    case erlang:length(aarondb@index:get_all_datoms(erlang:element(3, State))) > Max_datoms of
        true ->
            {error, temporal_scan_budget_exceeded};

        false ->
            {ok, as_of_bitemporal(Db, Tx, Valid_time, Q_clauses)}
    end.

-file("src/aarondb.gleam", 572).
-spec p({aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()}) -> aarondb@shared@ast:body_clause().
p(Triple) ->
    {positive, Triple}.

-file("src/aarondb.gleam", 576).
-spec register_function(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()}))
) -> nil.
register_function(Db, Name, Func) ->
    aarondb@transactor:register_function(Db, Name, Func).

-file("src/aarondb.gleam", 584).
-spec register_function_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()})),
    integer()
) -> {ok, nil} | {error, binary()}.
register_function_with_timeout(Db, Name, Func, Timeout_ms) ->
    aarondb@transactor:register_function_with_timeout(
        Db,
        Name,
        Func,
        Timeout_ms
    ).

-file("src/aarondb.gleam", 593).
-spec register_composite(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list(binary())
) -> {ok, nil} | {error, binary()}.
register_composite(Db, Attrs) ->
    aarondb@transactor:register_composite(Db, Attrs).

-file("src/aarondb.gleam", 597).
-spec register_composite_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    list(binary()),
    integer()
) -> {ok, nil} | {error, binary()}.
register_composite_with_timeout(Db, Attrs, Timeout_ms) ->
    aarondb@transactor:register_composite_with_timeout(Db, Attrs, Timeout_ms).

-file("src/aarondb.gleam", 607).
?DOC(
    " **Compatibility registration helper.** This function cannot surface an\n"
    " actor timeout. New integrations should use `register_predicate_with_timeout/4`.\n"
).
-spec register_predicate(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    fun((aarondb@fact:value()) -> boolean())
) -> nil.
register_predicate(Db, Name, Pred) ->
    aarondb@transactor:register_predicate(Db, Name, Pred).

-file("src/aarondb.gleam", 615).
-spec register_predicate_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    fun((aarondb@fact:value()) -> boolean()),
    integer()
) -> {ok, nil} | {error, binary()}.
register_predicate_with_timeout(Db, Name, Pred, Timeout_ms) ->
    aarondb@transactor:register_predicate_with_timeout(
        Db,
        Name,
        Pred,
        Timeout_ms
    ).

-file("src/aarondb.gleam", 624).
-spec store_rule(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@ast:rule()
) -> {ok, nil} | {error, binary()}.
store_rule(Db, Rule) ->
    aarondb@transactor:store_rule(Db, Rule).

-file("src/aarondb.gleam", 628).
-spec store_rule_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@ast:rule(),
    integer()
) -> {ok, nil} | {error, binary()}.
store_rule_with_timeout(Db, Rule, Timeout_ms) ->
    aarondb@transactor:store_rule_with_timeout(Db, Rule, Timeout_ms).

-file("src/aarondb.gleam", 636).
-spec set_config(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@state:config()
) -> nil.
set_config(Db, Config) ->
    aarondb@transactor:set_config(Db, Config).

-file("src/aarondb.gleam", 640).
-spec set_config_with_timeout(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@state:config(),
    integer()
) -> {ok, nil} | {error, binary()}.
set_config_with_timeout(Db, Config, Timeout_ms) ->
    aarondb@transactor:set_config_with_timeout(Db, Config, Timeout_ms).

-file("src/aarondb.gleam", 654).
?DOC(
    " Subscribe to local reactive query updates.\n"
    "\n"
    " The initial result and later deltas are emitted by the reactive actor in mailbox\n"
    " order. Delivery is unbounded BEAM mailbox delivery: it does not block writers or\n"
    " drop updates, so callers must drain their own mailbox. Call `unsubscribe` when\n"
    " finished; stopped subscribers are also removed on the next notification.\n"
).
-spec subscribe(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@shared@ast:'query'(),
    gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta())
) -> nil.
subscribe(Db, Query, Subscriber) ->
    Current_state = aarondb@transactor:get_state(Db),
    Results = aarondb@engine:run(Current_state, Query, [], none, none),
    Attrs = gleam@list:filter_map(erlang:element(3, Query), fun(C) -> case C of
                {positive, {_, A, _}} ->
                    {ok, A};

                {negative, {_, A@1, _}} ->
                    {ok, A@1};

                _ ->
                    {error, nil}
            end end),
    Msg = {subscribe, Query, Attrs, Subscriber, Results},
    gleam@erlang@process:send(erlang:element(11, Current_state), Msg),
    nil.

-file("src/aarondb.gleam", 681).
?DOC(
    " Stop local reactive updates for a subscriber.\n"
    "\n"
    " Unsubscription is ordered with notifications received by the reactive actor:\n"
    " deltas already sent to the subscriber remain in its mailbox, while later actor\n"
    " notifications do not produce new deltas for it.\n"
).
-spec unsubscribe(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta())
) -> nil.
unsubscribe(Db, Subscriber) ->
    Current_state = aarondb@transactor:get_state(Db),
    gleam@erlang@process:send(
        erlang:element(11, Current_state),
        {unsubscribe, Subscriber}
    ),
    nil.

-file("src/aarondb.gleam", 690).
-spec subscribe_wal(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@erlang@process:subject(list(aarondb@fact:datom()))
) -> nil.
subscribe_wal(Db, Subscriber) ->
    gleam@erlang@process:send(Db, {subscribe, Subscriber}).

-file("src/aarondb.gleam", 694).
-spec get_state(gleam@erlang@process:subject(aarondb@transactor:message())) -> aarondb@shared@state:db_state().
get_state(Db) ->
    aarondb@transactor:get_state(Db).

-file("src/aarondb.gleam", 698).
-spec sync(gleam@erlang@process:subject(aarondb@transactor:message())) -> nil.
sync(Db) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Db, {sync, Reply}),
    _ = gleam@erlang@process:'receive'(Reply, 5000),
    nil.

-file("src/aarondb.gleam", 705).
-spec traverse(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    aarondb@fact:eid(),
    list(aarondb@shared@ast:step()),
    integer()
) -> {ok, list(aarondb@fact:value())} | {error, binary()}.
traverse(Db, Eid, Path, Max_depth) ->
    State = aarondb@transactor:get_state(Db),
    Id = case Eid of
        {uid, {entity_id, I}} ->
            I;

        {lookup, {A, V}} ->
            _pipe = aarondb@index:get_entity_by_av(
                erlang:element(5, State),
                A,
                V
            ),
            _pipe@1 = gleam@result:unwrap(_pipe, {entity_id, 0}),
            aarondb@fact:eid_to_integer(_pipe@1)
    end,
    Engine_path = gleam@list:map(Path, fun(S) -> case S of
                {in, A@1} ->
                    {in, A@1};

                {out, A@2} ->
                    {out, A@2}
            end end),
    aarondb@engine:traverse(State, Id, Engine_path, Max_depth).
