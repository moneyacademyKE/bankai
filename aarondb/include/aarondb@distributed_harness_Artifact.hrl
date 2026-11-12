-record(artifact, {
    seed :: integer(),
    schedule :: list(aarondb@distributed_harness:fault()),
    observations :: list(aarondb@distributed_harness:observation()),
    violations :: list(aarondb@distributed_harness:violation())
}).
