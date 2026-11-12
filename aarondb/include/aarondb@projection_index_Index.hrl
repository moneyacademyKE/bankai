-record(index, {
    schema_version :: integer(),
    generation :: integer(),
    health :: aarondb@projection_index:health(),
    last_applied_offset :: integer(),
    values :: list(binary())
}).
