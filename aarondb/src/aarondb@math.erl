-module(aarondb@math).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/math.gleam").
-export([cosine_similarity/2]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/math.gleam", 34).
-spec magnitude(list(float())) -> float().
magnitude(V) ->
    Sum_sq = gleam@list:fold(V, +0.0, fun(Acc, X) -> Acc + (X * X) end),
    Res@1 = case gleam@float:square_root(Sum_sq) of
        {ok, Res} -> Res;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/math"/utf8>>,
                        function => <<"magnitude"/utf8>>,
                        line => 36,
                        value => _assert_fail,
                        start => 918,
                        'end' => 964,
                        pattern_start => 929,
                        pattern_end => 936})
    end,
    Res@1.

-file("src/aarondb/math.gleam", 26).
-spec dot(list(float()), list(float())) -> float().
dot(A, B) ->
    _pipe = gleam@list:zip(A, B),
    gleam@list:fold(
        _pipe,
        +0.0,
        fun(Acc, Pair) ->
            {X, Y} = Pair,
            Acc + (X * Y)
        end
    ).

-file("src/aarondb/math.gleam", 7).
?DOC(
    " Calculate the cosine similarity between two vectors.\n"
    " Result is between -1.0 and 1.0.\n"
    " Returns Error if vectors have different lengths or depend on 0 magnitude.\n"
).
-spec cosine_similarity(list(float()), list(float())) -> {ok, float()} |
    {error, nil}.
cosine_similarity(A, B) ->
    Len_a = erlang:length(A),
    Len_b = erlang:length(B),
    case Len_a =:= Len_b of
        false ->
            {error, nil};

        true ->
            Dot_product = dot(A, B),
            Mag_a = magnitude(A),
            Mag_b = magnitude(B),
            case (Mag_a =:= +0.0) orelse (Mag_b =:= +0.0) of
                true ->
                    {error, nil};

                false ->
                    {ok, case (Mag_a * Mag_b) of
                            +0.0 -> +0.0;
                            -0.0 -> -0.0;
                            Gleam@denominator -> Dot_product / Gleam@denominator
                        end}
            end
    end.
