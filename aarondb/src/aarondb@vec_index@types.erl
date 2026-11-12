-module(aarondb@vec_index@types).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/vec_index/types.gleam").
-export_type([layer/0, level_source/0, hnsw_config/0, vec_index/0, search_result/0]).

-type layer() :: {layer,
        gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:entity_id()))}.

-type level_source() :: random_levels | {deterministic_levels, list(integer())}.

-type hnsw_config() :: {hnsw_config, integer(), integer(), level_source()}.

-type vec_index() :: {vec_index,
        gleam@dict:dict(aarondb@fact:entity_id(), list(float())),
        gleam@dict:dict(integer(), layer()),
        gleam@option:option(integer()),
        hnsw_config(),
        {ok, aarondb@fact:entity_id()} | {error, nil},
        integer()}.

-type search_result() :: {search_result, aarondb@fact:entity_id(), float()}.


