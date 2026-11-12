-record(column_chunk, {
    attribute :: binary(),
    values :: list(aarondb@fact:value()),
    max_tx :: integer(),
    is_compressed :: boolean()
}).
