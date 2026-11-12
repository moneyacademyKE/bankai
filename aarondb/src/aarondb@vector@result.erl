-module(aarondb@vector@result).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vector/result.gleam").
-export([compare_search_results/2]).
-export_type([search_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type search_result() :: {search_result, aarondb@fact:entity_id(), float()}.

-file("src/aarondb/vector/result.gleam", 15).
?DOC(
    " Deterministic descending-score ordering for vector results.\n"
    "\n"
    " Equal scores are resolved by ascending entity ID, so exact search, HNSW\n"
    " traversal, benchmarks, and tests share one mechanically comparable order.\n"
).
-spec compare_search_results(search_result(), search_result()) -> gleam@order:order().
compare_search_results(A, B) ->
    case gleam@float:compare(erlang:element(3, B), erlang:element(3, A)) of
        eq ->
            gleam@int:compare(
                aarondb@fact:eid_to_integer(erlang:element(2, A)),
                aarondb@fact:eid_to_integer(erlang:element(2, B))
            );

        Other ->
            Other
    end.
