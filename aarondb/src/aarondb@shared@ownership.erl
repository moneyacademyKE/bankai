-module(aarondb@shared@ownership).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/ownership.gleam").
-export([view/1]).
-export_type([facts/0, indexes/0, runtime/0, extensions/0, operations/0, view/0]).

-type facts() :: {facts,
        gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
        gleam@dict:dict(binary(), list(aarondb@fact:datom())),
        gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
        integer(),
        gleam@dict:dict(binary(), aarondb@fact:attribute_config())}.

-type indexes() :: {indexes,
        aarondb@vec_index:vec_index(),
        gleam@dict:dict(binary(), aarondb@index@bm25:b_m25_index()),
        aarondb@index@art:art(),
        gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))}.

-type runtime() :: {runtime,
        aarondb@storage:storage_adapter(),
        list(gleam@erlang@process:subject(list(aarondb@fact:datom()))),
        gleam@erlang@process:subject(aarondb@shared@state:reactive_message()),
        list(gleam@erlang@process:pid_()),
        boolean(),
        gleam@option:option(binary())}.

-type extensions() :: {extensions,
        gleam@dict:dict(binary(), fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
            binary(),
            aarondb@fact:value()}))),
        list(list(binary())),
        gleam@dict:dict(binary(), aarondb@shared@state:index_adapter()),
        gleam@dict:dict(binary(), aarondb@shared@state:extension_instance()),
        gleam@dict:dict(binary(), fun((aarondb@fact:value()) -> boolean())),
        list(aarondb@shared@ast:rule()),
        gleam@dict:dict(binary(), aarondb@shared@state:virtual_adapter())}.

-type operations() :: {operations,
        aarondb@shared@state:config(),
        list(aarondb@shared@state:query_context())}.

-type view() :: {view,
        facts(),
        indexes(),
        runtime(),
        extensions(),
        operations()}.

-file("src/aarondb/shared/ownership.gleam", 76).
-spec view(aarondb@shared@state:db_state()) -> view().
view(Db) ->
    {view,
        {facts,
            erlang:element(3, Db),
            erlang:element(4, Db),
            erlang:element(5, Db),
            erlang:element(6, Db),
            erlang:element(8, Db)},
        {indexes,
            erlang:element(15, Db),
            erlang:element(16, Db),
            erlang:element(17, Db),
            erlang:element(23, Db)},
        {runtime,
            erlang:element(2, Db),
            erlang:element(7, Db),
            erlang:element(11, Db),
            erlang:element(12, Db),
            erlang:element(13, Db),
            erlang:element(14, Db)},
        {extensions,
            erlang:element(9, Db),
            erlang:element(10, Db),
            erlang:element(18, Db),
            erlang:element(19, Db),
            erlang:element(20, Db),
            erlang:element(21, Db),
            erlang:element(22, Db)},
        {operations, erlang:element(24, Db), erlang:element(25, Db)}}.
