-record(state, {
    node :: binary(),
    role :: aarondb@raft_runtime:role(),
    hard :: aarondb@raft_runtime:hard_state(),
    members :: list(aarondb@raft_runtime:member()),
    log :: list(aarondb@raft_runtime:log_entry()),
    last_applied :: integer(),
    leader :: gleam@option:option(binary()),
    snapshot :: gleam@option:option(aarondb@raft_runtime:snapshot())
}).
