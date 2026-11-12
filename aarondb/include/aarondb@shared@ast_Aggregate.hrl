-record(aggregate, {
    variable :: binary(),
    func :: aarondb@shared@ast:agg_func(),
    target :: aarondb@shared@ast:part(),
    filter :: list(aarondb@shared@ast:body_clause())
}).
