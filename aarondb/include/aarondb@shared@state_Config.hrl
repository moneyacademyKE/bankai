-record(config, {
    parallel_threshold :: integer(),
    batch_size :: integer(),
    prefetch_enabled :: boolean(),
    zero_copy_threshold :: integer()
}).
