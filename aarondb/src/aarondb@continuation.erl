-module(aarondb@continuation).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/continuation.gleam").
-export([new/2, checkpoint/1, resume/1, current_provider/1, permit_effect/1, record_effect/1, fail/5]).
-export_type([failure_class/0, retry_policy/0, work/0, evidence/0, fallback_outcome/0, issue_payload/0, status/0, continuation/0, checkpoint/0, effect_permit/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # continuation — deterministic transient-failure policy\n"
    "\n"
    " This is a pure model for resuming approved work after a provider or transport\n"
    " interruption. An adapter persists `Checkpoint` and performs the chosen effect;\n"
    " this module never retries, sleeps, switches providers, or files an issue itself.\n"
).

-type failure_class() :: transient | provider_overloaded | permanent.

-type retry_policy() :: {retry_policy, integer(), integer(), list(binary())}.

-type work() :: {work, binary(), binary(), binary()}.

-type evidence() :: {evidence,
        binary(),
        failure_class(),
        integer(),
        integer(),
        binary()}.

-type fallback_outcome() :: no_fallback_available |
    {fallback_selected, binary()} |
    fallback_exhausted.

-type issue_payload() :: {issue_payload,
        binary(),
        binary(),
        binary(),
        binary(),
        integer(),
        integer(),
        failure_class(),
        integer(),
        fallback_outcome(),
        binary()}.

-type status() :: ready |
    {waiting, integer()} |
    {switched_to_fallback, binary()} |
    {escalated, issue_payload()} |
    completed.

-type continuation() :: {continuation,
        work(),
        retry_policy(),
        integer(),
        integer(),
        gleam@option:option(evidence()),
        list(binary()),
        status()}.

-type checkpoint() :: {checkpoint, continuation()}.

-type effect_permit() :: effect_authorized | effect_already_completed.

-file("src/aarondb/continuation.gleam", 91).
-spec new(work(), retry_policy()) -> continuation().
new(Work, Policy) ->
    {continuation, Work, Policy, 0, 0, none, [], ready}.

-file("src/aarondb/continuation.gleam", 95).
-spec checkpoint(continuation()) -> checkpoint().
checkpoint(Continuation) ->
    {checkpoint, Continuation}.

-file("src/aarondb/continuation.gleam", 99).
-spec resume(checkpoint()) -> continuation().
resume(Checkpoint) ->
    {checkpoint, Continuation} = Checkpoint,
    Continuation.

-file("src/aarondb/continuation.gleam", 254).
-spec list_at(list(QYX), integer()) -> gleam@option:option(QYX).
list_at(Items, Index) ->
    case {Items, Index} of
        {[], _} ->
            none;

        {[Item | _], 0} ->
            {some, Item};

        {[_ | Rest], _} ->
            list_at(Rest, Index - 1)
    end.

-file("src/aarondb/continuation.gleam", 247).
-spec provider_at(list(binary()), integer()) -> gleam@option:option(binary()).
provider_at(Providers, Index) ->
    case Index < 0 of
        true ->
            none;

        false ->
            list_at(Providers, Index)
    end.

-file("src/aarondb/continuation.gleam", 104).
-spec current_provider(continuation()) -> gleam@option:option(binary()).
current_provider(Continuation) ->
    provider_at(
        erlang:element(4, erlang:element(3, Continuation)),
        erlang:element(4, Continuation)
    ).

-file("src/aarondb/continuation.gleam", 109).
?DOC(" The adapter asks permission before performing the named external effect.\n").
-spec permit_effect(continuation()) -> effect_permit().
permit_effect(Continuation) ->
    case gleam@list:contains(
        erlang:element(7, Continuation),
        erlang:element(4, erlang:element(2, Continuation))
    ) of
        true ->
            effect_already_completed;

        false ->
            effect_authorized
    end.

-file("src/aarondb/continuation.gleam", 123).
?DOC(
    " Record completion before acknowledging an effect. Repeating this operation is\n"
    " deliberately idempotent so an interrupted acknowledgement cannot duplicate it.\n"
).
-spec record_effect(continuation()) -> continuation().
record_effect(Continuation) ->
    case permit_effect(Continuation) of
        effect_already_completed ->
            Continuation;

        effect_authorized ->
            {continuation,
                erlang:element(2, Continuation),
                erlang:element(3, Continuation),
                erlang:element(4, Continuation),
                erlang:element(5, Continuation),
                erlang:element(6, Continuation),
                [erlang:element(4, erlang:element(2, Continuation)) |
                    erlang:element(7, Continuation)],
                completed}
    end.

-file("src/aarondb/continuation.gleam", 210).
-spec escalate(continuation(), evidence(), fallback_outcome()) -> continuation().
escalate(Continuation, Evidence, Fallback_outcome) ->
    {work, Plan_id, Task_id, Effect_key} = erlang:element(2, Continuation),
    {continuation,
        erlang:element(2, Continuation),
        erlang:element(3, Continuation),
        erlang:element(4, Continuation),
        erlang:element(5, Continuation),
        erlang:element(6, Continuation),
        erlang:element(7, Continuation),
        {escalated,
            {issue_payload,
                Plan_id,
                Task_id,
                Effect_key,
                erlang:element(2, Evidence),
                erlang:element(4, Evidence),
                erlang:element(5, Evidence),
                erlang:element(3, Evidence),
                erlang:element(5, Continuation),
                Fallback_outcome,
                erlang:element(6, Evidence)}}}.

-file("src/aarondb/continuation.gleam", 193).
-spec switch_or_escalate(continuation(), evidence()) -> continuation().
switch_or_escalate(Continuation, Evidence) ->
    Next_index = erlang:element(4, Continuation) + 1,
    case provider_at(
        erlang:element(4, erlang:element(3, Continuation)),
        Next_index
    ) of
        {some, Provider} ->
            {continuation,
                erlang:element(2, Continuation),
                erlang:element(3, Continuation),
                Next_index,
                0,
                erlang:element(6, Continuation),
                erlang:element(7, Continuation),
                {switched_to_fallback, Provider}};

        none ->
            escalate(Continuation, Evidence, fallback_exhausted)
    end.

-file("src/aarondb/continuation.gleam", 177).
-spec wait_for_retry(continuation(), evidence()) -> continuation().
wait_for_retry(Continuation, Evidence) ->
    Next_retry = erlang:element(5, Continuation) + 1,
    {continuation,
        erlang:element(2, Continuation),
        erlang:element(3, Continuation),
        erlang:element(4, Continuation),
        Next_retry,
        erlang:element(6, Continuation),
        erlang:element(7, Continuation),
        {waiting,
            erlang:element(5, Evidence) + (erlang:element(
                3,
                erlang:element(3, Continuation)
            )
            * Next_retry)}}.

-file("src/aarondb/continuation.gleam", 164).
-spec decide(continuation(), evidence()) -> continuation().
decide(Continuation, Evidence) ->
    case erlang:element(3, Evidence) of
        permanent ->
            escalate(Continuation, Evidence, no_fallback_available);

        _ ->
            case erlang:element(5, Continuation) < erlang:element(
                2,
                erlang:element(3, Continuation)
            ) of
                true ->
                    wait_for_retry(Continuation, Evidence);

                false ->
                    switch_or_escalate(Continuation, Evidence)
            end
    end.

-file("src/aarondb/continuation.gleam", 233).
-spec next_evidence(
    gleam@option:option(evidence()),
    binary(),
    failure_class(),
    binary(),
    integer()
) -> evidence().
next_evidence(Previous, Request_id, Failure_class, Message, Now_ms) ->
    case Previous of
        {some, {evidence, _, _, First_failed_at_ms, _, _}} ->
            {evidence,
                Request_id,
                Failure_class,
                First_failed_at_ms,
                Now_ms,
                Message};

        none ->
            {evidence, Request_id, Failure_class, Now_ms, Now_ms, Message}
    end.

-file("src/aarondb/continuation.gleam", 141).
?DOC(
    " Decide the next retry/fallback/escalation transition for a failure observed at\n"
    " `now_ms`. A permanent failure never retries. Backoff is deterministic linear\n"
    " data: `base_backoff_ms * next_retry_count`.\n"
).
-spec fail(continuation(), binary(), failure_class(), binary(), integer()) -> continuation().
fail(Continuation, Request_id, Failure_class, Message, Now_ms) ->
    Evidence = next_evidence(
        erlang:element(6, Continuation),
        Request_id,
        Failure_class,
        Message,
        Now_ms
    ),
    case erlang:element(8, Continuation) of
        completed ->
            Continuation;

        {escalated, _} ->
            Continuation;

        _ ->
            decide(
                {continuation,
                    erlang:element(2, Continuation),
                    erlang:element(3, Continuation),
                    erlang:element(4, Continuation),
                    erlang:element(5, Continuation),
                    {some, Evidence},
                    erlang:element(7, Continuation),
                    erlang:element(8, Continuation)},
                Evidence
            )
    end.
