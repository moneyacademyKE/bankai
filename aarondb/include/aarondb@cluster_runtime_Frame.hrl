-record(frame, {
    version :: integer(),
    cluster :: binary(),
    from :: aarondb@cluster_runtime:peer(),
    bytes :: integer(),
    rpc :: aarondb@raft_runtime:rpc()
}).
