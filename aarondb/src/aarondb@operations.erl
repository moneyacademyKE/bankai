-module(aarondb@operations).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/operations.gleam").
-export([status/8]).
-export_type([quorum_health/0, alarm/0, status/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(" # operations — typed, honest distributed runtime status\n").

-type quorum_health() :: healthy | degraded | unavailable.

-type alarm() :: quorum_lost |
    {projection_failed, aarondb@projection:failure()} |
    {index_unavailable, aarondb@projection_index:health()} |
    {unsafe_recovery, aarondb@identity:recovery_alarm()}.

-type status() :: {status,
        gleam@option:option(binary()),
        integer(),
        integer(),
        quorum_health(),
        aarondb@projection:status(),
        aarondb@projection_index:health(),
        integer(),
        list(alarm())}.

-file("src/aarondb/operations.gleam", 73).
-spec alarms(
    quorum_health(),
    gleam@option:option(aarondb@projection:failure()),
    aarondb@projection_index:health(),
    list(aarondb@identity:recovery_alarm())
) -> list(alarm()).
alarms(Quorum, Projection_failure, Index_health, Recovery_alarms) ->
    Quorum_alarms = case Quorum of
        healthy ->
            [];

        _ ->
            [quorum_lost]
    end,
    Projection_alarms = case Projection_failure of
        {some, Failure} ->
            [{projection_failed, Failure}];

        none ->
            []
    end,
    Index_alarms = case Index_health of
        queryable ->
            [];

        Other ->
            [{index_unavailable, Other}]
    end,
    lists:append(
        Quorum_alarms,
        lists:append(
            Projection_alarms,
            lists:append(
                Index_alarms,
                gleam@list:map(
                    Recovery_alarms,
                    fun(Alarm) -> {unsafe_recovery, Alarm} end
                )
            )
        )
    ).

-file("src/aarondb/operations.gleam", 103).
-spec max(integer(), integer()) -> integer().
max(Left, Right) ->
    case Left > Right of
        true ->
            Left;

        false ->
            Right
    end.

-file("src/aarondb/operations.gleam", 61).
-spec quorum_health(integer(), integer()) -> quorum_health().
quorum_health(Voters, Acknowledged) ->
    Required = (Voters div 2) + 1,
    case Acknowledged >= Required of
        true ->
            healthy;

        false ->
            case Acknowledged > 0 of
                true ->
                    degraded;

                false ->
                    unavailable
            end
    end.

-file("src/aarondb/operations.gleam", 37).
-spec status(
    aarondb@raft_runtime:state(),
    integer(),
    integer(),
    integer(),
    aarondb@projection:status(),
    aarondb@projection_index:index(),
    aarondb@consensus:state(),
    aarondb@identity:recovery_state()
) -> status().
status(
    Raft_state,
    Voter_count,
    Acknowledged,
    Follower_match_index,
    Projection_status,
    Index,
    Consensus_state,
    Recovery
) ->
    Quorum = quorum_health(Voter_count, Acknowledged),
    Lag = max(
        0,
        erlang:element(4, erlang:element(4, Raft_state)) - Follower_match_index
    ),
    {status,
        erlang:element(8, Raft_state),
        erlang:element(4, erlang:element(4, Raft_state)),
        Lag,
        Quorum,
        Projection_status,
        erlang:element(4, Index),
        erlang:length(erlang:element(4, Consensus_state)),
        alarms(
            Quorum,
            erlang:element(5, Projection_status),
            erlang:element(4, Index),
            erlang:element(2, Recovery)
        )}.
