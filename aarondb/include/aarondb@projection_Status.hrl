-record(status, {
    state :: aarondb@projection:projection_state(),
    last_applied_offset :: integer(),
    lag :: integer(),
    failure :: gleam@option:option(aarondb@projection:failure()),
    generation :: integer(),
    metrics :: aarondb@projection:metrics()
}).
