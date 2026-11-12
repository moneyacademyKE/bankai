-record(temporal, {
    type_ :: aarondb@shared@ast:temporal_type(),
    time :: integer(),
    op :: aarondb@shared@ast:temporal_op(),
    variable :: binary(),
    entity :: aarondb@shared@ast:part(),
    clauses :: list(aarondb@shared@ast:body_clause())
}).
