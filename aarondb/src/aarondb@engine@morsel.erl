-module(aarondb@engine@morsel).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/morsel.gleam").
-export([execute_morsels/5]).
-export_type([worker_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type worker_result() :: {worker_result,
        list(gleam@dict:dict(binary(), aarondb@fact:value()))}.

-file("src/aarondb/engine/morsel.gleam", 41).
-spec receive_all(
    gleam@erlang@process:subject(worker_result()),
    integer(),
    list(gleam@dict:dict(binary(), aarondb@fact:value()))
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
receive_all(Subject, Remaining, Acc) ->
    case Remaining of
        0 ->
            Acc;

        N ->
            case gleam@erlang@process:'receive'(Subject, 5000) of
                {ok, {worker_result, Res}} ->
                    receive_all(Subject, N - 1, lists:append(Acc, Res));

                {error, _} ->
                    receive_all(Subject, N - 1, Acc)
            end
    end.

-file("src/aarondb/engine/morsel.gleam", 60).
-spec evaluate_chunk(
    list(aarondb@fact:datom()),
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part()
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
evaluate_chunk(Datoms, Contexts, E_p, V_p) ->
    gleam@list:flat_map(
        Datoms,
        fun(D) ->
            gleam@list:map(
                Contexts,
                fun(Ctx) ->
                    B = Ctx,
                    B@1 = case E_p of
                        {var, N} ->
                            gleam@dict:insert(B, N, {ref, erlang:element(2, D)});

                        _ ->
                            B
                    end,
                    B@2 = case V_p of
                        {var, N@1} ->
                            gleam@dict:insert(B@1, N@1, erlang:element(4, D));

                        _ ->
                            B@1
                    end,
                    B@2
                end
            )
        end
    ).

-file("src/aarondb/engine/morsel.gleam", 13).
?DOC(" Evaluates a compiled predicate over a \"morsel\" (chunk) of Datoms concurrently.\n").
-spec execute_morsels(
    list(aarondb@fact:datom()),
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    integer()
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
execute_morsels(Datoms, Contexts, E_p, V_p, Chunk_size) ->
    case erlang:length(Datoms) =< Chunk_size of
        true ->
            evaluate_chunk(Datoms, Contexts, E_p, V_p);

        false ->
            Chunks = gleam@list:sized_chunk(Datoms, Chunk_size),
            Subject = gleam@erlang@process:new_subject(),
            gleam@list:each(
                Chunks,
                fun(Chunk) ->
                    erlang:spawn(
                        fun() ->
                            Res = evaluate_chunk(Chunk, Contexts, E_p, V_p),
                            gleam@erlang@process:send(
                                Subject,
                                {worker_result, Res}
                            )
                        end
                    )
                end
            ),
            Num_chunks = erlang:length(Chunks),
            receive_all(Subject, Num_chunks, [])
    end.
