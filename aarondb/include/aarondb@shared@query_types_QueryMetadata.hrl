-record(query_metadata, {
    tx_id :: gleam@option:option(integer()),
    valid_time :: gleam@option:option(integer()),
    execution_time_ms :: integer(),
    index_hits :: integer(),
    plan :: binary(),
    shard_id :: gleam@option:option(integer()),
    aggregates :: gleam@dict:dict(binary(), aarondb@shared@ast:agg_func())
}).
