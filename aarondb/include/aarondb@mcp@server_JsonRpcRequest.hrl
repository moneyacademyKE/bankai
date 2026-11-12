-record(json_rpc_request, {
    jsonrpc :: binary(),
    id :: gleam@option:option(binary()),
    method :: binary(),
    params :: gleam@option:option(gleam@dynamic:dynamic_())
}).
