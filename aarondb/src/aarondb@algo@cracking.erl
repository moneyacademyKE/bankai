-module(aarondb@algo@cracking).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/algo/cracking.gleam").
-export([partition/2, compare_values/2, crack_chunk/2]).

-file("src/aarondb/algo/cracking.gleam", 11).
-spec partition(aarondb@storage@internal:cracking_node(), aarondb@fact:value()) -> aarondb@storage@internal:cracking_node().
partition(Node, Pivot) ->
    case Node of
        {leaf, Values} ->
            {Smaller, Larger} = gleam@list:partition(
                Values,
                fun(V) -> aarondb@fact:compare(V, Pivot) =:= lt end
            ),
            {branch, Pivot, {leaf, Smaller}, {leaf, Larger}};

        {branch, P, Left, Right} ->
            case aarondb@fact:compare(Pivot, P) of
                lt ->
                    {branch, P, partition(Left, Pivot), Right};

                _ ->
                    {branch, P, Left, partition(Right, Pivot)}
            end
    end.

-file("src/aarondb/algo/cracking.gleam", 53).
-spec compare_values(aarondb@fact:value(), aarondb@fact:value()) -> gleam@order:order().
compare_values(A, B) ->
    case {A, B} of
        {{int, I1}, {int, I2}} ->
            gleam@int:compare(I1, I2);

        {{float, F1}, {float, F2}} ->
            gleam@float:compare(F1, F2);

        {{int, I}, {float, F}} ->
            gleam@float:compare(erlang:float(I), F);

        {{float, F@1}, {int, I@1}} ->
            gleam@float:compare(F@1, erlang:float(I@1));

        {{str, S1}, {str, S2}} ->
            gleam@string:compare(S1, S2);

        {_, _} ->
            eq
    end.

-file("src/aarondb/algo/cracking.gleam", 31).
-spec crack_node(aarondb@storage@internal:cracking_node(), aarondb@fact:value()) -> aarondb@storage@internal:cracking_node().
crack_node(Node, Pivot) ->
    case Node of
        {leaf, Values} ->
            {Left_vals, Right_vals} = gleam@list:partition(
                Values,
                fun(V) -> compare_values(V, Pivot) =:= lt end
            ),
            case gleam@list:is_empty(Left_vals) orelse gleam@list:is_empty(
                Right_vals
            ) of
                true ->
                    {leaf, Values};

                false ->
                    {branch, Pivot, {leaf, Left_vals}, {leaf, Right_vals}}
            end;

        {branch, P, Left, Right} ->
            case compare_values(Pivot, P) of
                lt ->
                    {branch, P, crack_node(Left, Pivot), Right};

                _ ->
                    {branch, P, Left, crack_node(Right, Pivot)}
            end
    end.

-file("src/aarondb/algo/cracking.gleam", 27).
-spec crack_chunk(
    aarondb@storage@internal:storage_chunk(),
    aarondb@fact:value()
) -> aarondb@storage@internal:storage_chunk().
crack_chunk(Chunk, Pivot) ->
    {storage_chunk,
        erlang:element(2, Chunk),
        crack_node(erlang:element(3, Chunk), Pivot),
        erlang:element(4, Chunk),
        erlang:element(5, Chunk)}.
