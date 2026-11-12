-module(aarondb@raft).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/raft.gleam").
-export([new/1, handle_message/3, is_leader/1, add_peer/2, remove_peer/2]).
-export_type([raft_role/0, raft_state/0, raft_effect/0, raft_message/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # raft — INACTIVE clustering scaffold (unwired stub)\n"
    "\n"
    " ⚠️ STATUS: A complete, pure, unit-tested **leader-election** state machine,\n"
    " now **unwired** from the engine. The single-node AaronDB core no longer\n"
    " holds, initialises, or drives any raft state:\n"
    "\n"
    "   - `DbState` no longer has a `raft_state` field.\n"
    "   - The transactor has no `RaftMsg` variant and never calls `handle_message`.\n"
    "   - `aarondb.is_leader` has been removed.\n"
    "\n"
    " SCOPE: This is Raft **election only**. The log-replication half\n"
    " (AppendEntries, commit index, log matching, apply) was never present, so\n"
    " it could not deliver replicated consistency on its own.\n"
    "\n"
    " The pure protocol logic is covered by `test/aarondb/raft_test`. It is\n"
    " retained as a deliberate, documented stub — a clustering seed, not active\n"
    " code. Do not partially activate it. Revival requires an approved distributed\n"
    " design with peer transport/configuration, durable state, AppendEntries/log\n"
    " replication, membership changes, quorum commit, and partition/failure tests.\n"
).

-type raft_role() :: follower | candidate | leader.

-type raft_state() :: {raft_state,
        raft_role(),
        integer(),
        gleam@option:option(gleam@erlang@process:pid_()),
        list(gleam@erlang@process:pid_()),
        integer(),
        gleam@option:option(gleam@erlang@process:pid_())}.

-type raft_effect() :: {send_heartbeat,
        gleam@erlang@process:pid_(),
        integer(),
        gleam@erlang@process:pid_()} |
    {send_vote_request,
        gleam@erlang@process:pid_(),
        integer(),
        gleam@erlang@process:pid_()} |
    {send_vote_response, gleam@erlang@process:pid_(), integer(), boolean()} |
    register_as_leader |
    unregister_as_leader |
    reset_election_timer |
    start_heartbeat_timer |
    stop_heartbeat_timer.

-type raft_message() :: {heartbeat, integer(), gleam@erlang@process:pid_()} |
    {heartbeat_response, integer(), gleam@erlang@process:pid_()} |
    {vote_request, integer(), gleam@erlang@process:pid_()} |
    {vote_response, integer(), boolean(), gleam@erlang@process:pid_()} |
    election_timeout |
    heartbeat_tick.

-file("src/aarondb/raft.gleam", 73).
?DOC(" Create a new Raft state in Follower role at term 0.\n").
-spec new(list(gleam@erlang@process:pid_())) -> raft_state().
new(Peers) ->
    {raft_state, follower, 0, none, Peers, 0, none}.

-file("src/aarondb/raft.gleam", 348).
?DOC(" Check if we have a majority of votes (> half the cluster).\n").
-spec has_majority(raft_state()) -> boolean().
has_majority(State) ->
    Cluster_size = erlang:length(erlang:element(5, State)) + 1,
    erlang:element(6, State) > (Cluster_size div 2).

-file("src/aarondb/raft.gleam", 299).
?DOC(" Handle incoming vote response.\n").
-spec handle_vote_response(
    raft_state(),
    integer(),
    boolean(),
    gleam@erlang@process:pid_()
) -> {raft_state(), list(raft_effect())}.
handle_vote_response(State, Term, Granted, _) ->
    case erlang:element(2, State) of
        candidate ->
            case (Term =:= erlang:element(3, State)) andalso Granted of
                true ->
                    New_state = {raft_state,
                        erlang:element(2, State),
                        erlang:element(3, State),
                        erlang:element(4, State),
                        erlang:element(5, State),
                        erlang:element(6, State) + 1,
                        erlang:element(7, State)},
                    case has_majority(New_state) of
                        true ->
                            Leader_state = {raft_state,
                                leader,
                                erlang:element(3, New_state),
                                erlang:element(4, New_state),
                                erlang:element(5, New_state),
                                erlang:element(6, New_state),
                                erlang:element(7, New_state)},
                            {Leader_state,
                                [register_as_leader, start_heartbeat_timer]};

                        false ->
                            {New_state, []}
                    end;

                false ->
                    case Term > erlang:element(3, State) of
                        true ->
                            New_state@1 = {raft_state,
                                follower,
                                Term,
                                none,
                                erlang:element(5, State),
                                0,
                                none},
                            {New_state@1, [reset_election_timer]};

                        false ->
                            {State, []}
                    end
            end;

        _ ->
            {State, []}
    end.

-file("src/aarondb/raft.gleam", 230).
?DOC(" Handle incoming vote request from a candidate.\n").
-spec handle_vote_request(
    raft_state(),
    integer(),
    gleam@erlang@process:pid_(),
    gleam@erlang@process:pid_()
) -> {raft_state(), list(raft_effect())}.
handle_vote_request(State, Term, Candidate, _) ->
    case Term > erlang:element(3, State) of
        true ->
            New_state = {raft_state,
                follower,
                Term,
                {some, Candidate},
                erlang:element(5, State),
                0,
                none},
            Effects = case erlang:element(2, State) of
                leader ->
                    [unregister_as_leader,
                        stop_heartbeat_timer,
                        {send_vote_response, Candidate, Term, true},
                        reset_election_timer];

                _ ->
                    [{send_vote_response, Candidate, Term, true},
                        reset_election_timer]
            end,
            {New_state, Effects};

        false ->
            case Term =:= erlang:element(3, State) of
                true ->
                    case erlang:element(4, State) of
                        none ->
                            New_state@1 = {raft_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                {some, Candidate},
                                erlang:element(5, State),
                                erlang:element(6, State),
                                erlang:element(7, State)},
                            {New_state@1,
                                [{send_vote_response, Candidate, Term, true},
                                    reset_election_timer]};

                        {some, Prev} ->
                            Granted = Prev =:= Candidate,
                            {State,
                                [{send_vote_response, Candidate, Term, Granted}]}
                    end;

                false ->
                    {State,
                        [{send_vote_response,
                                Candidate,
                                erlang:element(3, State),
                                false}]}
            end
    end.

-file("src/aarondb/raft.gleam", 203).
?DOC(" Receive a heartbeat response (leader uses this for liveness tracking).\n").
-spec handle_heartbeat_response(raft_state(), integer()) -> {raft_state(),
    list(raft_effect())}.
handle_heartbeat_response(State, Term) ->
    case Term > erlang:element(3, State) of
        true ->
            New_state = {raft_state,
                follower,
                Term,
                none,
                erlang:element(5, State),
                0,
                none},
            Effects = case erlang:element(2, State) of
                leader ->
                    [unregister_as_leader,
                        stop_heartbeat_timer,
                        reset_election_timer];

                _ ->
                    [reset_election_timer]
            end,
            {New_state, Effects};

        false ->
            {State, []}
    end.

-file("src/aarondb/raft.gleam", 172).
?DOC(" Receive a heartbeat from a leader.\n").
-spec handle_heartbeat(raft_state(), integer(), gleam@erlang@process:pid_()) -> {raft_state(),
    list(raft_effect())}.
handle_heartbeat(State, Term, Leader) ->
    case Term >= erlang:element(3, State) of
        true ->
            New_state = {raft_state,
                follower,
                Term,
                none,
                erlang:element(5, State),
                0,
                {some, Leader}},
            Effects = case erlang:element(2, State) of
                leader ->
                    [unregister_as_leader,
                        stop_heartbeat_timer,
                        reset_election_timer];

                _ ->
                    [reset_election_timer]
            end,
            {New_state, Effects};

        false ->
            {State, []}
    end.

-file("src/aarondb/raft.gleam", 154).
?DOC(" Heartbeat tick fires. Leader sends heartbeats to all peers.\n").
-spec handle_heartbeat_tick(raft_state(), gleam@erlang@process:pid_()) -> {raft_state(),
    list(raft_effect())}.
handle_heartbeat_tick(State, Self_pid) ->
    case erlang:element(2, State) of
        leader ->
            Effects = gleam@list:map(
                erlang:element(5, State),
                fun(Peer) ->
                    {send_heartbeat, Peer, erlang:element(3, State), Self_pid}
                end
            ),
            {State, Effects};

        _ ->
            {State, []}
    end.

-file("src/aarondb/raft.gleam", 108).
?DOC(" Election timeout fires. Follower or Candidate becomes Candidate for a new term.\n").
-spec handle_election_timeout(raft_state(), gleam@erlang@process:pid_()) -> {raft_state(),
    list(raft_effect())}.
handle_election_timeout(State, Self_pid) ->
    case erlang:element(2, State) of
        leader ->
            {State, []};

        _ ->
            New_term = erlang:element(3, State) + 1,
            New_state = {raft_state,
                candidate,
                New_term,
                {some, Self_pid},
                erlang:element(5, State),
                1,
                none},
            Vote_effects = gleam@list:map(
                erlang:element(5, State),
                fun(Peer) -> {send_vote_request, Peer, New_term, Self_pid} end
            ),
            case has_majority(New_state) of
                true ->
                    Leader_state = {raft_state,
                        leader,
                        erlang:element(3, New_state),
                        erlang:element(4, New_state),
                        erlang:element(5, New_state),
                        erlang:element(6, New_state),
                        erlang:element(7, New_state)},
                    Effects = lists:append(
                        Vote_effects,
                        [register_as_leader, start_heartbeat_timer]
                    ),
                    {Leader_state, Effects};

                false ->
                    {New_state,
                        lists:append(Vote_effects, [reset_election_timer])}
            end
    end.

-file("src/aarondb/raft.gleam", 88).
?DOC(
    " Process a Raft message and return the new state + effects.\n"
    " This is the ONLY entry point. It is pure — no side effects.\n"
).
-spec handle_message(raft_state(), raft_message(), gleam@erlang@process:pid_()) -> {raft_state(),
    list(raft_effect())}.
handle_message(State, Msg, Self_pid) ->
    case Msg of
        election_timeout ->
            handle_election_timeout(State, Self_pid);

        heartbeat_tick ->
            handle_heartbeat_tick(State, Self_pid);

        {heartbeat, Term, Leader} ->
            handle_heartbeat(State, Term, Leader);

        {heartbeat_response, Term@1, _} ->
            handle_heartbeat_response(State, Term@1);

        {vote_request, Term@2, Candidate} ->
            handle_vote_request(State, Term@2, Candidate, Self_pid);

        {vote_response, Term@3, Granted, _} ->
            handle_vote_response(State, Term@3, Granted, Self_pid)
    end.

-file("src/aarondb/raft.gleam", 355).
?DOC(" Check if this node is the current leader.\n").
-spec is_leader(raft_state()) -> boolean().
is_leader(State) ->
    erlang:element(2, State) =:= leader.

-file("src/aarondb/raft.gleam", 360).
?DOC(" Add a peer to the cluster.\n").
-spec add_peer(raft_state(), gleam@erlang@process:pid_()) -> raft_state().
add_peer(State, Peer) ->
    {raft_state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        [Peer | erlang:element(5, State)],
        erlang:element(6, State),
        erlang:element(7, State)}.

-file("src/aarondb/raft.gleam", 365).
?DOC(" Remove a peer from the cluster.\n").
-spec remove_peer(raft_state(), gleam@erlang@process:pid_()) -> raft_state().
remove_peer(State, Peer) ->
    {raft_state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        gleam@list:filter(erlang:element(5, State), fun(P) -> P /= Peer end),
        erlang:element(6, State),
        erlang:element(7, State)}.
