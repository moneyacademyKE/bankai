-record(json_rpc_response, {
    jsonrpc :: binary(),
    id :: gleam@option:option(binary()),
    result :: gleam@option:option(gleam@json:json()),
    error :: gleam@option:option(aarondb@mcp@server:json_rpc_error())
}).
