-module(temporal_diff_benchmark).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/temporal_diff_benchmark.gleam").
-export([main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/temporal_diff_benchmark.gleam", 98).
-spec percentile_index(integer(), integer()) -> integer().
percentile_index(Count, Percentile) ->
    Percentage = (Count * Percentile) div 100,
    gleam@int:max(0, Percentage - 1).

-file("src/temporal_diff_benchmark.gleam", 85).
-spec print_latency(binary(), list(integer())) -> nil.
print_latency(Label, Samples) ->
    Sorted = gleam@list:sort(Samples, fun gleam@int:compare/2),
    Count = erlang:length(Sorted),
    Total = gleam@list:fold(Samples, 0, fun(Sum, Value) -> Sum + Value end),
    P50@1 = case begin
        _pipe = gleam@list:drop(Sorted, percentile_index(Count, 50)),
        gleam@list:first(_pipe)
    end of
        {ok, P50} -> P50;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"temporal_diff_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 89,
                        value => _assert_fail,
                        start => 2602,
                        'end' => 2689,
                        pattern_start => 2613,
                        pattern_end => 2620})
    end,
    P95@1 = case begin
        _pipe@1 = gleam@list:drop(Sorted, percentile_index(Count, 95)),
        gleam@list:first(_pipe@1)
    end of
        {ok, P95} -> P95;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"temporal_diff_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 91,
                        value => _assert_fail@1,
                        start => 2692,
                        'end' => 2779,
                        pattern_start => 2703,
                        pattern_end => 2710})
    end,
    gleam_stdlib:println(
        <<<<Label/binary, "_total_ms="/utf8>>/binary,
            (erlang:integer_to_binary(Total))/binary>>
    ),
    gleam_stdlib:println(
        <<<<Label/binary, "_p50_ms="/utf8>>/binary,
            (erlang:integer_to_binary(P50@1))/binary>>
    ),
    gleam_stdlib:println(
        <<<<Label/binary, "_p95_ms="/utf8>>/binary,
            (erlang:integer_to_binary(P95@1))/binary>>
    ).

-file("src/temporal_diff_benchmark.gleam", 103).
-spec nanoseconds_to_milliseconds(integer()) -> integer().
nanoseconds_to_milliseconds(Value) ->
    Value div 1000000.

-file("src/temporal_diff_benchmark.gleam", 81).
-spec samples(integer(), fun((nil) -> integer())) -> list(integer()).
samples(Count, Sample) ->
    _pipe = gleam@list:repeat(nil, Count),
    gleam@list:map(_pipe, Sample).

-file("src/temporal_diff_benchmark.gleam", 13).
?DOC(
    " Reproducible local temporal-query and diff evidence harness.\n"
    "\n"
    " Run with `gleam run -m temporal_diff_benchmark`. It measures one in-memory\n"
    " actor in one BEAM process. Results are regression evidence only, not a\n"
    " portable latency, retention, or capacity guarantee.\n"
).
-spec main() -> nil.
main() ->
    Db = aarondb:new(),
    Transaction_count = 250,
    Entity_count = 25,
    Setup_start = erlang:system_time(),
    First_state@1 = case aarondb:transact(
        Db,
        [{{uid, {entity_id, 1}}, <<"event/value"/utf8>>, {int, 1}}]
    ) of
        {ok, First_state} -> First_state;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"temporal_diff_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 18,
                        value => _assert_fail,
                        start => 515,
                        'end' => 642,
                        pattern_start => 526,
                        pattern_end => 541})
    end,
    Last_state = gleam@int:range(
        2,
        Transaction_count,
        First_state@1,
        fun(_, Tx) ->
            Entity_id = case case Entity_count of
                0 -> 0;
                Gleam@denominator -> Tx rem Gleam@denominator
            end of
                0 ->
                    Entity_count;

                Remainder ->
                    Remainder
            end,
            Entity = {uid, {entity_id, Entity_id}},
            Next@1 = case aarondb:transact(
                Db,
                [{Entity, <<"event/value"/utf8>>, {int, Tx}}]
            ) of
                {ok, Next} -> Next;
                _assert_fail@1 ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"temporal_diff_benchmark"/utf8>>,
                                function => <<"main"/utf8>>,
                                line => 33,
                                value => _assert_fail@1,
                                start => 958,
                                'end' => 1052,
                                pattern_start => 969,
                                pattern_end => 977})
            end,
            Next@1
        end
    ),
    Setup_ns = erlang:system_time() - Setup_start,
    Temporal_limits@1 = case aarondb:temporal_scan_limits(
        Transaction_count + 10
    ) of
        {ok, Temporal_limits} -> Temporal_limits;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"temporal_diff_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 40,
                        value => _assert_fail@2,
                        start => 1121,
                        'end' => 1210,
                        pattern_start => 1132,
                        pattern_end => 1151})
    end,
    Diff_limits@1 = case aarondb:diff_scan_limits(Transaction_count + 10) of
        {ok, Diff_limits} -> Diff_limits;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"temporal_diff_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 42,
                        value => _assert_fail@3,
                        start => 1213,
                        'end' => 1290,
                        pattern_start => 1224,
                        pattern_end => 1239})
    end,
    Clause = aarondb:p(
        {{var, <<"entity"/utf8>>},
            <<"event/value"/utf8>>,
            {var, <<"value"/utf8>>}}
    ),
    Temporal_times = samples(
        100,
        fun(_) ->
            Start = erlang:system_time(),
            _ = aarondb:as_of_bounded(
                Db,
                erlang:element(6, Last_state),
                [Clause],
                Temporal_limits@1
            ),
            nanoseconds_to_milliseconds(erlang:system_time() - Start)
        end
    ),
    Diff_times = samples(
        100,
        fun(_) ->
            Start@1 = erlang:system_time(),
            _ = aarondb:diff_bounded(
                Db,
                erlang:element(6, First_state@1),
                erlang:element(6, Last_state),
                Diff_limits@1
            ),
            nanoseconds_to_milliseconds(erlang:system_time() - Start@1)
        end
    ),
    gleam_stdlib:println(
        <<"transaction_count="/utf8,
            (erlang:integer_to_binary(Transaction_count))/binary>>
    ),
    gleam_stdlib:println(
        <<"entity_count="/utf8,
            (erlang:integer_to_binary(Entity_count))/binary>>
    ),
    gleam_stdlib:println(<<"sample_count=100"/utf8>>),
    gleam_stdlib:println(
        <<"setup_ms="/utf8,
            (erlang:integer_to_binary(nanoseconds_to_milliseconds(Setup_ns)))/binary>>
    ),
    print_latency(<<"temporal_snapshot"/utf8>>, Temporal_times),
    print_latency(<<"bounded_diff"/utf8>>, Diff_times).
