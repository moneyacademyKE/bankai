-module(aarondb@mcp@stdio).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/mcp/stdio.gleam").
-export([parse_request/1, serve_line/2, serve/1, main/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # mcp/stdio — local MCP stdio transport\n"
    "\n"
    " Runs the supported MCP surface as newline-delimited JSON-RPC over stdin and\n"
    " stdout. stdout carries protocol responses only; diagnostics use stderr.\n"
    "\n"
    " ## Lifecycle and flow control\n"
    "\n"
    " This is a local child-process adapter. It accepts one complete line, handles\n"
    " it synchronously, writes at most one response, then reads the next line.\n"
    " There is no request queue, concurrent execution, or partial-result mode: a\n"
    " slow tool call applies backpressure through stdin. EOF is the supported\n"
    " shutdown signal. `notifications/initialized` and\n"
    " `notifications/cancelled` are accepted notifications and deliberately write\n"
    " no response. Cancellation cannot interrupt an already-running synchronous\n"
    " call; hosts should stop the child process if they need hard cancellation.\n"
).

-file("src/aarondb/mcp/stdio.gleam", 71).
-spec malformed_request() -> aarondb@mcp@server:json_rpc_response().
malformed_request() ->
    {json_rpc_response,
        <<"2.0"/utf8>>,
        none,
        none,
        {some, {json_rpc_error, -32700, <<"Parse error"/utf8>>, none}}}.

-file("src/aarondb/mcp/stdio.gleam", 80).
-spec parse_request(binary()) -> {ok, aarondb@mcp@server:json_rpc_request()} |
    {error, gleam@json:decode_error()}.
parse_request(Line) ->
    Request_decoder = begin
        gleam@dynamic@decode:field(
            <<"jsonrpc"/utf8>>,
            {decoder, fun gleam@dynamic@decode:decode_string/1},
            fun(Jsonrpc) ->
                gleam@dynamic@decode:optional_field(
                    <<"id"/utf8>>,
                    none,
                    gleam@dynamic@decode:optional(
                        {decoder, fun gleam@dynamic@decode:decode_string/1}
                    ),
                    fun(Id) ->
                        gleam@dynamic@decode:field(
                            <<"method"/utf8>>,
                            {decoder, fun gleam@dynamic@decode:decode_string/1},
                            fun(Method) ->
                                gleam@dynamic@decode:optional_field(
                                    <<"params"/utf8>>,
                                    none,
                                    gleam@dynamic@decode:optional(
                                        {decoder,
                                            fun gleam@dynamic@decode:decode_dynamic/1}
                                    ),
                                    fun(Params) ->
                                        gleam@dynamic@decode:success(
                                            {json_rpc_request,
                                                Jsonrpc,
                                                Id,
                                                Method,
                                                Params}
                                        )
                                    end
                                )
                            end
                        )
                    end
                )
            end
        )
    end,
    gleam@json:parse(Line, Request_decoder).

-file("src/aarondb/mcp/stdio.gleam", 53).
?DOC(
    " Decode and synchronously handle one stdin line.\n"
    "\n"
    " A request produces `Some(response)`. JSON-RPC notifications intentionally\n"
    " produce `None`, including malformed notifications only when they cannot be\n"
    " identified as notifications.\n"
).
-spec serve_line(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary()
) -> gleam@option:option(aarondb@mcp@server:json_rpc_response()).
serve_line(Db, Line) ->
    case parse_request(Line) of
        {ok, Request} ->
            case erlang:element(3, Request) of
                none ->
                    _ = aarondb@mcp@server:handle_request(Db, Request),
                    none;

                {some, _} ->
                    {some, aarondb@mcp@server:handle_request(Db, Request)}
            end;

        {error, _} ->
            {some, malformed_request()}
    end.

-file("src/aarondb/mcp/stdio.gleam", 35).
-spec serve_loop(gleam@erlang@process:subject(aarondb@transactor:message())) -> nil.
serve_loop(Db) ->
    case aarondb_mcp_stdio_ffi:get_line(<<""/utf8>>) of
        {ok, Line} ->
            case serve_line(Db, Line) of
                {some, Response} ->
                    aarondb@mcp@server:send_response(Response);

                none ->
                    nil
            end,
            serve_loop(Db);

        {error, _} ->
            nil
    end.

-file("src/aarondb/mcp/stdio.gleam", 30).
?DOC(" Serve one JSON-RPC request per stdin line until EOF.\n").
-spec serve(gleam@erlang@process:subject(aarondb@transactor:message())) -> nil.
serve(Db) ->
    gleam_stdlib:println_error(
        <<"AaronDB local MCP stdio server started"/utf8>>
    ),
    serve_loop(Db).

-file("src/aarondb/mcp/stdio.gleam", 25).
?DOC(" Start a local MCP server with a fresh in-memory AaronDB instance.\n").
-spec main() -> nil.
main() ->
    _pipe = aarondb:new(),
    serve(_pipe).
