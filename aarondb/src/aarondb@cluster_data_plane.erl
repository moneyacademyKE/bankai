-module(aarondb@cluster_data_plane).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/cluster_data_plane.gleam").
-export([new/2, write/4, read/4, lease/5, validate_fence/3, resume_feed/3, catch_up/1, rebuild_index/2, query_index/1, status/3]).
-export_type([state/0, error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # cluster_data_plane — committed services composed behind one node boundary\n"
    "\n"
    " This is the stateful library boundary used by a cluster runtime after Raft\n"
    " has supplied leader and quorum evidence. It never exposes a write before\n"
    " the corresponding consensus command has committed. Derived services consume\n"
    " the committed durable log and remain explicitly non-authoritative.\n"
).

-type state() :: {state,
        aarondb@consensus:state(),
        aarondb@durable_log:durable_log(),
        aarondb@projection:projection(),
        aarondb@projection_index:index(),
        aarondb@identity:recovery_state()}.

-type error() :: {write_rejected, aarondb@consensus:submit_error()} |
    {read_rejected, aarondb@consensus:read_error()} |
    {lease_rejected, aarondb@consensus:submit_error()} |
    {feed_rejected, aarondb@changefeed:changefeed_error()} |
    {projection_rejected, aarondb@projection:projection_error()} |
    {index_rejected, aarondb@projection_index:error()}.

-file("src/aarondb/cluster_data_plane.gleam", 40).
?DOC(
    " Starts a node-local data plane. Production adapters replace the initial\n"
    " single-node bootstrap with a persisted multi-voter Raft recovery image.\n"
).
-spec new(binary(), binary()) -> state().
new(Node, Source) ->
    Raft = begin
        _pipe = aarondb@raft_runtime:new(Node, [{voter, Node}]),
        aarondb@raft_runtime:bootstrap_leader(_pipe)
    end,
    Index@1 = case aarondb@projection_index:new(1) of
        {ok, Index} -> Index;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/cluster_data_plane"/utf8>>,
                        function => <<"new"/utf8>>,
                        line => 42,
                        value => _assert_fail,
                        start => 1440,
                        'end' => 1486,
                        pattern_start => 1451,
                        pattern_end => 1460})
    end,
    {state,
        aarondb@consensus:new(Raft),
        aarondb@durable_log:new(Source),
        aarondb@projection:new(<<"default"/utf8>>, 1024, 3),
        Index@1,
        aarondb@identity:clean_recovery()}.

-file("src/aarondb/cluster_data_plane.gleam", 195).
-spec ready_to_commit(aarondb@consensus:state(), integer()) -> aarondb@consensus:state().
ready_to_commit(State, Index) ->
    Previous = aarondb@raft_runtime:last_index(erlang:element(2, State)),
    case Index =:= (Previous + 1) of
        false ->
            State;

        true ->
            Rpc = {append_entries,
                erlang:element(2, erlang:element(4, erlang:element(2, State))),
                erlang:element(2, erlang:element(2, State)),
                Previous,
                aarondb@raft_runtime:last_term(erlang:element(2, State)),
                [{log_entry,
                        erlang:element(
                            2,
                            erlang:element(4, erlang:element(2, State))
                        ),
                        <<"committed"/utf8>>}],
                erlang:element(4, erlang:element(4, erlang:element(2, State)))},
            {Logged, _} = aarondb@raft_runtime:handle(
                erlang:element(2, State),
                Rpc
            ),
            {state,
                Logged,
                erlang:element(3, State),
                erlang:element(4, State),
                erlang:element(5, State)}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 55).
?DOC(
    " Applies only a quorum-committed deterministic command, then appends its\n"
    " committed audit event. Retries retain the original command result and do\n"
    " not produce another log entry.\n"
).
-spec write(state(), integer(), integer(), aarondb@command:command_request()) -> {ok,
        {state(), aarondb@command:command_result()}} |
    {error, error()}.
write(State, Index, Replicated, Request) ->
    Ready = ready_to_commit(erlang:element(2, State), Index),
    case aarondb@consensus:submit(Ready, Index, Replicated, Request) of
        {error, Error} ->
            {error, {write_rejected, Error}};

        {ok, {Consensus, Result}} ->
            {Log, _} = aarondb@durable_log:append(
                erlang:element(3, State),
                aarondb@command:replay_hash(erlang:element(3, Consensus)),
                erlang:element(2, Request)
            ),
            {ok,
                {{state,
                        Consensus,
                        Log,
                        erlang:element(4, State),
                        erlang:element(5, State),
                        erlang:element(6, State)},
                    Result}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 76).
-spec read(state(), integer(), boolean(), binary()) -> {ok,
        gleam@option:option(binary())} |
    {error, error()}.
read(State, Read_index, Quorum_confirmed, Key) ->
    case aarondb@consensus:linearizable_read(
        erlang:element(2, State),
        Read_index,
        Quorum_confirmed,
        Key
    ) of
        {ok, Value} ->
            {ok, Value};

        {error, Error} ->
            {error, {read_rejected, Error}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 95).
-spec lease(
    state(),
    integer(),
    integer(),
    integer(),
    aarondb@consensus:lease_command()
) -> {ok, {state(), gleam@option:option(aarondb@consensus:lease())}} |
    {error, error()}.
