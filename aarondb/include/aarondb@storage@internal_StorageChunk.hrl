-record(storage_chunk, {
    attribute :: binary(),
    values :: aarondb@storage@internal:cracking_node(),
    max_tx :: integer(),
    is_compressed :: boolean()
}).
