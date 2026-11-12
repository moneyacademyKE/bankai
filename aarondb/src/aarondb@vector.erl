-module(aarondb@vector).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vector.gleam").
-export([dot_product/2, magnitude/1, cosine_similarity/2, euclidean_distance/2, normalize/1, dimensions/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/vector.gleam", 8).
-spec do_dot_product(list(float()), list(float()), float()) -> float().
do_dot_product(V1, V2, Acc) ->
    case {V1, V2} of
        {[X | Xs], [Y | Ys]} ->
            do_dot_product(Xs, Ys, Acc + (X * Y));

        {_, _} ->
            Acc
    end.

-file("src/aarondb/vector.gleam", 4).
-spec dot_product(list(float()), list(float())) -> float().
dot_product(V1, V2) ->
    do_dot_product(V1, V2, +0.0).

-file("src/aarondb/vector.gleam", 15).
-spec magnitude(list(float())) -> float().
magnitude(V) ->
    Sum_sq = gleam@list:fold(V, +0.0, fun(Acc, X) -> Acc + (X * X) end),
    case gleam@float:square_root(Sum_sq) of
        {ok, M} ->
            M;

        {error, _} ->
            +0.0
    end.

-file("src/aarondb/vector.gleam", 23).
-spec cosine_similarity(list(float()), list(float())) -> float().
cosine_similarity(V1, V2) ->
    Mag1 = magnitude(V1),
    Mag2 = magnitude(V2),
    case (Mag1 =:= +0.0) orelse (Mag2 =:= +0.0) of
        true ->
            +0.0;

        false ->
            case (Mag1 * Mag2) of
                +0.0 -> +0.0;
                -0.0 -> -0.0;
                Gleam@denominator -> dot_product(V1, V2) / Gleam@denominator
            end
    end.

-file("src/aarondb/vector.gleam", 34).
?DOC(" L2 (Euclidean) distance between two vectors.\n").
-spec euclidean_distance(list(float()), list(float())) -> float().
euclidean_distance(V1, V2) ->
    Sum_sq = begin
        _pipe = gleam@list:zip(V1, V2),
        gleam@list:fold(
            _pipe,
            +0.0,
            fun(Acc, Pair) ->
                Diff = erlang:element(1, Pair) - erlang:element(2, Pair),
                Acc + (Diff * Diff)
            end
        )
    end,
    case gleam@float:square_root(Sum_sq) of
        {ok, D} ->
            D;

        {error, _} ->
            +0.0
    end.

-file("src/aarondb/vector.gleam", 48).
?DOC(" Normalize a vector to unit length.\n").
-spec normalize(list(float())) -> list(float()).
normalize(V) ->
    Mag = magnitude(V),
    case Mag =:= +0.0 of
        true ->
            V;

        false ->
            gleam@list:map(V, fun(X) -> case Mag of
                        +0.0 -> +0.0;
                        -0.0 -> -0.0;
                        Gleam@denominator -> X / Gleam@denominator
                    end end)
    end.

-file("src/aarondb/vector.gleam", 57).
?DOC(" Number of dimensions.\n").
-spec dimensions(list(float())) -> integer().
dimensions(V) ->
    erlang:length(V).
