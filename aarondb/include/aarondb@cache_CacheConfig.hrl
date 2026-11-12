-record(cache_config, {
    max_size :: integer(),
    invalidator :: fun((aarondb@fact:datom(), any()) -> boolean())
}).
