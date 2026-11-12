-record(custom_index, {
    variable :: binary(),
    index_name :: binary(),
    'query' :: aarondb@shared@ast:index_query(),
    threshold :: float()
}).
