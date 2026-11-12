-module(graph_benchmark).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/graph_benchmark.gleam").
-export([main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/graph_benchmark.gleam", 138).
-spec nanoseconds_to_milliseconds(integer()) -> integer().
nanoseconds_to_milliseconds(Value) ->
    Value div 1000000.

-file("src/graph_benchmark.gleam", 84).
-spec graph_state(list({integer(), integer()})) -> aarondb@shared@state:db_state().
graph_state(Edges) ->
    Facts = gleam@list:map(
        Edges,
        fun(Edge) ->
            {datom,
                {entity_id, erlang:element(1, Edge)},
                <<"edge"/utf8>>,
                {ref, {entity_id, erlang:element(2, Edge)}},
                1,
                0,
                0,
                assert}
        end
    ),
    Eavt = gleam@list:fold(
        Facts,
        maps:new(),
        fun(Index, Datom) -> aarondb@index:insert_eavt(Index, Datom, all) end
    ),
    Aevt = gleam@list:fold(
        Facts,
        maps:new(),
        fun(Index@1, Datom@1) ->
            aarondb@index:insert_aevt(Index@1, Datom@1, all)
        end
    ),
    {db_state,
        aarondb@storage:ephemeral(),
        Eavt,
        Aevt,
        maps:new(),
        0,
        [],
        maps:new(),
        maps:new(),
        [],
        gleam@erlang@process:new_subject(),
        [],
        false,
        none,
        aarondb@vec_index:new(),
        maps:new(),
        aarondb@index@art:new(),
        maps:new(),
        maps:new(),
        maps:new(),
        [],
        maps:new(),
        maps:new(),
        {config, 500, 100, false, 10000},
        []}.

-file("src/graph_benchmark.gleam", 78).
-spec hub_edges(integer()) -> list({integer(), integer()}).
hub_edges(Size) ->
    gleam@int:range(
        2,
        Size,
        [],
        fun(Edges, Target) -> [{1, Target} | Edges] end
    ).

-file("src/graph_benchmark.gleam", 72).
-spec chain_edges(integer()) -> list({integer(), integer()}).
chain_edges(Size) ->
    gleam@int:range(
        1,
        Size - 1,
        [],
        fun(Edges, Source) -> [{Source, Source + 1} | Edges] end
    ).

-file("src/graph_benchmark.gleam", 68).
-spec disconnected_edges() -> list({integer(), integer()}).
disconnected_edges() ->
    [{1, 2}, {3, 4}, {5, 6}].

-file("src/graph_benchmark.gleam", 64).
-spec cyclic_edges() -> list({integer(), integer()}).
cyclic_edges() ->
    [{1, 2}, {2, 3}, {3, 1}, {3, 4}].

-file("src/graph_benchmark.gleam", 53).
-spec dense_edges() -> list({integer(), integer()}).
dense_edges() ->
    gleam@list:flat_map(
        [1, 2, 3, 4, 5],
        fun(Source) ->
            gleam@list:filter_map(
                [1, 2, 3, 4, 5],
                fun(Target) -> case Source =:= Target of
                        true ->
                            {error, nil};

                        false ->
                            {ok, {Source, Target}}
                    end end
            )
        end
    ).

-file("src/graph_benchmark.gleam", 49).
-spec sparse_edges() -> list({integer(), integer()}).
sparse_edges() ->
    [{1, 2}, {2, 3}, {3, 4}, {4, 5}].

-file("src/graph_benchmark.gleam", 20).
?DOC(
    " Reproducible local graph-algorithm evidence harness.\n"
    "\n"
    " Run with `gleam run -m graph_benchmark`. It exercises representative sparse,\n"
    " dense, cyclic, disconnected, chain, and hub fixtures in one BEAM process.\n"
    " It reports machine-local samples only; it is not a portable latency SLA.\n"
).
-spec main() -> nil.
main() ->
    Fixtures = [{<<"sparse"/utf8>>, sparse_edges()},
        {<<"dense"/utf8>>, dense_edges()},
        {<<"cyclic"/utf8>>, cyclic_edges()},
        {<<"disconnected"/utf8>>, disconnected_edges()},
        {<<"chain"/utf8>>, chain_edges(100)},
        {<<"hub"/utf8>>, hub_edges(100)}],
    gleam@list:each(
        Fixtures,
        fun(Fixture) ->
            {Name, Edges} = Fixture,
            Db = graph_state(Edges),
            Start = erlang:system_time(),
            _ = aarondb@algo@graph:reachable(
                Db,
                {entity_id, 1},
                <<"edge"/utf8>>
            ),
            _ = aarondb@algo@graph:pagerank(Db, <<"edge"/utf8>>, 0.85, 20),
            _ = aarondb@algo@graph:cycle_detect(Db, <<"edge"/utf8>>),
            _ = aarondb@algo@graph:strongly_connected_components(
                Db,
                <<"edge"/utf8>>
            ),
            Elapsed = erlang:system_time() - Start,
            gleam_stdlib:println(
                <<<<<<<<Name/binary, "_edges="/utf8>>/binary,
                            (erlang:integer_to_binary(erlang:length(Edges)))/binary>>/binary,
                        " total_ms="/utf8>>/binary,
                    (erlang:integer_to_binary(
                        nanoseconds_to_milliseconds(Elapsed)
                    ))/binary>>
            )
        end
    ).
