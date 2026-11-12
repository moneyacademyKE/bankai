-record(vec_index, {
    nodes :: gleam@dict:dict(aarondb@fact:entity_id(), list(float())),
    layers :: gleam@dict:dict(integer(), aarondb@vec_index:layer()),
    dimensions :: gleam@option:option(integer()),
    config :: aarondb@vec_index:hnsw_config(),
    entry_point :: {ok, aarondb@fact:entity_id()} | {error, nil},
    max_level :: integer()
}).
