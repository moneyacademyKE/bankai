-record(partial, {
    result :: aarondb@shared@query_types:query_result(),
    unavailable :: list(integer()),
    timed_out :: list({integer(), integer()})
}).
