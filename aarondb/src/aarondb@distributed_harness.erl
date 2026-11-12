-module(aarondb@distributed_harness).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/distributed_harness.gleam").
-export([schedule/1, replay/2, inspect/1, artifact/1, passed/1]).
-export_type([fault/0, observation/0, violation/0, run/0, artifact/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # distributed_harness — deterministic adversarial safety oracle\n"
    "\n"
    " This module deliberately models reproducible fault schedules and invariant\n"
    " checks only. The process/network adapter owns delivery; it records the\n"
    " resulting observations here so a failure can be replayed without timing or\n"
    " scheduler luck.\n"
).

-type fault() :: {partition, binary(), binary()} |
    {heal, binary(), binary()} |
    {duplicate_rpc, binary()} |
    {reorder_rpc, binary()} |
    {crash, binary()} |
    {restart, binary()} |
    {disk_fault, binary()} |
    {slow_follower, binary()} |
    {membership_churn, binary()} |
    {clock_skew, binary(), integer()}.

-type observation() :: {leaders, integer(), list(binary())} |
    {applied, integer(), integer()} |
    {fence, binary(), integer(), integer()} |
    {recovery_alarm, boolean()}.

-type violation() :: {split_brain, integer(), list(binary())} |
    {duplicate_apply, integer(), integer()} |
    {stale_fence_accepted, binary(), integer(), integer()} |
    unsafe_recovery_unalarmed.

-type run() :: {run, integer(), list(fault()), list(observation())}.

-type artifact() :: {artifact,
        integer(),
        list(fault()),
        list(observation()),
        list(violation())}.

-file("src/aarondb/distributed_harness.gleam", 52).
?DOC(
    " The stable seeds are a public replay corpus. Keep them fixed: changing a\n"
    " seed changes a reproducibility contract and belongs in a release note.\n"
).
-spec schedule(integer()) -> list(fault()).
schedule(Seed) ->
    case Seed of
        11 ->
            [{partition, <<"a"/utf8>>, <<"b"/utf8>>},
                {duplicate_rpc, <<"append-7"/utf8>>},
                {heal, <<"a"/utf8>>, <<"b"/utf8>>}];

        23 ->
            [{crash, <<"b"/utf8>>},
                {restart, <<"b"/utf8>>},
                {reorder_rpc, <<"append-9"/utf8>>}];

        37 ->
            [{slow_follower, <<"c"/utf8>>},
                {membership_churn, <<"d"/utf8>>},
                {clock_skew, <<"a"/utf8>>, -5}];

        41 ->
            [{disk_fault, <<"b"/utf8>>},
                {crash, <<"b"/utf8>>},
                {restart, <<"b"/utf8>>},
                {reorder_rpc, <<"snapshot-12"/utf8>>}];

        _ ->
            [{partition, <<"a"/utf8>>, <<"c"/utf8>>},
                {heal, <<"a"/utf8>>, <<"c"/utf8>>}]
    end.

-file("src/aarondb/distributed_harness.gleam", 75).
-spec replay(integer(), list(observation())) -> run().
replay(Seed, Observations) ->
    {run, Seed, schedule(Seed), Observations}.

-file("src/aarondb/distributed_harness.gleam", 134).
-spec list_length(list(any())) -> integer().
list_length(Items) ->
    case Items of
        [] ->
            0;

        [_ | Rest] ->
            1 + list_length(Rest)
    end.

-file("src/aarondb/distributed_harness.gleam", 109).
-spec violation(observation()) -> list(violation()).
violation(Observation) ->
    case Observation of
        {leaders, Term, Leaders} ->
            case list_length(Leaders) > 1 of
                true ->
                    [{split_brain, Term, Leaders}];

                false ->
                    []
            end;

        {applied, Index, Copies} ->
            case Copies > 1 of
                true ->
                    [{duplicate_apply, Index, Copies}];

                false ->
                    []
            end;

        {fence, Resource, Expected, Received} ->
            case Received < Expected of
                true ->
                    [{stale_fence_accepted, Resource, Expected, Received}];

                false ->
                    []
            end;

        {recovery_alarm, Present} ->
            case Present of
                true ->
                    [];

                false ->
                    [unsafe_recovery_unalarmed]
            end
    end.

-file("src/aarondb/distributed_harness.gleam", 98).
-spec inspect_observations(list(observation())) -> list(violation()).
inspect_observations(Observations) ->
    case Observations of
        [] ->
            [];

        [Observation | Rest] ->
            case violation(Observation) of
                [] ->
                    inspect_observations(Rest);

                Found ->
                    lists:append(Found, inspect_observations(Rest))
            end
    end.

-file("src/aarondb/distributed_harness.gleam", 79).
-spec inspect(run()) -> list(violation()).
inspect(Run) ->
    inspect_observations(erlang:element(4, Run)).

-file("src/aarondb/distributed_harness.gleam", 87).
?DOC(
    " Persist this value exactly when an adapter run fails. It contains every\n"
    " deterministic input needed to reproduce the invariant failure locally or\n"
    " in CI; raw process logs may be attached alongside it but are not required\n"
    " to reconstruct the schedule.\n"
).
-spec artifact(run()) -> artifact().
artifact(Run) ->
    {artifact,
        erlang:element(2, Run),
        erlang:element(3, Run),
        erlang:element(4, Run),
        inspect(Run)}.

-file("src/aarondb/distributed_harness.gleam", 91).
-spec passed(run()) -> boolean().
passed(Run) ->
    case inspect(Run) of
        [] ->
            true;

        _ ->
            false
    end.
