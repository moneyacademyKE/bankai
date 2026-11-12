-module(aarondb@consensus).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/consensus.gleam").
-export([new/1, submit/4, linearizable_read/4, lease/5, validate_fence/3]).
-export_type([lease/0, lease_command/0, submit_error/0, read_error/0, state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # consensus — leader-gated command and lease reference surface\n"
    "\n"
    " This module composes committed Raft positions with the deterministic command\n"
    " state machine. It is deliberately transport-free: callers supply quorum\n"
    " evidence and a monotonic clock reading. No wall-clock conversion is trusted.\n"
).

-type lease() :: {lease, binary(), binary(), integer(), integer()}.

-type lease_command() :: {acquire, binary(), binary(), integer()} |
    {renew, binary(), binary(), integer(), integer()} |
    {revoke, binary(), binary(), integer()}.

-type submit_error() :: {redirect, gleam@option:option(binary())} |
    quorum_unavailable |
    not_committed |
    {command_failed, aarondb@command:command_error()} |
    {invalid_clock, integer(), integer()} |
    invalid_ttl |
    {lease_held, binary(), integer(), integer()} |
    {stale_fence, binary(), integer(), integer()} |
    {lease_holder_mismatch, binary()}.

-type read_error() :: {read_redirect, gleam@option:option(binary())} |
    read_quorum_unavailable |
    read_index_unavailable.

-type state() :: {state,
        aarondb@raft_runtime:state(),
        aarondb@command:state(),
        list(lease()),
        integer()}.

-file("src/aarondb/consensus.gleam", 50).
-spec new(aarondb@raft_runtime:state()) -> state().
new(Raft_state) ->
    {state, Raft_state, aarondb@command:new(), [], -1}.

-file("src/aarondb/consensus.gleam", 292).
-spec leader(aarondb@raft_runtime:state()) -> boolean().
leader(State) ->
    (erlang:element(3, State) =:= leader) andalso (erlang:element(8, State) =:= {some,
        erlang:element(2, State)}).

-file("src/aarondb/consensus.gleam", 56).
?DOC(
    " Submission is accepted only on the elected leader after current-term quorum\n"
    " replication has committed the supplied index.\n"
).
-spec submit(state(), integer(), integer(), aarondb@command:command_request()) -> {ok,
        {state(), aarondb@command:command_result()}} |
    {error, submit_error()}.
submit(State, Index, Replicated, Request) ->
    case leader(erlang:element(2, State)) of
        false ->
            {error, {redirect, erlang:element(8, erlang:element(2, State))}};

        true ->
            Committed = aarondb@raft_runtime:commit_quorum(
                erlang:element(2, State),
                Index,
                Replicated
            ),
            case erlang:element(4, erlang:element(4, Committed)) < Index of
                true ->
                    {error, quorum_unavailable};

                false ->
                    case aarondb@command:apply(
                        Index,
                        Request,
                        erlang:element(3, State)
                    ) of
                        {ok, {Commands, Result}} ->
                            {ok,
                                {{state,
                                        Committed,
                                        Commands,
                                        erlang:element(4, State),
                                        erlang:element(5, State)},
                                    Result}};

                        {error, Error} ->
                            {error, {command_failed, Error}}
                    end
            end
    end.

-file("src/aarondb/consensus.gleam", 82).
?DOC(
    " Linearizable reads require leader confirmation and a ReadIndex at least as\n"
    " recent as the command state. LeaseRead is intentionally not provided here:\n"
    " callers must use a validated lease instead of relabelling a local read.\n"
).
-spec linearizable_read(state(), integer(), boolean(), binary()) -> {ok,
        gleam@option:option(binary())} |
    {error, read_error()}.
linearizable_read(State, Read_index, Quorum_confirmed, Key) ->
    case leader(erlang:element(2, State)) of
        false ->
            {error,
                {read_redirect, erlang:element(8, erlang:element(2, State))}};

        true ->
            case Quorum_confirmed of
                false ->
                    {error, read_quorum_unavailable};

                true ->
                    case Read_index < aarondb@command:last_applied(
                        erlang:element(3, State)
                    ) of
                        true ->
                            {error, read_index_unavailable};

                        false ->
                            {_, Value} = aarondb@command:read(
                                erlang:element(3, State),
                                Key,
                                linearizable
                            ),
                            {ok, Value}
                    end
            end
    end.

-file("src/aarondb/consensus.gleam", 323).
-spec remove_lease(list(lease()), binary()) -> list(lease()).
remove_lease(Leases, Resource) ->
    gleam@list:filter(
        Leases,
        fun(Lease) ->
            {lease, Saved, _, _, _} = Lease,
            Saved /= Resource
        end
    ).

-file("src/aarondb/consensus.gleam", 330).
-spec int_string(integer()) -> binary().
int_string(Value) ->
    gleam@string:inspect(Value).

-file("src/aarondb/consensus.gleam", 296).
-spec find_lease(list(lease()), binary()) -> gleam@option:option(lease()).
find_lease(Leases, Resource) ->
    case Leases of
        [] ->
            none;

        [Lease | Rest] ->
            {lease, Saved, _, _, _} = Lease,
            case Saved =:= Resource of
                true ->
                    {some, Lease};

                false ->
                    find_lease(Rest, Resource)
            end
    end.

-file("src/aarondb/consensus.gleam", 251).
-spec revoke(
    state(),
    integer(),
    integer(),
    integer(),
    binary(),
    binary(),
    integer()
) -> {ok, {state(), gleam@option:option(lease())}} | {error, submit_error()}.
revoke(State, Index, Replicated, Now, Resource, Holder, Fence) ->
    case find_lease(erlang:element(4, State), Resource) of
        none ->
            {error, {stale_fence, Resource, 0, Fence}};

        {some, {lease, _, _, Expected, _}} when Expected =/= Fence ->
            {error, {stale_fence, Resource, Expected, Fence}};

        {some, {lease, _, Saved_holder, _, _}} when Saved_holder =/= Holder ->
            {error, {lease_holder_mismatch, Resource}};

        {some, _} ->
            case submit(
                State,
                Index,
                Replicated,
                {command_request,
                    <<<<<<"revoke:"/utf8, Resource/binary>>/binary, ":"/utf8>>/binary,
                        (int_string(Index))/binary>>,
                    {put,
                        <<"lease-revoke:"/utf8, Resource/binary>>,
                        int_string(Now)}}
            ) of
                {error, Error} ->
                    {error, Error};

                {ok, {Advanced, _}} ->
                    {ok,
                        {{state,
                                erlang:element(2, Advanced),
                                erlang:element(3, Advanced),
                                remove_lease(
                                    erlang:element(4, Advanced),
                                    Resource
                                ),
                                Now},
                            none}}
            end
    end.

-file("src/aarondb/consensus.gleam", 309).
-spec put_lease(list(lease()), lease()) -> list(lease()).
put_lease(Leases, Replacement) ->
    {lease, Resource, _, _, _} = Replacement,
    case Leases of
        [] ->
            [Replacement];

        [Lease | Rest] ->
            {lease, Saved, _, _, _} = Lease,
            case Saved =:= Resource of
                true ->
                    [Replacement | Rest];

                false ->
                    [Lease | put_lease(Rest, Replacement)]
            end
    end.

-file("src/aarondb/consensus.gleam", 201).
-spec renew(
    state(),
    integer(),
    integer(),
    integer(),
    binary(),
    binary(),
    integer(),
    integer()
) -> {ok, {state(), gleam@option:option(lease())}} | {error, submit_error()}.
renew(State, Index, Replicated, Now, Resource, Holder, Fence, Ttl) ->
    case Ttl > 0 of
        false ->
            {error, invalid_ttl};

        true ->
            case find_lease(erlang:element(4, State), Resource) of
                none ->
                    {error, {stale_fence, Resource, 0, Fence}};

                {some, {lease, _, _, Expected, _}} when Expected =/= Fence ->
                    {error, {stale_fence, Resource, Expected, Fence}};

                {some, {lease, _, Saved_holder, _, _}} when Saved_holder =/= Holder ->
                    {error, {lease_holder_mismatch, Resource}};

                {some, {lease, _, _, _, Expiry}} when Expiry =< Now ->
                    {error, {stale_fence, Resource, 0, Fence}};

                {some, _} ->
                    case submit(
                        State,
                        Index,
                        Replicated,
                        {command_request,
                            <<<<<<"renew:"/utf8, Resource/binary>>/binary,
                                    ":"/utf8>>/binary,
                                (int_string(Index))/binary>>,
                            {put,
                                <<"lease-renew:"/utf8, Resource/binary>>,
                                int_string(Now)}}
                    ) of
                        {error, Error} ->
                            {error, Error};

                        {ok, {Advanced, _}} ->
                            Renewed = {lease,
                                Resource,
                                Holder,
                                Fence,
                                Now + Ttl},
                            {ok,
                                {{state,
                                        erlang:element(2, Advanced),
                                        erlang:element(3, Advanced),
                                        put_lease(
                                            erlang:element(4, Advanced),
                                            Renewed
                                        ),
                                        Now},
                                    {some, Renewed}}}
                    end
            end
    end.

-file("src/aarondb/consensus.gleam", 151).
-spec acquire(
    state(),
    integer(),
    integer(),
    integer(),
    binary(),
    binary(),
    integer()
) -> {ok, {state(), gleam@option:option(lease())}} | {error, submit_error()}.
acquire(State, Index, Replicated, Now, Resource, Holder, Ttl) ->
    case Ttl > 0 of
        false ->
            {error, invalid_ttl};

        true ->
            case find_lease(erlang:element(4, State), Resource) of
                {some, {lease, _, _, Fence, Expiry}} when Expiry > Now ->
                    {error, {lease_held, Resource, Fence, Expiry}};

                _ ->
                    case submit(
                        State,
                        Index,
                        Replicated,
                        {command_request,
                            <<<<<<<<<<"lease:"/utf8, Resource/binary>>/binary,
                                            ":"/utf8>>/binary,
                                        Holder/binary>>/binary,
                                    ":"/utf8>>/binary,
                                (int_string(Index))/binary>>,
                            {issue_fence, Resource}}
                    ) of
                        {error, Error} ->
                            {error, Error};

                        {ok, {Advanced, {fence_issued, _, Fence@1}}} ->
                            Granted = {lease,
                                Resource,
                                Holder,
                                Fence@1,
                                Now + Ttl},
                            {ok,
                                {{state,
                                        erlang:element(2, Advanced),
                                        erlang:element(3, Advanced),
                                        put_lease(
                                            erlang:element(4, Advanced),
                                            Granted
                                        ),
                                        Now},
                                    {some, Granted}}};

                        {ok, _} ->
                            {error, not_committed}
                    end
            end
    end.

-file("src/aarondb/consensus.gleam", 134).
-spec lease_at_monotonic_time(
    state(),
    integer(),
    integer(),
    integer(),
    lease_command()
) -> {ok, {state(), gleam@option:option(lease())}} | {error, submit_error()}.
lease_at_monotonic_time(State, Index, Replicated, Now, Request) ->
    case Request of
        {acquire, Resource, Holder, Ttl} ->
            acquire(State, Index, Replicated, Now, Resource, Holder, Ttl);

        {renew, Resource@1, Holder@1, Fence, Ttl@1} ->
            renew(
                State,
                Index,
                Replicated,
                Now,
                Resource@1,
                Holder@1,
                Fence,
                Ttl@1
            );

        {revoke, Resource@2, Holder@2, Fence@1} ->
            revoke(State, Index, Replicated, Now, Resource@2, Holder@2, Fence@1)
    end.

-file("src/aarondb/consensus.gleam", 108).
?DOC(
    " Uses a caller-supplied monotonic time domain. Regressing clock values are\n"
    " rejected, so expiry cannot be extended by a local wall-clock rollback.\n"
).
-spec lease(state(), integer(), integer(), integer(), lease_command()) -> {ok,
        {state(), gleam@option:option(lease())}} |
    {error, submit_error()}.
lease(State, Index, Replicated, Now, Request) ->
    case Now < erlang:element(5, State) of
        true ->
            {error, {invalid_clock, Now, erlang:element(5, State)}};

        false ->
            lease_at_monotonic_time(State, Index, Replicated, Now, Request)
    end.

-file("src/aarondb/consensus.gleam", 121).
-spec validate_fence(state(), binary(), integer()) -> {ok, nil} |
    {error, submit_error()}.
validate_fence(State, Resource, Fence) ->
    case find_lease(erlang:element(4, State), Resource) of
        {some, {lease, _, _, Expected, _}} when Expected =:= Fence ->
            {ok, nil};

        {some, {lease, _, _, Expected@1, _}} ->
            {error, {stale_fence, Resource, Expected@1, Fence}};

        none ->
            {error, {stale_fence, Resource, 0, Fence}}
    end.
