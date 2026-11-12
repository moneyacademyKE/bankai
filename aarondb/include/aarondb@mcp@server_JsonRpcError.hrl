-record(json_rpc_error, {
    code :: integer(),
    message :: binary(),
    data :: gleam@option:option(gleam@json:json())
}).
