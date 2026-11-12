-record('query', {
    find :: list(binary()),
    where :: list(aarondb@shared@ast:body_clause()),
    order_by :: gleam@option:option(aarondb@shared@ast:order_by()),
    limit :: gleam@option:option(integer()),
    offset :: gleam@option:option(integer())
}).
