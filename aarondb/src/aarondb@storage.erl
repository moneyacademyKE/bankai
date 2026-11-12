-module(aarondb@storage).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/storage.gleam").
-export([insert/2, append/2, read_all/1, query_datoms/2, error_message/1, ephemeral/0]).
-export_type([storage_error/0, storage_adapter/0]).

-type storage_error() :: {storage_error, binary()} |
    {transaction_error, binary()} |
    not_found_error.

-type storage_adapter() :: {storage_adapter,
        fun((list(aarondb@fact:datom())) -> {ok, nil} | {error, storage_error()}),
        fun((list(aarondb@fact:datom())) -> {ok, nil} | {error, storage_error()}),
        fun((binary()) -> {ok, list(aarondb@fact:datom())} |
            {error, storage_error()}),
        fun(() -> {ok, list(aarondb@fact:datom())} | {error, storage_error()}),
        fun(({aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()}) -> {ok,
                list(aarondb@fact:datom())} |
            {error, storage_error()})}.

-file("src/aarondb/storage.gleam", 20).
-spec insert(storage_adapter(), list(aarondb@fact:datom())) -> {ok, nil} |
    {error, storage_error()}.
insert(Adapter, Datoms) ->
    (erlang:element(2, Adapter))(Datoms).

-file("src/aarondb/storage.gleam", 27).
-spec append(storage_adapter(), list(aarondb@fact:datom())) -> {ok, nil} |
    {error, storage_error()}.
append(Adapter, Datoms) ->
    (erlang:element(3, Adapter))(Datoms).

-file("src/aarondb/storage.gleam", 34).
-spec read_all(storage_adapter()) -> {ok, list(aarondb@fact:datom())} |
    {error, storage_error()}.
read_all(Adapter) ->
    (erlang:element(5, Adapter))().

-file("src/aarondb/storage.gleam", 40).
-spec query_datoms(
    storage_adapter(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()}
) -> {ok, list(aarondb@fact:datom())} | {error, storage_error()}.
query_datoms(Adapter, Pattern) ->
    (erlang:element(6, Adapter))(Pattern).

-file("src/aarondb/storage.gleam", 47).
-spec error_message(storage_error()) -> binary().
error_message(Error) ->
    case Error of
        {storage_error, Message} ->
            Message;

        {transaction_error, Reason} ->
            Reason;

        not_found_error ->
            <<"storage record not found"/utf8>>
    end.

-file("src/aarondb/storage.gleam", 55).
-spec ephemeral() -> storage_adapter().
ephemeral() ->
    {storage_adapter,
        fun(_) -> {ok, nil} end,
        fun(_) -> {ok, nil} end,
        fun(_) -> {ok, []} end,
        fun() -> {ok, []} end,
        fun(_) -> {ok, []} end}.
