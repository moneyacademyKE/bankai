-record(status, {
    leader :: gleam@option:option(binary()),
    commit_index :: integer(),
    replication_lag :: integer(),
    quorum :: aarondb@operations:quorum_health(),
    projection :: aarondb@projection:status(),
    index_health :: aarondb@projection_index:health(),
    lease_count :: integer(),
    alarms :: list(aarondb@operations:alarm())
}).
