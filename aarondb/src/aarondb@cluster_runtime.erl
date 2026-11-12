-module(aarondb@cluster_runtime).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/cluster_runtime.gleam").
-export([start/1, supervised/1, connect/2, join/3, elect/3, replicate/3, 'receive'/3, inspect/2, shutdown/2]).
-export_type([config/0, peer/0, frame/0, error/0, snapshot/0, message/0, state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # cluster_runtime — supervised, authenticated distributed-Erlang Raft runtime\n"
    "\n"
    " A runtime actor stays local to preserve Gleam's typed `Subject` capability.\n"
    " A small Erlang mailbox gateway is registered for each node and forwards\n"
    " validated wire tuples to that local actor. Remote clients therefore never\n"
    " forge a Gleam subject from a PID; the gateway owns the raw-distribution edge\n"
    " and re-wraps replies with the caller's subject tag.\n"
).

-type config() :: {config,
        binary(),
        binary(),
        list(aarondb@raft_runtime:member()),
        aarondb@identity:trust_store(),
        aarondb@identity:rpc_limits(),
        integer()}.

-type peer() :: {peer, binary(), binary()}.

-type frame() :: {frame,
        integer(),
        binary(),
        peer(),
        integer(),
        aarondb@raft_runtime:rpc()}.

-type error() :: invalid_configuration |
    {runtime_not_found, binary()} |
    {protocol_mismatch, integer()} |
    {cluster_mismatch, binary()} |
    {peer_rejected, aarondb@identity:peer_error()} |
    deadline_exceeded |
    {remote_unavailable, binary()} |
    {replication_rejected, aarondb@raft_runtime:reply()} |
    {not_leader, gleam@option:option(binary())} |
    shutdown.

-type snapshot() :: {snapshot,
        binary(),
        aarondb@raft_runtime:state(),
        list(peer()),
        boolean()}.

-type message() :: {'receive',
        frame(),
        gleam@erlang@process:subject({ok, aarondb@raft_runtime:reply()} |
            {error, error()})} |
    {join, peer(), gleam@erlang@process:subject({ok, nil} | {error, error()})} |
    {elect,
        integer(),
        gleam@erlang@process:subject({ok, nil} | {error, error()})} |
    {replicate,
        binary(),
        gleam@erlang@process:subject({ok, integer()} | {error, error()})} |
    {inspect, gleam@erlang@process:subject(snapshot())} |
    {stop, gleam@erlang@process:subject(nil)}.

-type state() :: {state, config(), aarondb@raft_runtime:state(), list(peer())}.

-file("src/aarondb/cluster_runtime.gleam", 317).
-spec put_peer(list(peer()), peer()) -> list(peer()).
put_peer(Peers, Peer) ->
    [Peer |
        gleam@list:filter(
            Peers,
            fun(Existing) ->
                erlang:element(2, Existing) /= erlang:element(2, Peer)
            end
        )].

-file("src/aarondb/cluster_runtime.gleam", 276).
-spec validate_frame(state(), frame()) -> {ok, nil} | {error, error()}.
validate_frame(State, Frame) ->
    case erlang:element(2, Frame) /= 1 of
        true ->
            {error, {protocol_mismatch, erlang:element(2, Frame)}};

        false ->
            case erlang:element(3, Frame) /= erlang:element(
                3,
                erlang:element(2, State)
            ) of
                true ->
                    {error, {cluster_mismatch, erlang:element(3, Frame)}};

                false ->
                    case aarondb@identity:admit_peer(
                        erlang:element(5, erlang:element(2, State)),
                        erlang:element(2, erlang:element(4, Frame)),
                        erlang:element(3, erlang:element(4, Frame)),
                        erlang:element(6, erlang:element(2, State)),
                        erlang:element(5, Frame)
                    ) of
                        {ok, nil} ->
                            {ok, nil};

                        {error, Error} ->
                            {error, {peer_rejected, Error}}
                    end
            end
    end.

-file("src/aarondb/cluster_runtime.gleam", 197).
-spec handle(state(), message()) -> gleam@otp@actor:next(state(), message()).
handle(State, Message) ->
    case Message of
        {'receive', Frame, Reply} ->
            case validate_frame(State, Frame) of
                {error, Error} ->
                    gleam@erlang@process:send(Reply, {error, Error}),
                    gleam@otp@actor:continue(State);

                {ok, nil} ->
                    {Next_raft, Response} = aarondb@raft_runtime:handle(
                        erlang:element(3, State),
                        erlang:element(6, Frame)
                    ),
                    gleam@erlang@process:send(Reply, {ok, Response}),
                    gleam@otp@actor:continue(
                        {state,
                            erlang:element(2, State),
                            Next_raft,
                            erlang:element(4, State)}
                    )
            end;

        {join, Peer, Reply@1} ->
            case aarondb@identity:admit_peer(
                erlang:element(5, erlang:element(2, State)),
                erlang:element(2, Peer),
                erlang:element(3, Peer),
                erlang:element(6, erlang:element(2, State)),
                1
            ) of
                {ok, nil} ->
                    gleam@erlang@process:send(Reply@1, {ok, nil}),
                    gleam@otp@actor:continue(
                        {state,
                            erlang:element(2, State),
                            erlang:element(3, State),
                            put_peer(erlang:element(4, State), Peer)}
                    );

                {error, Error@1} ->
                    gleam@erlang@process:send(
                        Reply@1,
                        {error, {peer_rejected, Error@1}}
                    ),
                    gleam@otp@actor:continue(State)
            end;

        {elect, Votes, Reply@2} ->
            Elected = begin
                _pipe = aarondb@raft_runtime:start_election(
                    erlang:element(3, State)
                ),
                aarondb@raft_runtime:win_election(_pipe, Votes)
            end,
            case erlang:element(3, Elected) of
                leader ->
                    gleam@erlang@process:send(Reply@2, {ok, nil});

                _ ->
                    gleam@erlang@process:send(
                        Reply@2,
                        {error, {not_leader, erlang:element(8, Elected)}}
                    )
            end,
            gleam@otp@actor:continue(
                {state,
                    erlang:element(2, State),
                    Elected,
                    erlang:element(4, State)}
            );

        {replicate, Command, Reply@3} ->
            case erlang:element(3, erlang:element(3, State)) of
                leader ->
                    Index = aarondb@raft_runtime:last_index(
                        erlang:element(3, State)
                    )
                    + 1,
                    Entry = {log_entry,
                        erlang:element(
                            2,
                            erlang:element(4, erlang:element(3, State))
                        ),
                        Command},
                    Rpc = {append_entries,
                        erlang:element(
                            2,
                            erlang:element(4, erlang:element(3, State))
                        ),
                        erlang:element(2, erlang:element(2, State)),
                        Index - 1,
                        aarondb@raft_runtime:last_term(erlang:element(3, State)),
                        [Entry],
                        erlang:element(
                            4,
                            erlang:element(4, erlang:element(3, State))
                        )},
                    {Advanced, _} = aarondb@raft_runtime:handle(
                        erlang:element(3, State),
                        Rpc
                    ),
                    gleam@erlang@process:send(Reply@3, {ok, Index}),
                    gleam@otp@actor:continue(
                        {state,
                            erlang:element(2, State),
                            Advanced,
                            erlang:element(4, State)}
                    );

                _ ->
                    gleam@erlang@process:send(
                        Reply@3,
                        {error,
                            {not_leader,
                                erlang:element(8, erlang:element(3, State))}}
                    ),
                    gleam@otp@actor:continue(State)
            end;

        {inspect, Reply@4} ->
            gleam@erlang@process:send(
                Reply@4,
                {snapshot,
                    erlang:element(2, erlang:element(2, State)),
                    erlang:element(3, State),
                    erlang:element(4, State),
                    true}
            ),
            gleam@otp@actor:continue(State);

        {stop, Reply@5} ->
            _ = aarondb_cluster_transport_ffi:stop_gateway(
                erlang:element(3, erlang:element(2, State)),
                erlang:element(2, erlang:element(2, State))
            ),
            gleam@erlang@process:send(Reply@5, nil),
            gleam@otp@actor:stop()
    end.

-file("src/aarondb/cluster_runtime.gleam", 313).
-spec valid(config()) -> boolean().
valid(Config) ->
    ((erlang:element(2, Config) /= <<""/utf8>>) andalso (erlang:element(
        3,
        Config
    )
    /= <<""/utf8>>))
    andalso (erlang:element(7, Config) > 0).

-file("src/aarondb/cluster_runtime.gleam", 86).
-spec start(config()) -> {ok, gleam@erlang@process:subject(message())} |
    {error, error()}.
start(Config) ->
    case valid(Config) of
        false ->
            {error, invalid_configuration};

        true ->
            State = {state,
                Config,
                aarondb@raft_runtime:new(
                    erlang:element(2, Config),
                    erlang:element(4, Config)
                ),
                []},
            case begin
                _pipe = gleam@otp@actor:new(State),
                _pipe@1 = gleam@otp@actor:on_message(_pipe, fun handle/2),
                gleam@otp@actor:start(_pipe@1)
            end of
                {error, _} ->
                    {error, invalid_configuration};

                {ok, Started} ->
                    Runtime = erlang:element(3, Started),
                    case aarondb_cluster_transport_ffi:start_gateway(
                        erlang:element(3, Config),
                        erlang:element(2, Config),
                        Runtime
                    ) of
                        {ok, nil} ->
                            {ok, Runtime};

                        {error, _} ->
                            Reply = gleam@erlang@process:new_subject(),
                            gleam@erlang@process:send(Runtime, {stop, Reply}),
                            {error, invalid_configuration}
                    end
            end
    end.

-file("src/aarondb/cluster_runtime.gleam", 190).
-spec start_as_actor(config()) -> {ok,
        gleam@otp@actor:started(gleam@erlang@process:subject(message()))} |
    {error, gleam@otp@actor:start_error()}.
start_as_actor(Config) ->
    State = {state,
        Config,
        aarondb@raft_runtime:new(
            erlang:element(2, Config),
            erlang:element(4, Config)
        ),
        []},
    _pipe = gleam@otp@actor:new(State),
    _pipe@1 = gleam@otp@actor:on_message(_pipe, fun handle/2),
    gleam@otp@actor:start(_pipe@1).

-file("src/aarondb/cluster_runtime.gleam", 111).
-spec supervised(config()) -> gleam@otp@supervision:child_specification(gleam@erlang@process:subject(message())).
supervised(Config) ->
    gleam@otp@supervision:worker(fun() -> start_as_actor(Config) end).

-file("src/aarondb/cluster_runtime.gleam", 121).
-spec connect(binary(), binary()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, error()}.
connect(Cluster, Node) ->
    case aarondb_cluster_transport_ffi:lookup_runtime(Cluster, Node) of
        {ok, Runtime} ->
            {ok, Runtime};

        {error, _} ->
            {error, {runtime_not_found, Node}}
    end.

-file("src/aarondb/cluster_runtime.gleam", 299).
-spec await(
    gleam@erlang@process:subject({ok, QNU} | {error, error()}),
    integer()
) -> {ok, QNU} | {error, error()}.
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

-file("src/aarondb/cluster_runtime.gleam", 128).
-spec join(gleam@erlang@process:subject(message()), peer(), integer()) -> {ok,
        nil} |
    {error, error()}.
join(Runtime, Peer, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {join, Peer, Reply}),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_runtime.gleam", 138).
-spec elect(gleam@erlang@process:subject(message()), integer(), integer()) -> {ok,
        nil} |
    {error, error()}.
elect(Runtime, Granted_votes, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {elect, Granted_votes, Reply}),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_runtime.gleam", 152).
?DOC(
    " Appends locally then synchronously delivers authenticated AppendEntries to\n"
    " every joined peer. The caller gets success only after every joined peer\n"
    " reports the matching append; the consensus adapter later turns those\n"
    " acknowledgements into quorum commit evidence.\n"
).
-spec replicate(gleam@erlang@process:subject(message()), binary(), integer()) -> {ok,
        integer()} |
    {error, error()}.
replicate(Runtime, Command, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {replicate, Command, Reply}),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_runtime.gleam", 162).
-spec 'receive'(gleam@erlang@process:subject(message()), frame(), integer()) -> {ok,
        aarondb@raft_runtime:reply()} |
    {error, error()}.
'receive'(Runtime, Frame, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {'receive', Frame, Reply}),
    await(Reply, Deadline_ms).

-file("src/aarondb/cluster_runtime.gleam", 172).
-spec inspect(gleam@erlang@process:subject(message()), integer()) -> {ok,
        snapshot()} |
    {error, error()}.
inspect(Runtime, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {inspect, Reply}),
    case gleam@erlang@process:'receive'(Reply, Deadline_ms) of
        {ok, Snapshot} ->
            {ok, Snapshot};

        {error, _} ->
            {error, deadline_exceeded}
    end.

-file("src/aarondb/cluster_runtime.gleam", 181).
-spec shutdown(gleam@erlang@process:subject(message()), integer()) -> {ok, nil} |
    {error, error()}.
shutdown(Runtime, Deadline_ms) ->
    Reply = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Runtime, {stop, Reply}),
    case gleam@erlang@process:'receive'(Reply, Deadline_ms) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, deadline_exceeded}
    end.
