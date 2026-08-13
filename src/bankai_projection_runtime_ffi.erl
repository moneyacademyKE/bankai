-module(bankai_projection_runtime_ffi).
-export([start/1, ensure/1, reset_workspace/1, status/1]).

%% A daemon-local holder for replayable AaronDB projection values. Mnesia remains
%% authoritative; this ETS table only retains an in-process projection between
%% requests so a read does not rebuild snapshot/tail state every time.
-define(TABLE, bankai_projection_runtime_v1).

start(Workspace) ->
    ensure_table(),
    case bankai@projections:bootstrap(Workspace) of
        {ok, View} ->
            true = ets:insert(?TABLE, {Workspace, View}),
            {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

ensure(Workspace) -> refresh(Workspace).

reset_workspace(Workspace) ->
    ensure_table(),
    ets:delete(?TABLE, Workspace),
    {ok, nil}.

status(Workspace) ->
    ensure_table(),
    case ets:lookup(?TABLE, Workspace) of
        [{Workspace, View}] ->
            {health, Watermark, History, Text, Vector} = bankai@projections:health(View),
            {status, HistoryState, HistoryOffset, HistoryLag, HistoryFailure, _, _} = History,
            {status, TextState, TextOffset, TextLag, TextFailure, _, _} = Text,
            {status, VectorState, VectorOffset, VectorLag, VectorFailure, _, _} = Vector,
            {ok, {bankai@projections:healthy(View), Watermark,
                  atom_to_binary(HistoryState, utf8), HistoryOffset, HistoryLag,
                  failure_text(HistoryFailure),
                  atom_to_binary(TextState, utf8), TextOffset, TextLag,
                  failure_text(TextFailure),
                  atom_to_binary(VectorState, utf8), VectorOffset, VectorLag,
                  failure_text(VectorFailure)}};
        [] -> {error, <<"projection runtime is not started">>}
    end.

refresh(Workspace) ->
    ensure_table(),
    Result = case ets:lookup(?TABLE, Workspace) of
        [] -> bankai@projections:bootstrap(Workspace);
        [{Workspace, ExistingView}] -> bankai@projections:catch_up(ExistingView, Workspace)
    end,
    case Result of
        {ok, UpdatedView} ->
            true = ets:insert(?TABLE, {Workspace, UpdatedView}),
            {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

ensure_table() ->
    case ets:info(?TABLE) of
        undefined ->
            try ets:new(?TABLE, [named_table, public, set,
                                 {read_concurrency, true}, {write_concurrency, true}]) of
                _ -> ok
            catch error:badarg -> ok
            end;
        _ -> ok
    end.

failure_text(none) -> <<>>;
failure_text({some, Failure}) -> iolist_to_binary(io_lib:format("~p", [Failure])).
