-record(query_succeeded, {
    shard_id :: integer(),
    result :: aarondb@shared@query_types:query_result()
}).
