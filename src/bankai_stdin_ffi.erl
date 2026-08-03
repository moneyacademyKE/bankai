-module(bankai_stdin_ffi).
-export([read_line/0]).

%% G11 — MCP stdio transport: read one newline-delimited JSON-RPC message from
%% stdin (io:get_line includes the trailing newline). {error, eof} at end of
%% input, which terminates the serve loop.
read_line() ->
    case io:get_line("") of
        eof -> {error, eof};
        {error, _} -> {error, eof};
        Line -> {ok, Line}
    end.
