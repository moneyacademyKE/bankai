-record(install_snapshot, {
    term :: integer(),
    leader :: binary(),
    snapshot :: aarondb@raft_runtime:snapshot()
}).
