-module(aarondb@shared@query_types).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/query_types.gleam").
-export_type([shard_map/0, sharded_db/1, pull_result/0, traversal_step/0, query_result/0, query_metadata/0, reactive_delta/0]).

-type shard_map() :: {shard_map,
        gleam@dict:dict(integer(), gleam@erlang@process:pid_()),
        gleam@dict:dict(integer(), integer()),
        list(integer())}.

-type sharded_db(FZX) :: {sharded_db,
        gleam@dict:dict(integer(), FZX),
        integer(),
        binary(),
        shard_map()}.

-type pull_result() :: {pull_map, gleam@dict:dict(binary(), pull_result())} |
    {pull_single, aarondb@fact:value()} |
    {pull_many, list(aarondb@fact:value())} |
    {pull_nested_many, list(pull_result())} |
    {pull_raw_binary, bitstring()}.

-type traversal_step() :: {out, binary()} | {in, binary()}.

-type query_result() :: {query_result,
        list(gleam@dict:dict(binary(), aarondb@fact:value())),
        query_metadata(),
        gleam@option:option(gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk())))}.

-type query_metadata() :: {query_metadata,
        gleam@option:option(integer()),
        gleam@option:option(integer()),
        integer(),
        integer(),
        binary(),
        gleam@option:option(integer()),
        gleam@dict:dict(binary(), aarondb@shared@ast:agg_func())}.

-type reactive_delta() :: {initial, query_result()} |
    {delta, query_result(), query_result()}.


