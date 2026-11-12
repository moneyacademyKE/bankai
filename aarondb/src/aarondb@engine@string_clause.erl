-module(aarondb@engine@string_clause).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/string_clause.gleam").
-export([starts_with/4]).

-file("src/aarondb/engine/string_clause.gleam", 8).
-spec starts_with(
    aarondb@shared@state:db_state(),
    binary(),
    binary(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
starts_with(Db_state, Var, Prefix, Ctx) ->
    case gleam_stdlib:map_get(Ctx, Var) of
        {ok, {str, S}} ->
            case gleam_stdlib:string_starts_with(S, Prefix) of
                true ->
                    [Ctx];

                false ->
                    []
            end;

        {ok, _} ->
            [];

        {error, _} ->
            _pipe = aarondb@index@art:search_prefix_entries(
                erlang:element(17, Db_state),
                Prefix
            ),
            _pipe@1 = gleam@list:map(
                _pipe,
                fun(Entry) ->
                    {Val, _} = Entry,
                    gleam@dict:insert(Ctx, Var, Val)
                end
            ),
            gleam@list:unique(_pipe@1)
    end.
