-module(aarondb@engine@predicate).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/predicate.gleam").
-export([compile/1]).

-file("src/aarondb/engine/predicate.gleam", 50).
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

-file("src/aarondb/engine/predicate.gleam", 7).
-spec compile(aarondb@shared@ast:expression()) -> fun((gleam@dict:dict(binary(), aarondb@fact:value())) -> boolean()).
compile(Expr) ->
    case Expr of
        {eq, A, B} ->
            fun(Ctx) ->
                Val_a = resolve_part(A, Ctx),
                Val_b = resolve_part(B, Ctx),
                (Val_a =:= Val_b) andalso gleam@option:is_some(Val_a)
            end;

        {neq, A@1, B@1} ->
            fun(Ctx@1) ->
                Val_a@1 = resolve_part(A@1, Ctx@1),
                Val_b@1 = resolve_part(B@1, Ctx@1),
                Val_a@1 /= Val_b@1
            end;

        {gt, A@2, B@2} ->
            fun(Ctx@2) ->
                Val_a@2 = begin
                    _pipe = resolve_part(A@2, Ctx@2),
                    gleam@option:unwrap(_pipe, {int, 0})
                end,
                Val_b@2 = begin
                    _pipe@1 = resolve_part(B@2, Ctx@2),
                    gleam@option:unwrap(_pipe@1, {int, 0})
                end,
                aarondb@fact:compare(Val_a@2, Val_b@2) =:= gt
            end;

        {lt, A@3, B@3} ->
            fun(Ctx@3) ->
                Val_a@3 = begin
                    _pipe@2 = resolve_part(A@3, Ctx@3),
                    gleam@option:unwrap(_pipe@2, {int, 0})
                end,
                Val_b@3 = begin
                    _pipe@3 = resolve_part(B@3, Ctx@3),
                    gleam@option:unwrap(_pipe@3, {int, 0})
                end,
                aarondb@fact:compare(Val_a@3, Val_b@3) =:= lt
            end;

        {'and', L, R} ->
            Compiled_l = compile(L),
            Compiled_r = compile(R),
            fun(Ctx@4) -> Compiled_l(Ctx@4) andalso Compiled_r(Ctx@4) end;

        {'or', L@1, R@1} ->
            Compiled_l@1 = compile(L@1),
            Compiled_r@1 = compile(R@1),
            fun(Ctx@5) -> Compiled_l@1(Ctx@5) orelse Compiled_r@1(Ctx@5) end
    end.
