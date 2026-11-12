-module(aarondb@engine@virtual).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/virtual.gleam").
-export([solve/5]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/engine/virtual.gleam", 40).
-spec bind_outputs(
    gleam@dict:dict(binary(), aarondb@fact:value()),
    list(binary()),
    list(aarondb@fact:value())
) -> {ok, gleam@dict:dict(binary(), aarondb@fact:value())} | {error, nil}.
bind_outputs(Ctx, Outputs, Row) ->
    case erlang:length(Outputs) =:= erlang:length(Row) of
        true ->
            _pipe = gleam@list:zip(Outputs, Row),
            gleam@list:try_fold(
                _pipe,
                Ctx,
                fun(Acc, Pair) ->
                    {Var, Val} = Pair,
                    case gleam_stdlib:map_get(Acc, Var) of
                        {ok, Existing} ->
                            case Existing =:= Val of
                                true ->
                                    {ok, Acc};

                                false ->
                                    {error, nil}
                            end;

                        {error, _} ->
                            {ok, gleam@dict:insert(Acc, Var, Val)}
                    end
                end
            );

        false ->
            {error, nil}
    end.

-file("src/aarondb/engine/virtual.gleam", 64).
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

-file("src/aarondb/engine/virtual.gleam", 11).
?DOC(
    " Run a bounded local adapter. Rows retain the adapter's order; an adapter\n"
    " failure, invalid row limit, or row-limit overflow makes this clause produce\n"
    " no rows. Query execution is intentionally fail-closed at this boundary.\n"
).
-spec solve(
    aarondb@shared@state:db_state(),
    binary(),
    list(aarondb@shared@ast:part()),
    list(binary()),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
solve(Db_state, Predicate, Args, Outputs, Ctx) ->
    Resolved_args = gleam@list:try_map(
        Args,
        fun(Arg) -> _pipe = resolve_part(Arg, Ctx),
            gleam@option:to_result(_pipe, nil) end
    ),
    case {Resolved_args,
        gleam_stdlib:map_get(erlang:element(22, Db_state), Predicate)} of
        {{ok, Vals}, {ok, {virtual_adapter, Execute, Max_rows}}} ->
            case Execute(Vals) of
                {ok, Rows} ->
                    case erlang:length(Rows) =< Max_rows of
                        true ->
                            _pipe@1 = Rows,
                            gleam@list:filter_map(
                                _pipe@1,
                                fun(Row) -> bind_outputs(Ctx, Outputs, Row) end
                            );

                        false ->
                            []
                    end;

                {error, _} ->
                    []
            end;

        {_, _} ->
            []
    end.
