-record(attribute_config, {
    unique :: boolean(),
    component :: boolean(),
    retention :: aarondb@fact:retention(),
    cardinality :: aarondb@fact:cardinality(),
    check :: gleam@option:option(binary()),
    composite_group :: gleam@option:option(binary()),
    layout :: aarondb@fact:storage_layout(),
    tier :: aarondb@fact:storage_tier(),
    eviction :: aarondb@fact:eviction_policy()
}).
