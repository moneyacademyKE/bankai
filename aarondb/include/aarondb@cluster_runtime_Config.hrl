-record(config, {
    node :: binary(),
    cluster :: binary(),
    members :: list(aarondb@raft_runtime:member()),
    trust :: aarondb@identity:trust_store(),
    limits :: aarondb@identity:rpc_limits(),
    deadline_ms :: integer()
}).
