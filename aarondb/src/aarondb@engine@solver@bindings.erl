-module(aarondb@engine@solver@bindings).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/bindings.gleam").
-export([resolve_part/2, resolve_part_optional/2]).

-file("src/aarondb/engine/solver/bindings.gleam", 6).
-spec resolve_part(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:value()).
resolve_part(Part, Ctx) ->
    case Part of
        {var, Name} ->
            gleam@option:from_result(gleam_stdlib:map_get(Ctx, Name));

        {val, Val} ->
            {some, Val};

        {uid, Uid} ->
            {some, {ref, Uid}};

        {attr_val, S} ->
            {some, {str, S}};

        {lookup, {_, Val@1}} ->
            {some, Val@1}
    end.

-file("src/aarondb/engine/solver/bindings.gleam", 19).
-spec resolve_part_optional(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> gleam@option:option(aarondb@fact:value()).
resolve_part_optional(Part, Ctx) ->
    case Part of
        {var, Name} ->
            gleam@option:from_result(gleam_stdlib:map_get(Ctx, Name));

        {val, Val} ->
            {some, Val};

        {uid, Uid} ->
            {some, {ref, Uid}};

        {attr_val, S} ->
            {some, {str, S}};

        {lookup, {_, Val@1}} ->
            {some, Val@1}
    end.
