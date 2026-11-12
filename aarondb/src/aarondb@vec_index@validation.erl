-module(aarondb@vec_index@validation).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vec_index/validation.gleam").
-export([vector_is_valid/1, query_is_valid/3]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/vec_index/validation.gleam", 4).
?DOC(" True when a vector has at least one dimension and non-zero magnitude.\n").
-spec vector_is_valid(list(float())) -> boolean().
vector_is_valid(Vec) ->
    (aarondb@vector:dimensions(Vec) > 0) andalso (aarondb@vector:magnitude(Vec)
    /= +0.0).

-file("src/aarondb/vec_index/validation.gleam", 9).
?DOC(" True when a query can be evaluated against an index.\n").
-spec query_is_valid(list(float()), float(), integer()) -> boolean().
query_is_valid(Query, Threshold, K) ->
    ((vector_is_valid(Query) andalso (Threshold >= -1.0)) andalso (Threshold =< 1.0))
    andalso (K > 0).
