-record(subscribe, {
    'query' :: aarondb@shared@ast:'query'(),
    attributes :: list(binary()),
    subscriber :: gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()),
    initial_state :: aarondb@shared@query_types:query_result()
}).
