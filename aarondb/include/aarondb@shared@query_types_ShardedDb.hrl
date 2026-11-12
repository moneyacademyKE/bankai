-record(sharded_db, {
    shards :: gleam@dict:dict(integer(), any()),
    shard_count :: integer(),
    cluster_id :: binary(),
    shard_map :: aarondb@shared@query_types:shard_map()
}).
