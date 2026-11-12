-record(pull, {
    variable :: binary(),
    entity :: aarondb@shared@ast:part(),
    pattern :: list(aarondb@shared@ast:pull_item())
}).
