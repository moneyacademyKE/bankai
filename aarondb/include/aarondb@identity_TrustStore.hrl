-record(trust_store, {
    cluster :: binary(),
    trusted_issuers :: list(binary()),
    certificates :: list(aarondb@identity:certificate()),
    members :: list(binary())
}).
