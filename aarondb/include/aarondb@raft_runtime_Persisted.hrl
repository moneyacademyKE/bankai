-record(persisted, {
    hard :: aarondb@raft_runtime:hard_state(),
    log :: list(aarondb@raft_runtime:log_entry()),
    snapshot :: gleam@option:option(aarondb@raft_runtime:snapshot()),
    last_applied :: integer()
}).
