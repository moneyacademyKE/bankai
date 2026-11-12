-module(aarondb@shared@ast).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/ast.gleam").
-export_type([pull_item/0, 'query'/0, order_by/0, part/0, body_clause/0, agg_func/0, order_direction/0, temporal_type/0, temporal_op/0, expression/0, step/0, rule/0, index_query/0]).

-type pull_item() :: wildcard |
    {attr, binary()} |
    {nested, binary(), list(pull_item())} |
    {except, list(binary())} |
    {pull_recursion, binary(), integer()}.

-type 'query'() :: {'query',
        list(binary()),
        list(body_clause()),
        gleam@option:option(order_by()),
        gleam@option:option(integer()),
        gleam@option:option(integer())}.

-type order_by() :: {order_by, binary(), order_direction()}.

-type part() :: {var, binary()} |
    {uid, aarondb@fact:entity_id()} |
    {val, aarondb@fact:value()} |
    {attr_val, binary()} |
    {lookup, {binary(), aarondb@fact:value()}}.

-type body_clause() :: {positive, {part(), binary(), part()}} |
    {negative, {part(), binary(), part()}} |
    {filter, expression()} |
    {bind, part(), part()} |
    {aggregate, binary(), agg_func(), part(), list(body_clause())} |
    {graph_group_by, list(binary())} |
    {group_by, binary()} |
    {limit_clause, integer()} |
    {offset_clause, integer()} |
    {order_by_clause, binary(), order_direction()} |
    {union, list(list(body_clause()))} |
    {subquery, list(body_clause())} |
    {recursion, binary(), list(body_clause())} |
    {temporal,
        temporal_type(),
        integer(),
        temporal_op(),
        binary(),
        part(),
        list(body_clause())} |
    {neighbors, part(), binary(), integer(), binary()} |
    {cycle_detect, binary(), binary()} |
    {betweenness_centrality, binary(), binary(), binary()} |
    {strongly_connected_components, binary(), binary(), binary()} |
    {topological_sort, binary(), binary(), binary()} |
    {connected_components, binary(), binary(), binary()} |
    {reachable, part(), binary(), binary()} |
    {similarity, binary(), part(), float()} |
    {similarity_entity, binary(), part(), float()} |
    {custom_index, binary(), binary(), index_query(), float()} |
    {shortest_path,
        part(),
        part(),
        binary(),
        binary(),
        gleam@option:option(binary()),
        gleam@option:option(integer())} |
    {page_rank, binary(), binary(), binary(), float(), integer()} |
    {starts_with, binary(), binary()} |
    {virtual, binary(), list(part()), list(binary())} |
    {pull, binary(), part(), list(pull_item())} |
    {cognitive, part(), part(), float(), binary()}.

-type agg_func() :: sum | count | min | max | avg | median.

-type order_direction() :: asc | desc.

-type temporal_type() :: tx | valid.

-type temporal_op() :: at | since | until | before | 'after' | range.

-type expression() :: {eq, part(), part()} |
    {neq, part(), part()} |
    {gt, part(), part()} |
    {lt, part(), part()} |
    {'and', expression(), expression()} |
    {'or', expression(), expression()}.

-type step() :: {in, binary()} | {out, binary()}.

-type rule() :: {rule, {part(), binary(), part()}, list(body_clause())}.

-type index_query() :: {text_query, binary()} |
    {numeric_range, float(), float()} |
    {custom, binary()}.


