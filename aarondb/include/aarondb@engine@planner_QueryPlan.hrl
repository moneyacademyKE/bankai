-record(query_plan, {
    'query' :: aarondb@shared@ast:'query'(),
    clauses :: list(aarondb@shared@ast:body_clause()),
    aggregates :: gleam@dict:dict(binary(), aarondb@shared@ast:agg_func())
}).
