-module(aarondb@process_extra).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/process_extra.gleam").
-export([subject_to_pid/1, pid_to_subject/1, self/0, is_alive/1]).

-file("src/aarondb/process_extra.gleam", 4).
-spec subject_to_pid(gleam@erlang@process:subject(any())) -> gleam@erlang@process:pid_().
subject_to_pid(Subject) ->
    aarondb_process_ffi:subject_to_pid(Subject).

-file("src/aarondb/process_extra.gleam", 7).
-spec pid_to_subject(gleam@erlang@process:pid_()) -> gleam@erlang@process:subject(any()).
pid_to_subject(Pid) ->
    aarondb_process_ffi:pid_to_subject(Pid).

-file("src/aarondb/process_extra.gleam", 10).
-spec self() -> gleam@erlang@process:pid_().
self() ->
    aarondb_process_ffi:self().

-file("src/aarondb/process_extra.gleam", 13).
-spec is_alive(gleam@erlang@process:subject(any())) -> boolean().
is_alive(Subject) ->
    aarondb_process_ffi:is_alive(Subject).
