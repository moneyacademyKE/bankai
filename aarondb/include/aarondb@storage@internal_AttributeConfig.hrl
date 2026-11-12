-record(attribute_config, {
    unique :: boolean(),
    component :: boolean(),
    retention :: aarondb@storage@internal:retention(),
    cardinality :: aarondb@storage@internal:cardinality(),
    check :: gleam@option:option(binary()),
    composite_group :: gleam@option:option(binary()),
    layout :: aarondb@storage@internal:storage_layout(),
    tier :: aarondb@storage@internal:storage_tier(),
    eviction :: aarondb@storage@internal:eviction_policy()
}).
