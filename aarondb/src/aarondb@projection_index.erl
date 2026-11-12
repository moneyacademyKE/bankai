-module(aarondb@projection_index).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/projection_index.gleam").
-export([new/1, apply/3, 'query'/1, begin_rebuild/2, swap/3, degrade/2, fail/2, failure_reason/1]).
-export_type([health/0, index/0, error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # projection_index — non-authoritative index lifecycle\n"
    "\n"
    " Index state is a replayable projection of an ordered source. Queries are only\n"
    " available while the index is healthy; the source remains authoritative.\n"
).

-type health() :: building |
    rebuilding |
    queryable |
    {degraded, binary()} |
    {failed, binary()}.

-type index() :: {index,
        integer(),
        integer(),
        health(),
        integer(),
        list(binary())}.

-type error() :: invalid_schema_version |
    {offset_gap, integer(), integer()} |
    {not_queryable, health()}.

-file("src/aarondb/projection_index.gleam", 33).
-spec new(integer()) -> {ok, index()} | {error, error()}.
new(Schema_version) ->
    case Schema_version > 0 of
        true ->
            {ok, {index, Schema_version, 0, building, -1, []}};

        false ->
            {error, invalid_schema_version}
    end.

-file("src/aarondb/projection_index.gleam", 59).
-spec next_health(health()) -> health().
next_health(Health) ->
    case Health of
        rebuilding ->
            rebuilding;

        _ ->
            queryable
    end.

-file("src/aarondb/projection_index.gleam", 40).
-spec apply(index(), integer(), binary()) -> {ok, index()} | {error, error()}.
apply(Index, Offset, Value) ->
    case Offset =< erlang:element(5, Index) of
        true ->
            {ok, Index};

        false ->
            case Offset =:= (erlang:element(5, Index) + 1) of
                true ->
                    {ok,
                        {index,
                            erlang:element(2, Index),
                            erlang:element(3, Index),
                            next_health(erlang:element(4, Index)),
                            Offset,
                            lists:append(erlang:element(6, Index), [Value])}};

                false ->
                    {error, {offset_gap, erlang:element(5, Index) + 1, Offset}}
            end
    end.

-file("src/aarondb/projection_index.gleam", 66).
-spec 'query'(index()) -> {ok, list(binary())} | {error, error()}.
'query'(Index) ->
    case erlang:element(4, Index) of
        queryable ->
            {ok, erlang:element(6, Index)};

        Other ->
            {error, {not_queryable, Other}}
    end.

-file("src/aarondb/projection_index.gleam", 74).
?DOC(" Marks the current projection unavailable while a separate generation is built.\n").
-spec begin_rebuild(index(), integer()) -> {ok, index()} | {error, error()}.
begin_rebuild(Index, Schema_version) ->
    case Schema_version > 0 of
        true ->
            {ok,
                {index,
                    Schema_version,
                    erlang:element(3, Index) + 1,
                    rebuilding,
                    -1,
                    []}};

        false ->
            {error, invalid_schema_version}
    end.

-file("src/aarondb/projection_index.gleam", 86).
?DOC(
    " The caller swaps only a fully caught-up replacement. This makes a partial\n"
    " rebuild unqueryable instead of returning silently incomplete answers.\n"
).
-spec swap(index(), index(), integer()) -> {ok, index()} | {error, error()}.
swap(_, Replacement, Source_high_watermark) ->
    case erlang:element(5, Replacement) =:= Source_high_watermark of
        true ->
            {ok,
                {index,
                    erlang:element(2, Replacement),
                    erlang:element(3, Replacement),
                    queryable,
                    erlang:element(5, Replacement),
                    erlang:element(6, Replacement)}};

        false ->
            {error,
                {offset_gap,
                    Source_high_watermark,
                    erlang:element(5, Replacement)}}
    end.

-file("src/aarondb/projection_index.gleam", 98).
-spec degrade(index(), binary()) -> index().
degrade(Index, Reason) ->
    {index,
        erlang:element(2, Index),
        erlang:element(3, Index),
        {degraded, Reason},
        erlang:element(5, Index),
        erlang:element(6, Index)}.

-file("src/aarondb/projection_index.gleam", 102).
-spec fail(index(), binary()) -> index().
fail(Index, Reason) ->
    {index,
        erlang:element(2, Index),
        erlang:element(3, Index),
        {failed, Reason},
        erlang:element(5, Index),
        erlang:element(6, Index)}.

-file("src/aarondb/projection_index.gleam", 106).
-spec failure_reason(index()) -> gleam@option:option(binary()).
failure_reason(Index) ->
    case erlang:element(4, Index) of
        {degraded, Reason} ->
            {some, Reason};

        {failed, Reason@1} ->
            {some, Reason@1};

        _ ->
            none
    end.
