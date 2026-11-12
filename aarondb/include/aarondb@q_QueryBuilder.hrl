-record(query_builder, {
    find :: list(binary()),
    clauses :: list(aarondb@shared@ast:body_clause()),
    order_by :: gleam@option:option(aarondb@shared@ast:order_by()),
    limit :: gleam@option:option(integer()),
    offset :: gleam@option:option(integer())
}).
