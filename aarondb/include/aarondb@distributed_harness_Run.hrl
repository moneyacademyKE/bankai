-record(run, {
    seed :: integer(),
    schedule :: list(aarondb@distributed_harness:fault()),
    observations :: list(aarondb@distributed_harness:observation())
}).
