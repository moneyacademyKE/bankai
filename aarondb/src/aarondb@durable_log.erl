-module(aarondb@durable_log).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/durable_log.gleam").
-export([new/1, append/3, scan_after/2, snapshot/3, snapshot_then_tail/2, retain_after/2, commit_checkpoint/3, checkpoint/2, corrupt_entry/2]).
-export_type([entry/0, snapshot/0, projection_checkpoint/0, checkpoint_fault/0, durable_log/0, durable_log_error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # durable_log — independent deterministic durable-log reference\n"
    "\n"
    " This pure local reference is deliberately separate from fact storage. It\n"
    " models the port contract used by later durable adapters: ordered offsets,\n"
    " retained tails, verified snapshots, idempotent append, and an atomic\n"
    " projection-checkpoint boundary. It is not a filesystem implementation.\n"
).

-type entry() :: {entry, integer(), binary(), binary(), binary()}.

-type snapshot() :: {snapshot, integer(), binary(), binary()}.

-type projection_checkpoint() :: {projection_checkpoint, binary(), integer()}.

-type checkpoint_fault() :: no_fault | fail_before_commit.

-type durable_log() :: {durable_log,
        binary(),
        integer(),
        list(entry()),
        list(snapshot()),
        list(projection_checkpoint())}.

-type durable_log_error() :: {cursor_expired, integer(), integer()} |
    {corrupt_entry, integer()} |
    {snapshot_unavailable, integer()} |
    checkpoint_fault_injected.

-file("src/aarondb/durable_log.gleam", 58).
-spec new(binary()) -> durable_log().
new(Source) ->
    {durable_log, Source, 0, [], [], []}.

-file("src/aarondb/durable_log.gleam", 248).
-spec fingerprint(binary()) -> binary().
fingerprint(Value) ->
    <<<<(erlang:integer_to_binary(string:length(Value)))/binary, ":"/utf8>>/binary,
        Value/binary>>.

-file("src/aarondb/durable_log.gleam", 252).
-spec find_key(list(entry()), binary()) -> gleam@option:option(entry()).
find_key(Entries, Key) ->
    case gleam@list:find(
        Entries,
        fun(Entry) -> erlang:element(4, Entry) =:= Key end
    ) of
        {ok, Entry@1} ->
            {some, Entry@1};

        {error, nil} ->
            none
    end.

-file("src/aarondb/durable_log.gleam", 69).
?DOC(" Append is idempotent for a source-local key. Retrying returns its first entry.\n").
-spec append(durable_log(), binary(), binary()) -> {durable_log(), entry()}.
append(Log, Payload, Idempotency_key) ->
    case find_key(erlang:element(4, Log), Idempotency_key) of
        {some, Entry} ->
            {Log, Entry};

        none ->
            Entry@1 = {entry,
                erlang:element(3, Log),
                Payload,
                Idempotency_key,
                fingerprint(Payload)},
            {{durable_log,
                    erlang:element(2, Log),
                    erlang:element(3, Log) + 1,
                    lists:append(erlang:element(4, Log), [Entry@1]),
                    erlang:element(5, Log),
                    erlang:element(6, Log)},
                Entry@1}
    end.

-file("src/aarondb/durable_log.gleam", 234).
-spec verify_entry(entry()) -> {ok, entry()} | {error, durable_log_error()}.
verify_entry(Entry) ->
    case erlang:element(5, Entry) =:= fingerprint(erlang:element(3, Entry)) of
        true ->
            {ok, Entry};

        false ->
            {error, {corrupt_entry, erlang:element(2, Entry)}}
    end.

-file("src/aarondb/durable_log.gleam", 217).
-spec verify_and_filter(list(entry()), integer()) -> {ok, list(entry())} |
    {error, durable_log_error()}.
verify_and_filter(Entries, Cursor) ->
    gleam@list:fold(
        Entries,
        {ok, []},
        fun(Result, Entry) -> case {Result, verify_entry(Entry)} of
                {{error, Error}, _} ->
                    {error, Error};

                {_, {error, Error@1}} ->
                    {error, Error@1};

                {{ok, Acc}, {ok, Valid}} ->
                    case erlang:element(2, Valid) > Cursor of
                        true ->
                            {ok, lists:append(Acc, [Valid])};

                        false ->
                            {ok, Acc}
                    end
            end end
    ).

-file("src/aarondb/durable_log.gleam", 210).
-spec earliest_available(durable_log()) -> integer().
earliest_available(Log) ->
    case erlang:element(4, Log) of
        [{entry, Offset, _, _, _} | _] ->
            Offset;

        [] ->
            erlang:element(3, Log)
    end.

-file("src/aarondb/durable_log.gleam", 97).
?DOC(" Read the retained tail strictly after `cursor` after validating every entry.\n").
-spec scan_after(durable_log(), integer()) -> {ok, list(entry())} |
    {error, durable_log_error()}.
scan_after(Log, Cursor) ->
    Earliest = earliest_available(Log),
    case Cursor < (Earliest - 1) of
        true ->
            {error, {cursor_expired, Cursor, Earliest}};

        false ->
            verify_and_filter(erlang:element(4, Log), Cursor)
    end.

-file("src/aarondb/durable_log.gleam", 110).
?DOC(" Persist a verified snapshot at an already committed position.\n").
-spec snapshot(durable_log(), integer(), binary()) -> {ok, durable_log()} |
    {error, durable_log_error()}.
snapshot(Log, Offset, State) ->
    case (Offset < -1) orelse (Offset >= erlang:element(3, Log)) of
        true ->
            {error, {snapshot_unavailable, Offset}};

        false ->
            {ok,
                {durable_log,
                    erlang:element(2, Log),
                    erlang:element(3, Log),
                    erlang:element(4, Log),
                    lists:append(
                        erlang:element(5, Log),
                        [{snapshot, Offset, State, fingerprint(State)}]
                    ),
                    erlang:element(6, Log)}}
    end.

-file("src/aarondb/durable_log.gleam", 241).
-spec verify_snapshot(snapshot()) -> {ok, snapshot()} |
    {error, durable_log_error()}.
verify_snapshot(Snapshot) ->
    case erlang:element(4, Snapshot) =:= fingerprint(
        erlang:element(3, Snapshot)
    ) of
        true ->
            {ok, Snapshot};

        false ->
            {error, {corrupt_entry, erlang:element(2, Snapshot)}}
    end.

-file("src/aarondb/durable_log.gleam", 259).
-spec latest_snapshot(list(snapshot()), integer()) -> gleam@option:option(snapshot()).
latest_snapshot(Snapshots, Through) ->
    gleam@list:fold(
        Snapshots,
        none,
        fun(Latest, Candidate) ->
            case erlang:element(2, Candidate) =< Through of
                false ->
                    Latest;

                true ->
                    case Latest of
                        none ->
                            {some, Candidate};

                        {some, Current} ->
                            case erlang:element(2, Candidate) > erlang:element(
                                2,
                                Current
                            ) of
                                true ->
                                    {some, Candidate};

                                false ->
                                    Latest
                            end
                    end
            end
        end
    ).

-file("src/aarondb/durable_log.gleam", 130).
?DOC(" Bootstrap state from the latest verified snapshot at or before `through`, then tail it.\n").
-spec snapshot_then_tail(durable_log(), integer()) -> {ok,
        {snapshot(), list(entry())}} |
    {error, durable_log_error()}.
snapshot_then_tail(Log, Through) ->
    case latest_snapshot(erlang:element(5, Log), Through) of
        none ->
            {error, {snapshot_unavailable, Through}};

        {some, Saved} ->
            case verify_snapshot(Saved) of
                {error, Error} ->
                    {error, Error};

                {ok, Snapshot} ->
                    case scan_after(Log, erlang:element(2, Snapshot)) of
                        {error, Error@1} ->
                            {error, Error@1};

                        {ok, Entries} ->
                            {ok, {Snapshot, Entries}}
                    end
            end
    end.

-file("src/aarondb/durable_log.gleam", 149).
?DOC(" Drop entries through an offset only when a verified recovery snapshot covers it.\n").
-spec retain_after(durable_log(), integer()) -> {ok, durable_log()} |
    {error, durable_log_error()}.
retain_after(Log, Offset) ->
    case latest_snapshot(erlang:element(5, Log), Offset) of
        {some, Saved} when erlang:element(2, Saved) >= Offset ->
            case verify_snapshot(Saved) of
                {ok, _} ->
                    {ok,
                        {durable_log,
                            erlang:element(2, Log),
                            erlang:element(3, Log),
                            gleam@list:filter(
                                erlang:element(4, Log),
                                fun(Entry) ->
                                    erlang:element(2, Entry) > Offset
                                end
                            ),
                            erlang:element(5, Log),
                            erlang:element(6, Log)}};

                {error, Error} ->
                    {error, Error}
            end;

        _ ->
            {error, {snapshot_unavailable, Offset}}
    end.

-file("src/aarondb/durable_log.gleam", 279).
-spec replace_checkpoint(list(projection_checkpoint()), projection_checkpoint()) -> list(projection_checkpoint()).
replace_checkpoint(Checkpoints, Replacement) ->
    Without = gleam@list:filter(
        Checkpoints,
        fun(Current) ->
            erlang:element(2, Current) /= erlang:element(2, Replacement)
        end
    ),
    lists:append(Without, [Replacement]).

-file("src/aarondb/durable_log.gleam", 173).
?DOC(
    " This boundary represents one storage transaction: projection state is owned by\n"
    " the adapter, and its successful application advances this checkpoint together.\n"
).
-spec commit_checkpoint(
    durable_log(),
    projection_checkpoint(),
    checkpoint_fault()
) -> {ok, durable_log()} | {error, durable_log_error()}.
commit_checkpoint(Log, Checkpoint, Fault) ->
    case Fault of
        fail_before_commit ->
            {error, checkpoint_fault_injected};

        no_fault ->
            {ok,
                {durable_log,
                    erlang:element(2, Log),
                    erlang:element(3, Log),
                    erlang:element(4, Log),
                    erlang:element(5, Log),
                    replace_checkpoint(erlang:element(6, Log), Checkpoint)}}
    end.

-file("src/aarondb/durable_log.gleam", 290).
-spec find_checkpoint(list(projection_checkpoint()), binary()) -> gleam@option:option(projection_checkpoint()).
find_checkpoint(Checkpoints, Projection) ->
    case gleam@list:find(
        Checkpoints,
        fun(Current) -> erlang:element(2, Current) =:= Projection end
    ) of
        {ok, Checkpoint} ->
            {some, Checkpoint};

        {error, nil} ->
            none
    end.

-file("src/aarondb/durable_log.gleam", 190).
-spec checkpoint(durable_log(), binary()) -> gleam@option:option(projection_checkpoint()).
checkpoint(Log, Projection) ->
    find_checkpoint(erlang:element(6, Log), Projection).

-file("src/aarondb/durable_log.gleam", 198).
?DOC(" Test-only fault-model hook: a decoder must fail rather than skip altered bytes.\n").
-spec corrupt_entry(durable_log(), integer()) -> durable_log().
corrupt_entry(Log, Offset) ->
    {durable_log,
        erlang:element(2, Log),
        erlang:element(3, Log),
        gleam@list:map(
            erlang:element(4, Log),
            fun(Entry) -> case erlang:element(2, Entry) =:= Offset of
                    true ->
                        {entry,
                            erlang:element(2, Entry),
                            <<(erlang:element(3, Entry))/binary,
                                "!corrupt"/utf8>>,
                            erlang:element(4, Entry),
                            erlang:element(5, Entry)};

                    false ->
                        Entry
                end end
        ),
        erlang:element(5, Log),
        erlang:element(6, Log)}.
