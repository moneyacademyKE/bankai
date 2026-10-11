%% bk-07a7: a boot crash must KILL the VM. Gleam's generated escript main
%% tries to pretty-print uncaught errors and that printer itself can crash
%% (bad iolist from non-Gleam error terms), leaving a zombie BEAM that
%% launchd's KeepAlive counts as alive — permanent silent outage.
%%
%% Wrapping the serve entry here: any crash/exit/throw during boot (or at
%% any later point — the supervisor owns restart policy) prints one plain
%% line to stderr and halts with a non-zero status so launchd respawns us.
-module(bankai_boot_ffi).
-export([run_or_halt/1]).

run_or_halt(Fun) ->
  try
    Fun()
  catch
    Class:Reason:Stack ->
      io:format(standard_error, "bankai serve crashed: ~p ~p~n~p~n", [
        Class, Reason, Stack
      ]),
      erlang:halt(1)
  end.
