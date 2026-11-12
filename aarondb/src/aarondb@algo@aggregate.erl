-module(aarondb@algo@aggregate).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/algo/aggregate.gleam").
-export([aggregate/2]).

-file("src/aarondb/algo/aggregate.gleam", 24).
-spec sum(list(aarondb@fact:value())) -> {ok, aarondb@fact:value()} |
    {error, binary()}.
sum(Values) ->
    case Values of
        [] ->
            {ok, {int, 0}};

        [First | Rest] ->
            gleam@list:try_fold(Rest, First, fun(Acc, V) -> case {Acc, V} of
                        {{int, A}, {int, B}} ->
                            {ok, {int, A + B}};

                        {{float, A@1}, {float, B@1}} ->
                            {ok, {float, A@1 + B@1}};

                        {{int, A@2}, {float, B@2}} ->
                            {ok, {float, erlang:float(A@2) + B@2}};

                        {{float, A@3}, {int, B@3}} ->
                            {ok, {float, A@3 + erlang:float(B@3)}};

                        {_, _} ->
                            {error, <<"Cannot sum non-numeric values"/utf8>>}
                    end end)
    end.

-file("src/aarondb/algo/aggregate.gleam", 75).
-spec avg(list(aarondb@fact:value())) -> {ok, aarondb@fact:value()} |
    {error, binary()}.
avg(Values) ->
    case Values of
        [] ->
            {error, <<"Cannot compute average of empty list"/utf8>>};

        _ ->
            gleam@result:'try'(
                sum(Values),
                fun(S) ->
                    Count = erlang:length(Values),
                    case S of
                        {int, I} ->
                            {ok, {float, case erlang:float(Count) of
                                        +0.0 -> +0.0;
                                        -0.0 -> -0.0;
                                        Gleam@denominator -> erlang:float(I) / Gleam@denominator
                                    end}};

                        {float, F} ->
                            {ok, {float, case erlang:float(Count) of
                                        +0.0 -> +0.0;
                                        -0.0 -> -0.0;
                                        Gleam@denominator@1 -> F / Gleam@denominator@1
                                    end}};

                        _ ->
                            {error, <<"Cannot average non-numeric sum"/utf8>>}
                    end
                end
            )
    end.

-file("src/aarondb/algo/aggregate.gleam", 130).
-spec compare_values(aarondb@fact:value(), aarondb@fact:value()) -> {ok,
        gleam@order:order()} |
    {error, binary()}.
compare_values(A, B) ->
    case {A, B} of
        {{int, I1}, {int, I2}} ->
            {ok, gleam@int:compare(I1, I2)};

        {{float, F1}, {float, F2}} ->
            {ok, gleam@float:compare(F1, F2)};

        {{int, I1@1}, {float, F2@1}} ->
            {ok, gleam@float:compare(erlang:float(I1@1), F2@1)};

        {{float, F1@1}, {int, I2@1}} ->
            {ok, gleam@float:compare(F1@1, erlang:float(I2@1))};

        {{str, S1}, {str, S2}} ->
            {ok, gleam@string:compare(S1, S2)};

        {_, _} ->
            {error, <<"Cannot compare incompatible types"/utf8>>}
    end.

-file("src/aarondb/algo/aggregate.gleam", 90).
-spec median(list(aarondb@fact:value())) -> {ok, aarondb@fact:value()} |
    {error, binary()}.
median(Values) ->
    case Values of
        [] ->
            {error, <<"Cannot compute median of empty list"/utf8>>};

        _ ->
            Sorted = gleam@list:sort(
                Values,
                fun(A, B) -> case compare_values(A, B) of
                        {ok, O} ->
                            O;

                        {error, _} ->
                            eq
                    end end
            ),
            Len = erlang:length(Sorted),
            Mid = Len div 2,
            case Len rem 2 of
                1 ->
                    _pipe = gleam@list:drop(Sorted, Mid),
                    _pipe@1 = gleam@list:first(_pipe),
                    gleam@result:replace_error(_pipe@1, <<"Index error"/utf8>>);

                0 ->
                    M1 = begin
                        _pipe@2 = gleam@list:drop(Sorted, Mid - 1),
                        gleam@list:first(_pipe@2)
                    end,
                    M2 = begin
                        _pipe@3 = gleam@list:drop(Sorted, Mid),
                        gleam@list:first(_pipe@3)
                    end,
                    case {M1, M2} of
                        {{ok, V1}, {ok, V2}} ->
                            avg([V1, V2]);

                        {_, _} ->
                            {error, <<"Index error"/utf8>>}
                    end;

                _ ->
                    {error, <<"Math broken"/utf8>>}
            end
    end.

-file("src/aarondb/algo/aggregate.gleam", 58).
-spec max_val(list(aarondb@fact:value())) -> {ok, aarondb@fact:value()} |
    {error, binary()}.
max_val(Values) ->
    case Values of
        [] ->
            {error, <<"Cannot compute max of empty list"/utf8>>};

        [First | Rest] ->
            gleam@list:try_fold(
                Rest,
                First,
                fun(Acc, V) -> _pipe = compare_values(Acc, V),
                    gleam@result:map(_pipe, fun(Ord) -> case Ord of
                                gt ->
                                    Acc;

                                _ ->
                                    V
                            end end) end
            )
    end.

-file("src/aarondb/algo/aggregate.gleam", 41).
-spec min_val(list(aarondb@fact:value())) -> {ok, aarondb@fact:value()} |
    {error, binary()}.
min_val(Values) ->
    case Values of
        [] ->
            {error, <<"Cannot compute min of empty list"/utf8>>};

        [First | Rest] ->
            gleam@list:try_fold(
                Rest,
                First,
                fun(Acc, V) -> _pipe = compare_values(Acc, V),
                    gleam@result:map(_pipe, fun(Ord) -> case Ord of
                                lt ->
                                    Acc;

                                _ ->
                                    V
                            end end) end
            )
    end.

-file("src/aarondb/algo/aggregate.gleam", 10).
-spec aggregate(list(aarondb@fact:value()), aarondb@shared@ast:agg_func()) -> {ok,
        aarondb@fact:value()} |
    {error, binary()}.
aggregate(Values, Op) ->
    case Op of
        count ->
            {ok, {int, erlang:length(Values)}};

        sum ->
            sum(Values);

        min ->
            min_val(Values);

        max ->
            max_val(Values);

        avg ->
            avg(Values);

        median ->
            median(Values)
    end.
