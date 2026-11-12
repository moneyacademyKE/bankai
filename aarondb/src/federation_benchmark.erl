-module(federation_benchmark).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/federation_benchmark.gleam").
-export([main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/federation_benchmark.gleam", 83).
-spec nanoseconds_to_milliseconds(integer()) -> integer().
nanoseconds_to_milliseconds(Value) ->
    Value div 1000000.

-file("src/federation_benchmark.gleam", 55).
-spec run_reads(
    aarondb@federation:federation(),
    aarondb@shared@ast:'query'(),
    integer()
) -> {ok, aarondb@federation:federated_result()} |
    {error, aarondb@federation:federation_error()}.
run_reads(Federation, Query, Count) ->
    gleam@int:range(
        1,
        Count,
        aarondb@federation:'query'(Federation, Query),
        fun(Result, _) -> case Result of
                {ok, _} ->
                    aarondb@federation:'query'(Federation, Query);

                {error, Error} ->
                    {error, Error}
            end end
    ).

-file("src/federation_benchmark.gleam", 73).
-spec people_query() -> aarondb@shared@ast:'query'().
people_query() ->
    {'query',
        [<<"name"/utf8>>],
        [{positive,
                {{var, <<"e"/utf8>>},
                    <<"person/name"/utf8>>,
                    {var, <<"name"/utf8>>}}}],
        none,
        none,
        none}.

-file("src/federation_benchmark.gleam", 39).
-spec seed(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    integer(),
    integer(),
    binary()
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
seed(Db, Start, Count, Prefix) ->
    Facts = gleam@int:range(
        Start,
        (Start + Count) - 1,
        [],
        fun(Acc, Id) ->
            [{{uid, {entity_id, Id}},
                    <<"person/name"/utf8>>,
                    {str,
                        <<Prefix/binary, (erlang:integer_to_binary(Id))/binary>>}} |
                Acc]
        end
    ),
    aarondb:transact(Db, Facts).

-file("src/federation_benchmark.gleam", 15).
?DOC(
    " Reproducible local federation evidence harness.\n"
    "\n"
    " Run with `gleam run -m federation_benchmark`. It creates two local actors,\n"
    " inserts deterministic data, and measures repeated fail-fast reads. The\n"
    " result is machine-local evidence, not a remote or HA performance claim.\n"
).
-spec main() -> nil.
main() ->
    Alpha = aarondb:new(),
    Beta = aarondb:new(),
    case seed(Alpha, 1, 500, <<"alpha"/utf8>>) of
        {ok, _} -> nil;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"federation_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 18,
                        value => _assert_fail,
                        start => 546,
                        'end' => 593,
                        pattern_start => 557,
                        pattern_end => 562})
    end,
    case seed(Beta, 10001, 500, <<"beta"/utf8>>) of
        {ok, _} -> nil;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"federation_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 19,
                        value => _assert_fail@1,
                        start => 596,
                        'end' => 646,
                        pattern_start => 607,
                        pattern_end => 612})
    end,
    Federation@1 = case aarondb@federation:new(
        [{source, <<"beta"/utf8>>, Beta}, {source, <<"alpha"/utf8>>, Alpha}]
    ) of
        {ok, Federation} -> Federation;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"federation_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 20,
                        value => _assert_fail@2,
                        start => 649,
                        'end' => 784,
                        pattern_start => 660,
                        pattern_end => 674})
    end,
    Query = people_query(),
    Start = erlang:system_time(),
    Result = run_reads(Federation@1, Query, 100),
    Elapsed = erlang:system_time() - Start,
    Rows@1 = case Result of
        {ok, {federated_result, Rows, _}} -> Rows;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"federation_benchmark"/utf8>>,
                        function => <<"main"/utf8>>,
                        line => 30,
                        value => _assert_fail@3,
                        start => 916,
                        'end' => 977,
                        pattern_start => 927,
                        pattern_end => 968})
    end,
    gleam_stdlib:println(
        <<<<<<"sources=2 rows="/utf8,
                    (erlang:integer_to_binary(erlang:length(Rows@1)))/binary>>/binary,
                " reads=100 total_ms="/utf8>>/binary,
            (erlang:integer_to_binary(nanoseconds_to_milliseconds(Elapsed)))/binary>>
    ).
