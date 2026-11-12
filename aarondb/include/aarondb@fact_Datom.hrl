-record(datom, {
    entity :: aarondb@fact:entity_id(),
    attribute :: binary(),
    value :: aarondb@fact:value(),
    tx :: integer(),
    tx_index :: integer(),
    valid_time :: integer(),
    operation :: aarondb@fact:operation()
}).
