-module(aarondb@engine@solver@stores).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/stores.gleam").
-export([merge_optional_stores/2]).

-file("src/aarondb/engine/solver/stores.gleam", 5).
-spec merge_optional_stores(
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))),
    gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))
) -> gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))).
merge_optional_stores(S1, S2) ->
    case {S1, S2} of
        {{some, M1}, {some, M2}} ->
            {some, maps:merge(M1, M2)};

        {{some, _}, none} ->
            S1;

        {none, {some, _}} ->
            S2;

        {none, none} ->
            none
    end.
