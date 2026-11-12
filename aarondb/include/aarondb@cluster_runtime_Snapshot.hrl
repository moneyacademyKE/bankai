-record(snapshot, {
    node :: binary(),
    raft :: aarondb@raft_runtime:state(),
    peers :: list(aarondb@cluster_runtime:peer()),
    running :: boolean()
}).
