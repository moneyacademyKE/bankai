-record(shortest_path, {
    from :: aarondb@shared@ast:part(),
    to :: aarondb@shared@ast:part(),
    edge :: binary(),
    path_var :: binary(),
    cost_var :: gleam@option:option(binary()),
    max_depth :: gleam@option:option(integer())
}).
