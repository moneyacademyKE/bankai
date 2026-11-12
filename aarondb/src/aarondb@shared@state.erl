-module(aarondb@shared@state).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/state.gleam").
-export([virtual_adapter/2]).
-export_type([config/0, query_context/0, index_adapter/0, extension_instance/0, index_query/0, db_state/0, reactive_message/0, virtual_adapter/0, virtual_adapter_error/0]).

-type config() :: {config, integer(), integer(), boolean(), integer()}.

-type query_context() :: {query_context,
        list(binary()),
        list(aarondb@fact:entity_id()),
        integer()}.

-type index_adapter() :: {index_adapter,
        binary(),
        fun((binary()) -> gleam@dynamic:dynamic_()),
        fun((gleam@dynamic:dynamic_(), list(aarondb@fact:datom())) -> gleam@dynamic:dynamic_()),
        fun((gleam@dynamic:dynamic_(), index_query(), float()) -> list(aarondb@fact:entity_id()))}.

-type extension_instance() :: {extension_instance,
        binary(),
        binary(),
        gleam@dynamic:dynamic_()}.

-type index_query() :: {text_query, binary()} |
    {numeric_range, float(), float()} |
    {custom, binary()}.

-type db_state() :: {db_state,
        aarondb@storage:storage_adapter(),
        gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
        gleam@dict:dict(binary(), list(aarondb@fact:datom())),
        gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
        integer(),
        list(gleam@erlang@process:subject(list(aarondb@fact:datom()))),
        gleam@dict:dict(binary(), aarondb@fact:attribute_config()),
        gleam@dict:dict(binary(), fun((db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
            binary(),
            aarondb@fact:value()}))),
        list(list(binary())),
        gleam@erlang@process:subject(reactive_message()),
        list(gleam@erlang@process:pid_()),
        boolean(),
        gleam@option:option(binary()),
        aarondb@vec_index:vec_index(),
        gleam@dict:dict(binary(), aarondb@index@bm25:b_m25_index()),
        aarondb@index@art:art(),
        gleam@dict:dict(binary(), index_adapter()),
        gleam@dict:dict(binary(), extension_instance()),
        gleam@dict:dict(binary(), fun((aarondb@fact:value()) -> boolean())),
        list(aarondb@shared@ast:rule()),
        gleam@dict:dict(binary(), virtual_adapter()),
        gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())),
        config(),
        list(query_context())}.

-type reactive_message() :: {subscribe,
        aarondb@shared@ast:'query'(),
        list(binary()),
        gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta()),
        aarondb@shared@query_types:query_result()} |
    {unsubscribe,
        gleam@erlang@process:subject(aarondb@shared@query_types:reactive_delta())} |
    {notify, list(binary()), db_state()}.

-type virtual_adapter() :: {virtual_adapter,
        fun((list(aarondb@fact:value())) -> {ok,
                list(list(aarondb@fact:value()))} |
            {error, virtual_adapter_error()}),
        integer()}.

-type virtual_adapter_error() :: invalid_virtual_row_limit |
    {virtual_adapter_failed, binary()} |
    virtual_adapter_timed_out |
    virtual_row_limit_exceeded.

-file("src/aarondb/shared/state.gleam", 112).
-spec virtual_adapter(
    fun((list(aarondb@fact:value())) -> {ok, list(list(aarondb@fact:value()))} |
        {error, virtual_adapter_error()}),
    integer()
) -> {ok, virtual_adapter()} | {error, virtual_adapter_error()}.
virtual_adapter(Execute, Max_rows) ->
    case Max_rows > 0 of
        true ->
            {ok, {virtual_adapter, Execute, Max_rows}};

        false ->
            {error, invalid_virtual_row_limit}
    end.
