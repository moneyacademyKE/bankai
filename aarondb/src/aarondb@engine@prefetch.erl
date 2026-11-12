-module(aarondb@engine@prefetch).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/prefetch.gleam").
-export([analyze_history/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/engine/prefetch.gleam", 9).
?DOC(
    " Analyzes the recent query history to identify the most heavily \n"
    " requested attributes that might benefit from predictive prefetching.\n"
).
-spec analyze_history(list(aarondb@shared@state:query_context())) -> list(binary()).
analyze_history(History) ->
    Counts = gleam@list:fold(
        History,
        maps:new(),
        fun(Acc, Ctx) ->
            gleam@list:fold(
                erlang:element(2, Ctx),
                Acc,
                fun(A, Attr) ->
                    Count = begin
                        _pipe = gleam_stdlib:map_get(A, Attr),
                        gleam@result:unwrap(_pipe, 0)
                    end,
                    gleam@dict:insert(A, Attr, Count + 1)
                end
            )
        end
    ),
    _pipe@1 = maps:to_list(Counts),
    _pipe@2 = gleam@list:sort(
        _pipe@1,
        fun(A@1, B) ->
            gleam@int:compare(erlang:element(2, B), erlang:element(2, A@1))
        end
    ),
    _pipe@3 = gleam@list:filter(
        _pipe@2,
        fun(Pair) -> erlang:element(2, Pair) >= 2 end
    ),
    gleam@list:map(_pipe@3, fun(Pair@1) -> erlang:element(1, Pair@1) end).
