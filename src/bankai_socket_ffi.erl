%% Native UNIX-domain-socket transport for the bankai daemon.
%%
%% gleam_erlang does not expose gen_tcp, so these thin FFI shims back the
%% daemon's warm path: a resident process that answers JSON-RPC requests over
%% .bankai/bankai.sock without paying the BEAM cold-start cost of single-shot
%% `gleam run` on every command.
%%
%% Uses {packet, line} framing: gen_tcp strips/attaches newlines, so recv_line
%% returns a single line without the trailing newline and send_data callers
%% append "\n". {ok,_}/{error,_} tuples map directly onto gleam's Result.

-module(bankai_socket_ffi).
-export([
    listen/1,
    accept/1,
    recv_line/1,
    send_data/2,
    close_s/1,
    connect/1,
    delete_path/1,
    socket_exists/1,
    controlling_process/2
]).

%% Listen on a UNIX-domain socket at Path. Removes any stale socket file first.
listen(Path) ->
    file:delete(Path),
    gen_tcp:listen(0, [
        {ifaddr, {local, Path}},
        {packet, line},
        {active, false},
        {reuseaddr, false}
    ]).

accept(ListenSocket) ->
    gen_tcp:accept(ListenSocket).

%% One framed line, with the trailing CR/LF stripped. gen_tcp {packet, line}
%% includes the terminator on this OTP version; gleam_json's ffi raises (does
%% not return Error) on trailing bytes, so we guarantee a clean line here.
%% BUG-07: guard on is_binary so we don't rely on iolist_to_binary being a
%% no-op on binaries (idempotent today, fragile if recv ever returns a list).
recv_line(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} when is_binary(Data) -> {ok, strip_eol(Data)};
        {ok, Data} -> {ok, strip_eol(iolist_to_binary(Data))};
        Err -> Err
    end.

strip_eol(<<>>) ->
    <<>>;
strip_eol(B) ->
    Size = byte_size(B),
    case binary:at(B, Size - 1) of
        10 ->
            %% trailing "\n"; also peel a preceding "\r"
            case Size >= 2 andalso binary:at(B, Size - 2) of
                13 -> binary:part(B, 0, Size - 2);
                _ -> binary:part(B, 0, Size - 1)
            end;
        _ ->
            B
    end.

send_data(Socket, Data) ->
    gen_tcp:send(Socket, Data).

close_s(Socket) ->
    gen_tcp:close(Socket),
    nil.

%% BUG-05: hand socket control to the handler process so its lifetime + close
%% signals are tied to it (the acceptor is the default owner after accept).
controlling_process(Socket, Pid) ->
    gen_tcp:controlling_process(Socket, Pid).

%% Client connect to an existing UNIX-domain socket.
connect(Path) ->
    gen_tcp:connect({local, Path}, 0, [{packet, line}, {active, false}]).

%% Idempotently remove a socket/path file. Always returns nil (gleam Nil).
delete_path(Path) ->
    file:delete(Path),
    nil.

%% True iff a socket file currently exists at Path.
socket_exists(Path) ->
    case file:read_file_info(Path) of
        {ok, _} -> true;
        {error, _} -> false
    end.
