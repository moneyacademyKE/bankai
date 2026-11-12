-record(operations, {
    config :: aarondb@shared@state:config(),
    query_history :: list(aarondb@shared@state:query_context())
}).
