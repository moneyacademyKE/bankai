-module(aarondb@engine@solver@vector_input).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver/vector_input.gleam").
-export([vector_from_part/2]).

-file("src/aarondb/engine/solver/vector_input.gleam", 8).
-spec vector_from_part(
    aarondb@shared@ast:part(),
    gleam@dict:dict(binary(), aarondb@fact:value())
) -> list(float()).
vector_from_part(Target_p, Ctx) ->
    case aarondb@engine@solver@bindings:resolve_part(Target_p, Ctx) of
        {some, {vec, Vs}} ->
            Vs;

        {some, {list, Vs@1}} ->
            gleam@list:filter_map(Vs@1, fun(V) -> case V of
                        {float, F} ->
                            {ok, F};

                        _ ->
                            {error, nil}
                    end end);

        _ ->
            []
    end.
