-record(query_result, {
    rows :: list(gleam@dict:dict(binary(), aarondb@fact:value())),
    metadata :: aarondb@shared@query_types:query_metadata(),
    updated_columnar_store :: gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))
}).
