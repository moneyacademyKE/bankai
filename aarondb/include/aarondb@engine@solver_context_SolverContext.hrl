-record(solver_context, {
    db_state :: aarondb@shared@state:db_state(),
    rules :: list(aarondb@shared@ast:rule()),
    derived :: gleam@set:set(aarondb@fact:datom()),
    as_of_tx :: gleam@option:option(integer()),
    as_of_valid :: gleam@option:option(integer())
}).
