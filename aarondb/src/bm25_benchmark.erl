-module(bm25_benchmark).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bm25_benchmark.gleam").
-export([main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/bm25_benchmark.gleam", 80).
-spec percentile_index(integer(), integer()) -> integer().
percentile_index(Count, Percentile) ->
    Percentage = (Count * Percentile) div 100,
    gleam@int:max(0, Percentage - 1).

-file("src/bm25_benchmark.gleam", 63).
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
                        module => <<"bm25_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 67,
                        value => _assert_fail,
                        start => 2043,
                        'end' => 2130,
                        pattern_start => 2054,
                        pattern_end => 2061})
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
                        module => <<"bm25_benchmark"/utf8>>,
                        function => <<"print_latency"/utf8>>,
                        line => 69,
                        value => _assert_fail@1,
                        start => 2133,
                        'end' => 2220,
                        pattern_start => 2144,
                        pattern_end => 2151})
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

-file("src/bm25_benchmark.gleam", 76).
-spec nanoseconds_to_milliseconds(integer()) -> integer().
nanoseconds_to_milliseconds(Value) ->
    Value div 1000000.

-file("src/bm25_benchmark.gleam", 52).
-spec documents(integer()) -> list({aarondb@fact:entity_id(), binary()}).
documents(Count) ->
    _pipe = gleam@list:repeat(nil, Count),
    gleam@list:index_map(
        _pipe,
        fun(_, Offset) ->
            Id = Offset + 1,
            {{entity_id, Id},
                <<"gleam database retrieval document "/utf8,
                    (erlang:integer_to_binary(Id))/binary>>}
        end
    ).

-file("src/bm25_benchmark.gleam", 12).
?DOC(
    " Reproducible local evidence harness for the caller-owned BM25 primitive.\n"
    "\n"
    " Run with `gleam run -m bm25_benchmark`. This measures one BEAM process,\n"
    " one immutable in-memory index, and sequential operations. It does not\n"
    " claim persistence, transaction integration, or concurrent mutation safety.\n"
).
-spec main() -> nil.
main() ->
    Document_count = 1000,
    Query_count = 100,
    Documents = documents(Document_count),
    Build_start = erlang:system_time(),
    Index@1 = gleam@list:fold(
        Documents,
        aarondb@index@bm25:empty(<<"body"/utf8>>),
        fun(Index, Document) ->
            {Entity, Text} = Document,
            aarondb@index@bm25:add(Index, Entity, Text)
        end
    ),
    Build_ns = erlang:system_time() - Build_start,
    Query_times = begin
        _pipe = gleam@list:repeat(nil, Query_count),
        gleam@list:map(
            _pipe,
            fun(_) ->
                Start = erlang:system_time(),
                _ = aarondb@index@bm25:search(
                    Index@1,
                    <<"gleam database retrieval"/utf8>>,
                    1.2,
                    0.75,
                    10
                ),
                nanoseconds_to_milliseconds(erlang:system_time() - Start)
            end
        )
    end,
    Update_start = erlang:system_time(),
    _ = gleam@list:fold(
        Documents,
        Index@1,
        fun(Current, Document@1) ->
            {Entity@1, _} = Document@1,
            aarondb@index@bm25:add(
                Current,
                Entity@1,
                <<"gleam updated document retrieval"/utf8>>
            )
        end
    ),
    Update_ns = erlang:system_time() - Update_start,
    gleam_stdlib:println(
        <<"document_count="/utf8,
            (erlang:integer_to_binary(Document_count))/binary>>
    ),
    gleam_stdlib:println(
        <<"query_count="/utf8, (erlang:integer_to_binary(Query_count))/binary>>
    ),
    gleam_stdlib:println(
        <<"build_ms="/utf8,
            (erlang:integer_to_binary(nanoseconds_to_milliseconds(Build_ns)))/binary>>
    ),
    gleam_stdlib:println(
        <<"replace_all_ms="/utf8,
            (erlang:integer_to_binary(nanoseconds_to_milliseconds(Update_ns)))/binary>>
    ),
    print_latency(<<"search"/utf8>>, Query_times).
