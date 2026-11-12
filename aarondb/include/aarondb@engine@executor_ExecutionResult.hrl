-record(execution_result, {
    rows :: list(gleam@dict:dict(binary(), aarondb@fact:value())),
    store :: gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))
}).
