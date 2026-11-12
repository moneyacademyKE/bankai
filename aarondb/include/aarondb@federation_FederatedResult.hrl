-record(federated_result, {
    rows :: list(aarondb@federation:federated_row()),
    sources :: list(binary())
}).
