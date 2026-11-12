-record(hnsw_config, {
    max_neighbors :: integer(),
    search_budget :: integer(),
    level_source :: aarondb@vec_index:level_source()
}).