lease(State, Index, Replicated, Now, Request) ->
    Ready = ready_to_commit(erlang:element(2, State), Index),
    case aarondb@consensus:lease(Ready, Index, Replicated, Now, Request) of
        {ok, {Consensus, Lease}} ->
            {ok,
                {{state,
                        Consensus,
                        erlang:element(3, State),
                        erlang:element(4, State),
                        erlang:element(5, State),
                        erlang:element(6, State)},
                    Lease}};

        {error, Error} ->
            {error, {lease_rejected, Error}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 110).
-spec validate_fence(state(), binary(), integer()) -> {ok, nil} |
    {error, error()}.
validate_fence(State, Resource, Fence) ->
    case aarondb@consensus:validate_fence(
        erlang:element(2, State),
        Resource,
        Fence
    ) of
        {ok, nil} ->
            {ok, nil};

        {error, Error} ->
            {error, {lease_rejected, Error}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 121).
-spec resume_feed(state(), integer(), integer()) -> {ok,
        aarondb@changefeed:changefeed()} |
    {error, error()}.
resume_feed(State, Cursor, Credit) ->
    case aarondb@changefeed:resume(erlang:element(3, State), Cursor, Credit) of
        {ok, Feed} ->
            {ok, Feed};

        {error, Error} ->
            {error, {feed_rejected, Error}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 227).
-spec apply_entries(
    aarondb@projection_index:index(),
    list(aarondb@durable_log:entry())
) -> {ok, aarondb@projection_index:index()} |
    {error, aarondb@projection_index:error()}.
apply_entries(Index, Entries) ->
    case Entries of
        [] ->
            {ok, Index};

        [Entry | Rest] ->
            case aarondb@projection_index:apply(
                Index,
                erlang:element(2, Entry),
                erlang:element(3, Entry)
            ) of
                {error, Error} ->
                    {error, Error};

                {ok, Next} ->
                    apply_entries(Next, Rest)
            end
    end.

-file("src/aarondb/cluster_data_plane.gleam", 215).
-spec rebuild_from_log(
    aarondb@projection_index:index(),
    aarondb@durable_log:durable_log(),
    integer()
) -> {ok, aarondb@projection_index:index()} |
    {error, aarondb@projection_index:error()}.
rebuild_from_log(Index, Log, Cursor) ->
    case aarondb@durable_log:scan_after(Log, Cursor) of
        {error, _} ->
            {ok,
                aarondb@projection_index:degrade(
                    Index,
                    <<"committed source unavailable"/utf8>>
                )};

        {ok, Entries} ->
            apply_entries(Index, Entries)
    end.

-file("src/aarondb/cluster_data_plane.gleam", 135).
?DOC(
    " Builds both derived services from the committed source. If either boundary\n"
    " fails it remains visibly behind/degraded instead of answering from partial\n"
    " state.\n"
).
-spec catch_up(state()) -> {ok, state()} | {error, error()}.
catch_up(State) ->
    case aarondb@projection:catch_up(
        erlang:element(4, State),
        erlang:element(3, State)
    ) of
        {error, Error} ->
            {error, {projection_rejected, Error}};

        {ok, {Projection, Log}} ->
            case rebuild_from_log(erlang:element(5, State), Log, -1) of
                {error, Error@1} ->
                    {error, {index_rejected, Error@1}};

                {ok, Index} ->
                    {ok,
                        {state,
                            erlang:element(2, State),
                            Log,
                            Projection,
                            Index,
                            erlang:element(6, State)}}
            end
    end.

-file("src/aarondb/cluster_data_plane.gleam", 147).
-spec rebuild_index(state(), integer()) -> {ok, state()} | {error, error()}.
rebuild_index(State, Schema_version) ->
    case aarondb@projection_index:begin_rebuild(
        erlang:element(5, State),
        Schema_version
    ) of
        {error, Error} ->
            {error, {index_rejected, Error}};

        {ok, Building} ->
            case rebuild_from_log(Building, erlang:element(3, State), -1) of
                {error, Error@1} ->
                    {error, {index_rejected, Error@1}};

                {ok, Replacement} ->
                    case aarondb@projection_index:swap(
                        erlang:element(5, State),
                        Replacement,
                        erlang:element(3, erlang:element(3, State)) - 1
                    ) of
                        {error, Error@2} ->
                            {error, {index_rejected, Error@2}};

                        {ok, Index} ->
                            {ok,
                                {state,
                                    erlang:element(2, State),
                                    erlang:element(3, State),
                                    erlang:element(4, State),
                                    Index,
                                    erlang:element(6, State)}}
                    end
            end
    end.

-file("src/aarondb/cluster_data_plane.gleam", 171).
-spec query_index(state()) -> {ok, list(binary())} | {error, error()}.
query_index(State) ->
    case aarondb@projection_index:'query'(erlang:element(5, State)) of
        {ok, Values} ->
            {ok, Values};

        {error, Error} ->
            {error, {index_rejected, Error}}
    end.

-file("src/aarondb/cluster_data_plane.gleam", 178).
-spec status(state(), integer(), integer()) -> aarondb@operations:status().
status(State, Acknowledged, Follower_match_index) ->
    aarondb@operations:status(
        erlang:element(2, erlang:element(2, State)),
        (aarondb@raft_runtime:quorum(
            erlang:element(2, erlang:element(2, State))
        )
        * 2)
        - 1,
        Acknowledged,
        Follower_match_index,
        aarondb@projection:status(
            erlang:element(4, State),
            erlang:element(3, State)
        ),
        erlang:element(5, State),
        erlang:element(2, State),
        erlang:element(6, State)
    ).
