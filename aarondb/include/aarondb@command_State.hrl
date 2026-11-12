-record(state, {
    values :: list(aarondb@command:value()),
    fences :: list({binary(), integer()}),
    applied :: list(aarondb@command:applied()),
    last_applied :: integer()
}).
