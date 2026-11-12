-module(aarondb@changefeed).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/changefeed.gleam").
-export([resume/3, bootstrap/2, grant/2, pull/1, acknowledge/2, cursor/1, credits/1]).
-export_type([changefeed/0, bootstrap/0, changefeed_error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # changefeed — bounded, resumable, ordered delivery over a durable source\n"
    "\n"
    " The contract is deliberately at-least-once. Consumers persist their own\n"
    " idempotent effect and advance their durable projection checkpoint in the\n"
    " same storage transaction. A cursor identifies the last acknowledged offset.\n"
).

-type changefeed() :: {changefeed,
        aarondb@durable_log:durable_log(),
        integer(),
        integer()}.

-type bootstrap() :: {bootstrap,
        aarondb@durable_log:snapshot(),
        list(aarondb@durable_log:entry()),
        integer()}.

-type changefeed_error() :: {invalid_credit, integer()} |
    {source, aarondb@durable_log:durable_log_error()}.

-file("src/aarondb/changefeed.gleam", 37).
?DOC(" Open a resumable feed. `cursor` is the last durably acknowledged offset.\n").
-spec resume(aarondb@durable_log:durable_log(), integer(), integer()) -> {ok,
        changefeed()} |
    {error, changefeed_error()}.
resume(Source, Cursor, Credit) ->
    case Credit < 0 of
        true ->
            {error, {invalid_credit, Credit}};

        false ->
            case aarondb@durable_log:scan_after(Source, Cursor) of
                {ok, _} ->
                    {ok, {changefeed, Source, Cursor, Credit}};

                {error, Error} ->
                    {error, {source, Error}}
            end
    end.

-file("src/aarondb/changefeed.gleam", 54).
?DOC(
    " Establish a consistent snapshot boundary before opening the tail feed.\n"
    " The returned cursor is the snapshot position; callers must resume from it.\n"
).
-spec bootstrap(aarondb@durable_log:durable_log(), integer()) -> {ok,
        bootstrap()} |
    {error, changefeed_error()}.
bootstrap(Source, Through) ->
    case aarondb@durable_log:snapshot_then_tail(Source, Through) of
        {ok, {Snapshot, Tail}} ->
            {ok, {bootstrap, Snapshot, Tail, erlang:element(2, Snapshot)}};

        {error, Error} ->
            {error, {source, Error}}
    end.

-file("src/aarondb/changefeed.gleam", 65).
?DOC(" Add bounded delivery credits. Zero is valid and deliberately changes nothing.\n").
-spec grant(changefeed(), integer()) -> {ok, changefeed()} |
    {error, changefeed_error()}.
grant(Feed, Credit) ->
    case Credit < 0 of
        true ->
            {error, {invalid_credit, Credit}};

        false ->
            {ok,
                {changefeed,
                    erlang:element(2, Feed),
                    erlang:element(3, Feed),
                    erlang:element(4, Feed) + Credit}}
    end.

-file("src/aarondb/changefeed.gleam", 107).
-spec take(list(aarondb@durable_log:entry()), integer()) -> list(aarondb@durable_log:entry()).
take(Entries, Count) ->
    case {Entries, Count > 0} of
        {_, false} ->
            [];

        {[], _} ->
            [];

        {[Entry | Rest], true} ->
            [Entry | take(Rest, Count - 1)]
    end.

-file("src/aarondb/changefeed.gleam", 78).
?DOC(
    " Pull at most the currently granted credit. Delivery does not advance the\n"
    " cursor: only `acknowledge` does, so an interrupted consumer can see a retry.\n"
).
-spec pull(changefeed()) -> {ok,
        {changefeed(), list(aarondb@durable_log:entry())}} |
    {error, changefeed_error()}.
pull(Feed) ->
    case aarondb@durable_log:scan_after(
        erlang:element(2, Feed),
        erlang:element(3, Feed)
    ) of
        {error, Error} ->
            {error, {source, Error}};

        {ok, Entries} ->
            Delivered = take(Entries, erlang:element(4, Feed)),
            {ok,
                {{changefeed,
                        erlang:element(2, Feed),
                        erlang:element(3, Feed),
                        0},
                    Delivered}}
    end.

-file("src/aarondb/changefeed.gleam", 92).
?DOC(
    " Advance only to an offset that was committed by the source. Acknowledge is\n"
    " idempotent for older offsets and never makes an uncommitted event observable.\n"
).
-spec acknowledge(changefeed(), integer()) -> changefeed().
acknowledge(Feed, Offset) ->
    case (Offset > erlang:element(3, Feed)) andalso (Offset < erlang:element(
        3,
        erlang:element(2, Feed)
    )) of
        true ->
            {changefeed,
                erlang:element(2, Feed),
                Offset,
                erlang:element(4, Feed)};

        false ->
            Feed
    end.

-file("src/aarondb/changefeed.gleam", 99).
-spec cursor(changefeed()) -> integer().
cursor(Feed) ->
    erlang:element(3, Feed).

-file("src/aarondb/changefeed.gleam", 103).
-spec credits(changefeed()) -> integer().
credits(Feed) ->
    erlang:element(4, Feed).
