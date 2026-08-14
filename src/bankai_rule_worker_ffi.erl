-module(bankai_rule_worker_ffi).
-export([run_bounded/4, exhaust_reductions/0]).

%% Execute untrusted pure work in an unlinked process with three independent
%% bounds: wall clock, process heap words, and BEAM reductions. The result of
%% Work is opaque to this module and returned unchanged inside {ok, Result}.
run_bounded(Work, TimeoutMs, MaxHeapWords, ReductionLimit) ->
    Parent = self(),
    Tag = make_ref(),
    Started = erlang:monotonic_time(millisecond),
    Options = [
        monitor,
        {max_heap_size, #{
            size => MaxHeapWords,
            kill => true,
            error_logger => false
        }}
    ],
    {Pid, Monitor} = spawn_opt(fun() -> Parent ! {Tag, Work()} end, Options),
    await(Pid, Monitor, Tag, Started, TimeoutMs, ReductionLimit).

await(Pid, Monitor, Tag, Started, TimeoutMs, ReductionLimit) ->
    receive
        {Tag, Result} ->
            erlang:demonitor(Monitor, [flush]),
            {ok, Result};
        {'DOWN', Monitor, process, Pid, killed} ->
            {error, <<"rule eval exceeded heap limit">>};
        {'DOWN', Monitor, process, Pid, _Reason} ->
            {error, <<"rule eval crashed (isolated process exited)">>}
    after 1 ->
        Elapsed = erlang:monotonic_time(millisecond) - Started,
        case Elapsed >= TimeoutMs of
            true ->
                stop(Pid, Monitor),
                {error, iolist_to_binary(io_lib:format(
                    "rule eval timed out after ~Bms", [TimeoutMs]))};
            false ->
                case process_info(Pid, reductions) of
                    {reductions, Count} when Count > ReductionLimit ->
                        stop(Pid, Monitor),
                        {error, iolist_to_binary(io_lib:format(
                            "rule eval exceeded reduction budget (~B)",
                            [ReductionLimit]))};
                    _ -> await(Pid, Monitor, Tag, Started, TimeoutMs, ReductionLimit)
                end
        end
    end.

stop(Pid, Monitor) ->
    exit(Pid, kill),
    receive
        {'DOWN', Monitor, process, Pid, _} -> ok
    after 50 ->
        erlang:demonitor(Monitor, [flush])
    end.

%% Test helper: consume reductions without allocating an unbounded heap.
exhaust_reductions() -> exhaust_reductions(0).
exhaust_reductions(N) when N >= 0 -> exhaust_reductions(N + 1).
