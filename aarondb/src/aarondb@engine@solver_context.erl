-module(aarondb@engine@solver_context).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/engine/solver_context.gleam").
-export_type([solver_context/0]).

-type solver_context() :: {solver_context,
        aarondb@shared@state:db_state(),
        list(aarondb@shared@ast:rule()),
        gleam@set:set(aarondb@fact:datom()),
        gleam@option:option(integer()),
        gleam@option:option(integer())}.


