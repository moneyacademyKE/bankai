-module(aarondb@shared@utils).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/utils.gleam").
-export([extract_json/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/shared/utils.gleam", 15).
-spec do_extract(binary(), integer(), boolean(), binary()) -> binary().
do_extract(Input, Depth, In_quote, Acc) ->
    case gleam_stdlib:string_pop_grapheme(Input) of
        {ok, {<<"\""/utf8>>, Rest}} ->
            do_extract(Rest, Depth, not In_quote, <<Acc/binary, "\""/utf8>>);

        {ok, {<<"{"/utf8>>, Rest@1}} when not In_quote ->
            do_extract(Rest@1, Depth + 1, false, <<Acc/binary, "{"/utf8>>);

        {ok, {<<"}"/utf8>>, Rest@2}} when not In_quote ->
            New_depth = Depth - 1,
            New_acc = <<Acc/binary, "}"/utf8>>,
            case New_depth =< 0 of
                true ->
                    New_acc;

                false ->
                    do_extract(Rest@2, New_depth, false, New_acc)
            end;

        {ok, {C, Rest@3}} ->
            do_extract(Rest@3, Depth, In_quote, <<Acc/binary, C/binary>>);

        {error, _} ->
            Acc
    end.

-file("src/aarondb/shared/utils.gleam", 5).
?DOC(
    " Extract the largest balanced JSON object from a string.\n"
    " This is useful for parsing LLM outputs that may contain preamble or postscript noise.\n"
).
-spec extract_json(binary()) -> binary().
extract_json(Input) ->
    case gleam@string:split_once(Input, <<"{"/utf8>>) of
        {ok, {_, Rest}} ->
            Candidate = <<"{"/utf8, Rest/binary>>,
            do_extract(Candidate, 0, false, <<""/utf8>>);

        {error, _} ->
            <<""/utf8>>
    end.
