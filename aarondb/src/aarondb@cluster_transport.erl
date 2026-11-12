-module(aarondb@cluster_transport).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/cluster_transport.gleam").
-export([connect/2, 'receive'/3, join/3, elect/3, replicate/3, inspect/2, shutdown/2]).
-export_type([remote_runtime/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # cluster_transport — correlation-safe remote bridge for cluster runtimes\n"
    "\n"
    " `cluster_runtime.Runtime` is a local Gleam actor capability. It cannot be\n"
    " reconstructed from a remote BEAM PID because Gleam deliberately tags\n"
    " subjects. This module keeps that capability boundary intact: it exposes a\n"
    " separate remote handle and sends each request with a reply `Subject` created\n"
    " by the caller, preserving Gleam's actor capability tag across the wire.\n"
    "\n"
    " The bridge has no TCP fallback. Cross-node calls require an already connected\n"
    " BEAM distribution channel; operators must configure authenticated TLS\n"
    " distribution before a remote handle is admitted.\n"
).

-opaque remote_runtime() :: {remote_runtime, gleam@erlang@process:pid_()}.

-file("src/aarondb/cluster_transport.gleam", 150).
-spec registry_name(binary(), binary()) -> binary().
registry_name(Cluster, Node) ->
    <<<<<<"aarondb.cluster."/utf8, Cluster/binary>>/binary, "."/utf8>>/binary,
        Node/binary>>.

-file("src/aarondb/cluster_transport.gleam", 22).
-spec connect(binary(), binary()) -> {ok, remote_runtime()} |
    {error, aarondb@cluster_runtime:error()}.
connect(Cluster, Node) ->
    case aarondb_global_ffi:whereis(registry_name(Cluster, Node)) of
        {ok, Pid} ->
            {ok, {remote_runtime, Pid}};

        {error, _} ->
            {error, {runtime_not_found, Node}}
    end.

-file("src/aarondb/cluster_transport.gleam", 136).
-spec await(
    gleam@erlang@process:subject({ok, QWO} |
        {error, aarondb@cluster_runtime:error()}),
    integer()
) -> {ok, QWO} | {error, aarondb@cluster_runtime:error()}.
await(Reply, Deadline_ms) ->
    case Deadline_ms > 0 of
        false ->
            {error, deadline_exceeded};

        true ->
            case gleam@erlang@process:'receive'(Reply, Deadline_ms) of
                {ok, Result} ->
                    Result;

                {error, _} ->
                    {error, deadline_exceeded}
            end
    end.

-file("src/aarondb/cluster_transport.gleam", 32).
-spec 'receive'(remote_runtime(), aarondb@cluster_runtime:frame(), integer()) -> {ok,
        aarondb@raft_runtime:reply()} |
    {error, aarondb@cluster_runtime:error()}.
'receive'(Runtime, Frame, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:receive_frame(Pid, Frame, Reply),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_transport.gleam", 43).
-spec join(remote_runtime(), aarondb@cluster_runtime:peer(), integer()) -> {ok,
        nil} |
    {error, aarondb@cluster_runtime:error()}.
join(Runtime, Peer, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:join_peer(Pid, Peer, Reply),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_transport.gleam", 54).
-spec elect(remote_runtime(), integer(), integer()) -> {ok, nil} |
    {error, aarondb@cluster_runtime:error()}.
elect(Runtime, Granted_votes, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:elect_leader(Pid, Granted_votes, Reply),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_transport.gleam", 65).
-spec replicate(remote_runtime(), binary(), integer()) -> {ok, integer()} |
    {error, aarondb@cluster_runtime:error()}.
replicate(Runtime, Command, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:replicate_command(Pid, Command, Reply),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_transport.gleam", 76).
-spec inspect(remote_runtime(), integer()) -> {ok,
        aarondb@cluster_runtime:snapshot()} |
    {error, aarondb@cluster_runtime:error()}.
inspect(Runtime, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:inspect_runtime(Pid, Reply),
    case gleam@erlang@process:'receive'(Reply, Deadline_ms) of
        {ok, Snapshot} ->
            {ok, Snapshot};

        {error, _} ->
            {error, deadline_exceeded}
    end.

-file("src/aarondb/cluster_transport.gleam", 89).
-spec shutdown(remote_runtime(), integer()) -> {ok, nil} |
    {error, aarondb@cluster_runtime:error()}.
shutdown(Runtime, Deadline_ms) ->
    {remote_runtime, Pid} = Runtime,
    Reply = gleam@erlang@process:new_subject(),
    aarondb_cluster_transport_ffi:stop_runtime(Pid, Reply),
    case gleam@erlang@process:'receive'(Reply, Deadline_ms) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, deadline_exceeded}
    end.
