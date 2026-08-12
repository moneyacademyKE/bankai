%% Task-4 benchmark runner. It compares the legacy request-scoped HNSW build
%% against Bankai's managed projection: one warm-up build followed by a steady
%% query at the identical committed offset.
-module(projection_bench).
-export([run/0]).

run() ->
    io:format("tasks,datalog_build_us,datalog_query_us,bm25_build_query_us,hnsw_fresh_us,hnsw_managed_build_us,hnsw_managed_steady_query_us~n"),
    lists:foreach(fun benchmark/1, [100, 1000, 5000]),
    ok.

benchmark(N) ->
    Tasks = [task(I) || I <- lists:seq(1, N)],
    Docs = [doc(I) || I <- lists:seq(1, N)],
    {BuildUs, Db} = timer:tc(bankai@aarondb_bridge, db_from_tasks, [Tasks]),
    {QueryUs, _} = timer:tc(bankai@aarondb_bridge, count_by_status, [element(2, Db)]),
    {Bm25Us, _} = timer:tc(bankai@aarondb_bridge, search, [Docs, <<"authentication worker">>]),
    Workspace = iolist_to_binary(io_lib:format("bench-~B", [N])),
    ok = reset_vector(Workspace),
    VectorDocs = [vector_doc(I) || I <- lists:seq(1, N)],
    {FreshUs, _} = timer:tc(bankai@vector_bridge, search,
                            [VectorDocs, <<"authentication worker">>, 0.10, 12]),
    {ManagedBuildUs, _} = timer:tc(bankai@vector_bridge, projected_search,
                                   [Workspace, 0, VectorDocs,
                                    <<"authentication worker">>, 0.10, 12]),
    {ManagedQueryUs, _} = timer:tc(bankai@vector_bridge, projected_search,
                                   [Workspace, 0, VectorDocs,
                                    <<"authentication worker">>, 0.10, 12]),
    io:format("~B,~B,~B,~B,~B,~B,~B~n",
              [N, BuildUs, QueryUs, Bm25Us, FreshUs, ManagedBuildUs, ManagedQueryUs]).

reset_vector(Workspace) ->
    case bankai@vector_bridge:reset_projection_for_test(Workspace) of
        {ok, nil} -> ok;
        _ -> ok
    end.

task(I) ->
    Id = id(I),
    Title = text(I),
    {task, Id, Title, <<"">>, open, none, 1, I, I, [], [], <<>>, none,
     default_task, none, none, none, false}.

doc(I) ->
    {<<"task">>, id(I), text(I)}.

vector_doc(I) ->
    {document, <<"task">>, id(I), text(I)}.

id(I) ->
    iolist_to_binary(io_lib:format("bk-~B", [I])).

text(I) ->
    case I rem 10 of
        0 -> <<"authentication worker session token refresh database migration">>;
        _ -> iolist_to_binary(io_lib:format("feature task ~B queue event processing", [I]))
    end.
