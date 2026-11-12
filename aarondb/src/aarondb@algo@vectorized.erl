-module(aarondb@algo@vectorized).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/algo/vectorized.gleam").
-export([sum_column/1, chunks_to_datoms/1, count_node/1, avg_column/1]).

-file("src/aarondb/algo/vectorized.gleam", 36).
-spec sum_node(aarondb@storage@internal:cracking_node()) -> float().
sum_node(Node) ->
    case Node of
        {leaf, Values} ->
            gleam@list:fold(Values, +0.0, fun(Acc, V) -> case V of
                        {int, I} ->
                            Acc + erlang:float(I);

                        {float, F} ->
                            Acc + F;

                        _ ->
                            Acc
                    end end);

        {branch, _, Left, Right} ->
            sum_node(Left) + sum_node(Right)
    end.

-file("src/aarondb/algo/vectorized.gleam", 5).
-spec sum_column(aarondb@storage@internal:storage_chunk()) -> float().
sum_column(Chunk) ->
    sum_node(erlang:element(3, Chunk)).

-file("src/aarondb/algo/vectorized.gleam", 28).
-spec node_to_values(aarondb@storage@internal:cracking_node()) -> list(aarondb@fact:value()).
node_to_values(Node) ->
    case Node of
        {leaf, Vs} ->
            Vs;

        {branch, _, L, R} ->
            lists:append(node_to_values(L), node_to_values(R))
    end.

-file("src/aarondb/algo/vectorized.gleam", 9).
-spec chunks_to_datoms(list(aarondb@storage@internal:storage_chunk())) -> list(aarondb@fact:datom()).
chunks_to_datoms(Chunks) ->
    gleam@list:flat_map(
        Chunks,
        fun(Chunk) -> _pipe = node_to_values(erlang:element(3, Chunk)),
            gleam@list:map(
                _pipe,
                fun(V) ->
                    {datom,
                        {entity_id, 0},
                        erlang:element(2, Chunk),
                        V,
                        0,
                        0,
                        0,
                        assert}
                end
            ) end
    ).

-file("src/aarondb/algo/vectorized.gleam", 61).
-spec count_node(aarondb@storage@internal:cracking_node()) -> integer().
count_node(Node) ->
    case Node of
        {leaf, Values} ->
            erlang:length(Values);

        {branch, _, Left, Right} ->
            count_node(Left) + count_node(Right)
    end.

-file("src/aarondb/algo/vectorized.gleam", 53).
-spec avg_column(aarondb@storage@internal:storage_chunk()) -> float().
avg_column(Chunk) ->
    Len = count_node(erlang:element(3, Chunk)),
    case Len of
        0 ->
            +0.0;

        _ ->
            case erlang:float(Len) of
                +0.0 -> +0.0;
                -0.0 -> -0.0;
                Gleam@denominator -> sum_node(erlang:element(3, Chunk)) / Gleam@denominator
            end
    end.
