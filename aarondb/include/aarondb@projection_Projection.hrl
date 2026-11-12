-record(projection, {
    name :: binary(),
    generation :: integer(),
    max_batch :: integer(),
    max_restarts :: integer(),
    state :: aarondb@projection:projection_state(),
    last_applied_offset :: integer(),
    applied_offsets :: list(integer()),
    values :: list(binary()),
    failure :: gleam@option:option(aarondb@projection:failure()),
    metrics :: aarondb@projection:metrics()
}).
