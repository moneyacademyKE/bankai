-module(vector_hnsw_benchmark).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/vector_hnsw_benchmark.gleam").
-export([main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/vector_hnsw_benchmark.gleam", 70).
-spec vector_for(integer()) -> list(float()).
vector_for(Id) ->
    [erlang:float((Id rem 97) + 1),
        erlang:float(((Id * 7) rem 89) + 1),
        erlang:float(((Id * 11) rem 83) + 1),
        erlang:float(((Id * 13) rem 79) + 1),
        erlang:float(((Id * 17) rem 73) + 1),
        erlang:float(((Id * 19) rem 71) + 1),
        erlang:float(((Id * 23) rem 67) + 1),
        erlang:float(((Id * 29) rem 61) + 1)].

-file("src/vector_hnsw_benchmark.gleam", 83).
-spec recall_at_ten(aarondb@vec_index:vec_index(), list(integer())) -> binary().
recall_at_ten(Index, Query_ids) ->
    Matching_results = gleam@list:fold(
        Query_ids,
        0,
        fun(Matches, Id) ->
            Query = vector_for(Id * 7),
            Approximate = aarondb@vec_index:search(Index, Query, -1.0, 10),
            Exact@1 = case aarondb@vec_index:exact_search(
                Index,
                Query,
                -1.0,
                10
            ) of
                {ok, Exact} -> Exact;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"vector_hnsw_benchmark"/utf8>>,
                                function => <<"recall_at_ten"/utf8>>,
                                line => 88,
                                value => _assert_fail,
                                start => 2630,
                                'end' => 2699,
                                pattern_start => 2641,
                                pattern_end => 2650})
            end,
            Expected = gleam@list:map(
                Exact@1,
                fun(Item) -> erlang:element(2, Item) end
            ),
            Found = gleam@list:map(
                Approximate,
                fun(Item@1) -> erlang:element(2, Item@1) end
            ),
            Matches + erlang:length(
                gleam@list:filter(
                    Expected,
                    fun(Entity) -> gleam@list:contains(Found, Entity) end
                )
            )
        end
    ),
    case Matching_results =:= (erlang:length(Query_ids) * 10) of
        true ->
            <<"1.00"/utf8>>;

        false ->
            <<"<1.00"/utf8>>
    end.

-file("src/vector_hnsw_benchmark.gleam", 119).
-spec percentile_index(integer(), integer()) -> integer().
percentile_index(Count, Percentile) ->
    Percentage = (Count * Percentile) div 100,
    gleam@int:max(0, Percentage - 1).

-file("src/vector_hnsw_benchmark.gleam", 102).
-spec print_latency(binary(), list(integer())) -> nil.
print_latency(Label, Samples) ->
    Sorted = gleam@list:sort(Samples, fun gleam@int:compare/2),
    Count = erlang:length(Sorted),
    Total = gleam@list:fold(Samples, 0, fun(Sum, Sample) -> Sum + Sample end),
    P50@1 = case begin
        _pipe = gleam@list:drop(Sorted, percentile_index(Count, 50)),
        gleam@list:first(_pipe)
    end of
        {ok, P50} -> P50;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"vector_hnsw_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 106,
                        value => _assert_fail,
                        start => 3266,
                        'end' => 3353,
                        pattern_start => 3277,
                        pattern_end => 3284})
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
                        module => <<"vector_hnsw_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 108,
                        value => _assert_fail@1,
                        start => 3356,
                        'end' => 3443,
                        pattern_start => 3367,
                        pattern_end => 3374})
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

-file("src/vector_hnsw_benchmark.gleam", 115).
-spec nanoseconds_to_milliseconds(integer()) -> integer().
nanoseconds_to_milliseconds(Value) ->
    Value div 1000000.

-file("src/vector_hnsw_benchmark.gleam", 63).
-spec insert_point(
    aarondb@vec_index:vec_index(),
    {aarondb@fact:entity_id(), list(float())}
) -> aarondb@vec_index:vec_index().
insert_point(Index, Point) ->
    aarondb@vec_index:insert(
        Index,
        erlang:element(1, Point),
        erlang:element(2, Point)
    ).

-file("src/vector_hnsw_benchmark.gleam", 55).
-spec corpus(integer()) -> list({aarondb@fact:entity_id(), list(float())}).
corpus(Size) ->
    _pipe = gleam@list:repeat(nil, Size),
    gleam@list:index_map(
        _pipe,
        fun(_, Offset) ->
            Id = Offset + 1,
            {{entity_id, Id}, vector_for(Id)}
        end
    ).

-file("src/vector_hnsw_benchmark.gleam", 11).
?DOC(
    " Reproducible local evidence harness for the in-memory HNSW index.\n"
    "\n"
    " Run with `gleam run -m vector_hnsw_benchmark`. It reports a machine-local\n"
    " sample rather than claiming a portable latency SLA.\n"
).
-spec main() -> nil.
main() ->
    Corpus_size = 1000,
    Query_count = 100,
    Corpus = corpus(Corpus_size),
    Start_build = erlang:system_time(),
    Index = gleam@list:fold(
        Corpus,
        aarondb@vec_index:new_with_config(
            {hnsw_config, 32, 1000, {deterministic_levels, []}}
        ),
        fun insert_point/2
    ),
    Build_ns = erlang:system_time() - Start_build,
    Query_ids = begin
        _pipe = gleam@list:repeat(nil, Query_count),
        gleam@list:index_map(_pipe, fun(_, Offset) -> Offset + 1 end)
    end,
    Hnsw_times = gleam@list:map(
        Query_ids,
        fun(Id) ->
            Start = erlang:system_time(),
            _ = aarondb@vec_index:search(Index, vector_for(Id * 7), -1.0, 10),
            nanoseconds_to_milliseconds(erlang:system_time() - Start)
        end
    ),
    Exact_times = gleam@list:map(
        Query_ids,
        fun(Id@1) ->
            Start@1 = erlang:system_time(),
            case aarondb@vec_index:exact_search(
                Index,
                vector_for(Id@1 * 7),
                -1.0,
                10
            ) of
                {ok, _} -> nil;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"vector_hnsw_benchmark"/utf8>>,
                                function => <<"main"/utf8>>,
                                line => 39,
                                value => _assert_fail,
                                start => 1101,
                                'end' => 1187,
                                pattern_start => 1112,
                                pattern_end => 1117})
            end,
            nanoseconds_to_milliseconds(erlang:system_time() - Start@1)
        end
    ),
    gleam_stdlib:println(
        <<"corpus_size="/utf8, (erlang:integer_to_binary(Corpus_size))/binary>>
    ),
    gleam_stdlib:println(<<"dimensions=8"/utf8>>),
    gleam_stdlib:println(
        <<"query_count="/utf8, (erlang:integer_to_binary(Query_count))/binary>>
    ),
    gleam_stdlib:println(
        <<"build_ms="/utf8,
            (erlang:integer_to_binary(nanoseconds_to_milliseconds(Build_ns)))/binary>>
    ),
    print_latency(<<"hnsw"/utf8>>, Hnsw_times),
    print_latency(<<"exact"/utf8>>, Exact_times),
    gleam_stdlib:println(
        <<"recall_at_10="/utf8, (recall_at_ten(Index, Query_ids))/binary>>
    ).
