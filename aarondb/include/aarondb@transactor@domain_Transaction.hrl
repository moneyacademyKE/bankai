-record(transaction, {
    facts :: list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    valid_time :: gleam@option:option(integer()),
    operation :: aarondb@fact:operation()
}).
