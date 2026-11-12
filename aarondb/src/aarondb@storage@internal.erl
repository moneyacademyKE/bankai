-module(aarondb@storage@internal).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/storage/internal.gleam").
-export_type([cracking_node/0, storage_chunk/0, storage_layout/0, retention/0, storage_tier/0, eviction_policy/0, cardinality/0, attribute_config/0]).

-type cracking_node() :: {leaf, list(aarondb@fact:value())} |
    {branch, aarondb@fact:value(), cracking_node(), cracking_node()}.

-type storage_chunk() :: {storage_chunk,
        binary(),
        cracking_node(),
        integer(),
        boolean()}.

-type storage_layout() :: row | columnar.

-type retention() :: all | latest_only | {last, integer()}.

-type storage_tier() :: memory | disk | cloud.

-type eviction_policy() :: always_in_memory | lru_to_disk | lru_to_cloud.

-type cardinality() :: many | one.

-type attribute_config() :: {attribute_config,
        boolean(),
        boolean(),
        retention(),
        cardinality(),
        gleam@option:option(binary()),
        gleam@option:option(binary()),
        storage_layout(),
        storage_tier(),
        eviction_policy()}.


