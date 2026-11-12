-record(durable_log, {
    source :: binary(),
    next_offset :: integer(),
    entries :: list(aarondb@durable_log:entry()),
    snapshots :: list(aarondb@durable_log:snapshot()),
    checkpoints :: list(aarondb@durable_log:projection_checkpoint())
}).
