-module(aarondb@federation).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/federation.gleam").
-export([new/1, query_with_timeout/3, 'query'/2]).
-export_type([source/0, federation/0, federation_error/0, federated_row/0, federated_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Local, in-runtime federation over independently owned AaronDB databases.\n"
    "\n"
    " This module deliberately composes local database actors only. It does not\n"
    " provide remote transport, coordinated writes, failover, quorum, or HA.\n"
).

-type source() :: {source,
        binary(),
        gleam@erlang@process:subject(aarondb@transactor:message())}.

-type federation() :: {federation, list(source())}.

-type federation_error() :: {source_unavailable, binary()} |
    {source_timeout, binary()}.

-type federated_row() :: {federated_row,
        binary(),
        gleam@dict:dict(binary(), aarondb@fact:value())}.

-type federated_result() :: {federated_result,
        list(federated_row()),
        list(binary())}.

-file("src/aarondb/federation.gleam", 151).
-spec schema_attributes(
    gleam@erlang@process:subject(aarondb@transactor:message())
) -> list(binary()).
schema_attributes(Db) ->
    _pipe = erlang:element(8, aarondb@transactor:get_state(Db)),
    _pipe@1 = maps:keys(_pipe),
    gleam@list:sort(_pipe@1, fun gleam@string:compare/2).

-file("src/aarondb/federation.gleam", 129).
-spec validate_schema_compatibility(list(source())) -> {ok, federation()} |
    {error, binary()}.
validate_schema_compatibility(Sources) ->
    case Sources of
        [] ->
            {error, <<"A federation requires at least one source"/utf8>>};

        [First | Rest] ->
            {source, _, First_db} = First,
            Expected = schema_attributes(First_db),
            case gleam@list:all(
                Rest,
                fun(Source) ->
                    {source, _, Db} = Source,
                    schema_attributes(Db) =:= Expected
                end
            ) of
                true ->
                    {ok, {federation, Sources}};

                false ->
                    {error,
                        <<"Federation sources must declare the same schema attributes"/utf8>>}
            end
    end.

-file("src/aarondb/federation.gleam", 113).
-spec validate_names(list(source()), list(binary())) -> {ok, nil} |
    {error, binary()}.
validate_names(Sources, Seen) ->
    case Sources of
        [] ->
            {ok, nil};

        [{source, Name, _} | _] when Name =:= <<""/utf8>> ->
            {error, <<"Federation source names cannot be empty"/utf8>>};

        [{source, Name@1, _} | Rest] ->
            case gleam@list:contains(Seen, Name@1) of
                true ->
                    {error,
                        <<"Duplicate federation source: "/utf8, Name@1/binary>>};

                false ->
                    validate_names(Rest, [Name@1 | Seen])
            end
    end.

-file("src/aarondb/federation.gleam", 43).
?DOC(
    " Construct a local federation.\n"
    "\n"
    " Source names must be non-empty and unique. Every source must expose the\n"
    " same set of declared schema attributes. This is a compatibility guard, not\n"
    " schema negotiation: callers own schema rollout across their databases.\n"
).
-spec new(list(source())) -> {ok, federation()} | {error, binary()}.
new(Sources) ->
    case Sources of
        [] ->
            {error, <<"A federation requires at least one source"/utf8>>};

        _ ->
            case validate_names(Sources, []) of
                {error, Error} ->
                    {error, Error};

                {ok, _} ->
                    validate_schema_compatibility(Sources)
            end
    end.

-file("src/aarondb/federation.gleam", 79).
-spec query_sources(
    list(source()),
    aarondb@shared@ast:'query'(),
    integer(),
    list(federated_row()),
    list(binary())
) -> {ok, federated_result()} | {error, federation_error()}.
query_sources(Sources, Query, Timeout_ms, Rows, Names) ->
    case Sources of
        [] ->
            {ok, {federated_result, Rows, Names}};

        [{source, Name, Db} | Rest] ->
            case aarondb_process_ffi:is_alive(Db) of
                false ->
                    {error, {source_unavailable, Name}};

                true ->
                    case aarondb@transactor:get_state_with_timeout(
                        Db,
                        Timeout_ms
                    ) of
                        {error, _} ->
                            {error, {source_timeout, Name}};

                        {ok, Source_state} ->
                            Result = aarondb@engine:run(
                                Source_state,
                                Query,
                                [],
                                none,
                                none
                            ),
                            Sourced_rows = gleam@list:map(
                                erlang:element(2, Result),
                                fun(Row) -> {federated_row, Name, Row} end
                            ),
                            query_sources(
                                Rest,
                                Query,
                                Timeout_ms,
                                lists:append(Rows, Sourced_rows),
                                lists:append(Names, [Name])
                            )
                    end
            end
    end.

-file("src/aarondb/federation.gleam", 157).
-spec compare_source(source(), source()) -> gleam@order:order().
compare_source(Left, Right) ->
    {source, Left_name, _} = Left,
    {source, Right_name, _} = Right,
    gleam@string:compare(Left_name, Right_name).

-file("src/aarondb/federation.gleam", 59).
?DOC(
    " Run a query against every live source in stable source-name order.\n"
    "\n"
    " This is the fail-fast federation API. It returns no result if any source is\n"
    " unavailable or fails to reply before `timeout_ms`; callers therefore cannot\n"
    " accidentally treat partial source successes as a complete federated read.\n"
).
-spec query_with_timeout(federation(), aarondb@shared@ast:'query'(), integer()) -> {ok,
        federated_result()} |
    {error, federation_error()}.
query_with_timeout(Federation, Query, Timeout_ms) ->
    {federation, Sources} = Federation,
    Ordered_sources = gleam@list:sort(Sources, fun compare_source/2),
    query_sources(Ordered_sources, Query, Timeout_ms, [], []).

-file("src/aarondb/federation.gleam", 72).
?DOC(
    " Run a query using the default five-second source deadline.\n"
    "\n"
    " See `query_with_timeout` for the fail-fast failure contract.\n"
).
-spec 'query'(federation(), aarondb@shared@ast:'query'()) -> {ok,
        federated_result()} |
    {error, federation_error()}.
'query'(Federation, Query) ->
    query_with_timeout(Federation, Query, 5000).
