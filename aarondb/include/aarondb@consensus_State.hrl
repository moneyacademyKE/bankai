-record(state, {
    raft :: aarondb@raft_runtime:state(),
    commands :: aarondb@command:state(),
    leases :: list(aarondb@consensus:lease()),
    last_now :: integer()
}).
