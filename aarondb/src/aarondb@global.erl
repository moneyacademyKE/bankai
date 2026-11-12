-module(aarondb@global).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/global.gleam").
-export([register/2, whereis/1, unregister/1]).

-file("src/aarondb/global.gleam", 4).
-spec register(binary(), gleam@erlang@process:pid_()) -> {ok, nil} |
    {error, nil}.
register(Name, Pid) ->
    aarondb_global_ffi:register(Name, Pid).

-file("src/aarondb/global.gleam", 7).
-spec whereis(binary()) -> {ok, gleam@erlang@process:pid_()} | {error, nil}.
whereis(Name) ->
    aarondb_global_ffi:whereis(Name).

-file("src/aarondb/global.gleam", 10).
-spec unregister(binary()) -> nil.
unregister(Name) ->
    aarondb_global_ffi:unregister(Name).
