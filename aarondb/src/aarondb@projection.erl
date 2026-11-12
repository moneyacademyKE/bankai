-module(aarondb@projection).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/projection.gleam").
-export([new/3, status/2, catch_up/2, restart/2, resume/1, rebuild/3, values/1]).
-export_type([projection_state/0, failure/0, metrics/0, status/0, projection/0, projection_error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # projection — supervised, checkpointed derived-state reference\n"
    "\n"
    " This pure module models the durable projection contract. Delivery is\n"
    " at-least-once; `apply` deduplicates offsets and commits its checkpoint only\n"
    " after the derived state has accepted the entry.\n"
).

-type projection_state() :: running |
    paused |
    replaying |
    failed |
    rebuilding |
    stale.

-type failure() :: {retryable, binary()} |
    {permanent, binary()} |
    {source_unavailable, binary()} |
    {corrupt_source, integer()} |
    {pressure_exceeded, integer()}.

-type metrics() :: {metrics, integer(), integer(), integer(), integer()}.

-type status() :: {status,
        projection_state(),
        integer(),
        integer(),
        gleam@option:option(failure()),
        integer(),
        metrics()}.

-type projection() :: {projection,
        binary(),
        integer(),
        integer(),
        integer(),
        projection_state(),
        integer(),
        list(integer()),
        list(binary()),
        gleam@option:option(failure()),
        metrics()}.

-type projection_error() :: {bounded_pressure, integer()} |
    {permanently_failed, failure()} |
    {source, aarondb@durable_log:durable_log_error()} |
    {checkpoint, aarondb@durable_log:durable_log_error()}.

-file("src/aarondb/projection.gleam", 65).
-spec new(binary(), integer(), integer()) -> projection().
new(Name, Max_batch, Max_restarts) ->
    {projection,
        Name,
        0,
        Max_batch,
        Max_restarts,
        running,
        -1,
        [],
        [],
        none,
        {metrics, 0, 0, 0, 0}}.

-file("src/aarondb/projection.gleam", 241).
-spec max(integer(), integer()) -> integer().
max(Left, Right) ->
    case Left > Right of
        true ->
            Left;

        false ->
            Right
    end.

-file("src/aarondb/projection.gleam", 80).
-spec status(projection(), aarondb@durable_log:durable_log()) -> status().
status(Projection, Source) ->
    {status,
        erlang:element(6, Projection),
        erlang:element(7, Projection),
        max(0, (erlang:element(3, Source) - erlang:element(7, Projection)) - 1),
        erlang:element(10, Projection),
        erlang:element(3, Projection),
        erlang:element(11, Projection)}.

-file("src/aarondb/projection.gleam", 237).
-spec contains(list(integer()), integer()) -> boolean().
contains(Offsets, Needle) ->
    gleam@list:any(Offsets, fun(Offset) -> Offset =:= Needle end).

-file("src/aarondb/projection.gleam", 209).
-spec apply(projection(), aarondb@durable_log:entry()) -> projection().
apply(Projection, Entry) ->
    {metrics, Applied, Duplicates, Restarts, Rebuilds} = erlang:element(
        11,
        Projection
    ),
    case contains(erlang:element(8, Projection), erlang:element(2, Entry)) of
        true ->
            {projection,
                erlang:element(2, Projection),
                erlang:element(3, Projection),
                erlang:element(4, Projection),
                erlang:element(5, Projection),
                erlang:element(6, Projection),
                erlang:element(7, Projection),
                erlang:element(8, Projection),
                erlang:element(9, Projection),
                erlang:element(10, Projection),
                {metrics, Applied, Duplicates + 1, Restarts, Rebuilds}};

        false ->
            {projection,
                erlang:element(2, Projection),
                erlang:element(3, Projection),
                erlang:element(4, Projection),
                erlang:element(5, Projection),
                erlang:element(6, Projection),
                erlang:element(2, Entry),
                lists:append(
                    erlang:element(8, Projection),
                    [erlang:element(2, Entry)]
                ),
                lists:append(
                    erlang:element(9, Projection),
                    [erlang:element(3, Entry)]
                ),
                erlang:element(10, Projection),
                {metrics, Applied + 1, Duplicates, Restarts, Rebuilds}}
    end.

-file("src/aarondb/projection.gleam", 185).
-spec apply_all(
    projection(),
    aarondb@durable_log:durable_log(),
    list(aarondb@durable_log:entry())
) -> {ok, {projection(), aarondb@durable_log:durable_log()}} |
    {error, projection_error()}.
apply_all(Projection, Source, Entries) ->
    case Entries of
        [] ->
            {ok,
                {{projection,
                        erlang:element(2, Projection),
                        erlang:element(3, Projection),
                        erlang:element(4, Projection),
                        erlang:element(5, Projection),
                        running,
                        erlang:element(7, Projection),
                        erlang:element(8, Projection),
                        erlang:element(9, Projection),
                        none,
                        erlang:element(11, Projection)},
                    Source}};

        [Entry | Rest] ->
            Next = apply(Projection, Entry),
            Checkpoint = {projection_checkpoint,
                erlang:element(2, Projection),
                erlang:element(7, Next)},
            case aarondb@durable_log:commit_checkpoint(
                Source,
                Checkpoint,
                no_fault
            ) of
                {error, Error} ->
                    {error, {checkpoint, Error}};

                {ok, Committed} ->
                    apply_all(Next, Committed, Rest)
            end
    end.

-file("src/aarondb/projection.gleam", 228).
-spec failed(projection()) -> {ok,
        {projection(), aarondb@durable_log:durable_log()}} |
    {error, projection_error()}.
failed(Projection) ->
    case erlang:element(10, Projection) of
        {some, Failure} ->
            {error, {permanently_failed, Failure}};

        none ->
            {error,
                {permanently_failed,
                    {permanent, <<"failed without reason"/utf8>>}}}
    end.

-file("src/aarondb/projection.gleam", 95).
?DOC(" Apply a bounded source tail, preserving atomic state/checkpoint ordering.\n").
-spec catch_up(projection(), aarondb@durable_log:durable_log()) -> {ok,
        {projection(), aarondb@durable_log:durable_log()}} |
    {error, projection_error()}.
catch_up(Projection, Source) ->
    case erlang:element(6, Projection) of
        failed ->
            failed(Projection);

        rebuilding ->
            failed(Projection);

        paused ->
            {ok, {Projection, Source}};

        _ ->
            case aarondb@durable_log:scan_after(
                Source,
                erlang:element(7, Projection)
            ) of
                {error, Error} ->
                    {error, {source, Error}};

                {ok, Entries} ->
                    case erlang:length(Entries) > erlang:element(4, Projection) of
                        true ->
                            {error,
                                {bounded_pressure,
                                    erlang:element(4, Projection)}};

                        false ->
                            apply_all(Projection, Source, Entries)
                    end
            end
    end.

-file("src/aarondb/projection.gleam", 116).
?DOC(" A retryable crash increments supervision state; exhaustion is permanent and visible.\n").
-spec restart(projection(), binary()) -> projection().
restart(Projection, Reason) ->
    {metrics, Applied, Duplicates, Restarts, Rebuilds} = erlang:element(
        11,
        Projection
    ),
    Next_restarts = Restarts + 1,
    case Next_restarts > erlang:element(5, Projection) of
        true ->
            {projection,
                erlang:element(2, Projection),
                erlang:element(3, Projection),
                erlang:element(4, Projection),
                erlang:element(5, Projection),
                failed,
                erlang:element(7, Projection),
                erlang:element(8, Projection),
                erlang:element(9, Projection),
                {some, {permanent, Reason}},
                {metrics, Applied, Duplicates, Next_restarts, Rebuilds}};

        false ->
            {projection,
                erlang:element(2, Projection),
                erlang:element(3, Projection),
                erlang:element(4, Projection),
                erlang:element(5, Projection),
                replaying,
                erlang:element(7, Projection),
                erlang:element(8, Projection),
                erlang:element(9, Projection),
                {some, {retryable, Reason}},
                {metrics, Applied, Duplicates, Next_restarts, Rebuilds}}
    end.

-file("src/aarondb/projection.gleam", 137).
-spec resume(projection()) -> projection().
resume(Projection) ->
    case erlang:element(10, Projection) of
        {some, {retryable, _}} ->
            {projection,
                erlang:element(2, Projection),
                erlang:element(3, Projection),
                erlang:element(4, Projection),
                erlang:element(5, Projection),
                running,
                erlang:element(7, Projection),
                erlang:element(8, Projection),
                erlang:element(9, Projection),
                none,
                erlang:element(11, Projection)};

        _ ->
            Projection
    end.

-file("src/aarondb/projection.gleam", 146).
?DOC(" Rebuild creates an isolated next generation from a snapshot boundary then swaps it.\n").
-spec rebuild(
    projection(),
    aarondb@durable_log:durable_log(),
    aarondb@durable_log:snapshot()
) -> {ok, {projection(), aarondb@durable_log:durable_log()}} |
    {error, projection_error()}.
rebuild(Projection, Source, Snapshot) ->
    Rebuilding = {projection,
        erlang:element(2, Projection),
        erlang:element(3, Projection),
        erlang:element(4, Projection),
        erlang:element(5, Projection),
        rebuilding,
        erlang:element(7, Projection),
        erlang:element(8, Projection),
        erlang:element(9, Projection),
        none,
        erlang:element(11, Projection)},
    case aarondb@durable_log:snapshot_then_tail(
        Source,
        erlang:element(2, Snapshot)
    ) of
        {error, Error} ->
            {error, {source, Error}};

        {ok, {_, Tail}} ->
            Fresh = {projection,
                erlang:element(2, Rebuilding),
                erlang:element(3, Projection) + 1,
                erlang:element(4, Rebuilding),
                erlang:element(5, Rebuilding),
                erlang:element(6, Rebuilding),
                erlang:element(2, Snapshot),
                [],
                [],
                erlang:element(10, Rebuilding),
                erlang:element(11, Rebuilding)},
            case apply_all(Fresh, Source, Tail) of
                {ok, {Rebuilt, Log}} ->
                    {metrics, Applied, Duplicates, Restarts, Rebuilds} = erlang:element(
                        11,
                        Rebuilt
                    ),
                    {ok,
                        {{projection,
                                erlang:element(2, Rebuilt),
                                erlang:element(3, Rebuilt),
                                erlang:element(4, Rebuilt),
                                erlang:element(5, Rebuilt),
                                running,
                                erlang:element(7, Rebuilt),
                                erlang:element(8, Rebuilt),
                                erlang:element(9, Rebuilt),
                                erlang:element(10, Rebuilt),
                                {metrics,
                                    Applied,
                                    Duplicates,
                                    Restarts,
                                    Rebuilds + 1}},
                            Log}};

                {error, Error@1} ->
                    {error, Error@1}
            end
    end.

-file("src/aarondb/projection.gleam", 181).
-spec values(projection()) -> list(binary()).
values(Projection) ->
    erlang:element(9, Projection).
