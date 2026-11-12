-module(aarondb@q).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/q.gleam").
-export([new/0, from_clauses/1, select/1, s/1, i/1, v/1, vec/1, where/4, negate/4, count/4, sum/4, avg/4, median/4, min/4, max/4, similar/4, temporal_at/4, valid_temporal_at/4, since/3, limit/2, offset/2, order_by/3, shortest_path/7, pagerank/6, virtual/4, connected_components/4, reachable/4, neighbors/5, cycle_detect/3, betweenness_centrality/4, topological_sort/4, filter/2, pull/4, cognitive/5, to_clauses/1, to_query/1]).
-export_type([query_builder/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type query_builder() :: {query_builder,
        list(binary()),
        list(aarondb@shared@ast:body_clause()),
        gleam@option:option(aarondb@shared@ast:order_by()),
        gleam@option:option(integer()),
        gleam@option:option(integer())}.

-file("src/aarondb/q.gleam", 18).
-spec new() -> query_builder().
new() ->
    {query_builder, [], [], none, none, none}.

-file("src/aarondb/q.gleam", 22).
-spec from_clauses(list(aarondb@shared@ast:body_clause())) -> query_builder().
from_clauses(Clauses) ->
    {query_builder, [], Clauses, none, none, none}.

-file("src/aarondb/q.gleam", 32).
-spec select(list(binary())) -> query_builder().
select(Vars) ->
    {query_builder, Vars, [], none, none, none}.

-file("src/aarondb/q.gleam", 43).
?DOC(" Helper for string value\n").
-spec s(binary()) -> aarondb@shared@ast:part().
s(Val) ->
    {val, {str, Val}}.

-file("src/aarondb/q.gleam", 48).
?DOC(" Helper for int value\n").
-spec i(integer()) -> aarondb@shared@ast:part().
i(Val) ->
    {val, {int, Val}}.

-file("src/aarondb/q.gleam", 53).
?DOC(" Helper for variable\n").
-spec v(binary()) -> aarondb@shared@ast:part().
v(Name) ->
    {var, Name}.

-file("src/aarondb/q.gleam", 58).
?DOC(" Helper for vector value\n").
-spec vec(list(float())) -> aarondb@shared@ast:part().
vec(Val) ->
    {val, {vec, Val}}.

-file("src/aarondb/q.gleam", 63).
?DOC(" Add a where clause (Entity, Attribute, Value).\n").
-spec where(
    query_builder(),
    aarondb@shared@ast:part(),
    binary(),
    aarondb@shared@ast:part()
) -> query_builder().
where(Builder, Entity, Attr, Value) ->
    Clause = {positive, {Entity, Attr, Value}},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 74).
?DOC(" Add a negative where clause (Entity, Attribute, Value).\n").
-spec negate(
    query_builder(),
    aarondb@shared@ast:part(),
    binary(),
    aarondb@shared@ast:part()
) -> query_builder().
negate(Builder, Entity, Attr, Value) ->
    Clause = {negative, {Entity, Attr, Value}},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 85).
?DOC(" Count aggregate\n").
-spec count(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
count(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, count, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 96).
?DOC(" Sum aggregate\n").
-spec sum(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
sum(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, sum, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 107).
?DOC(" Avg aggregate\n").
-spec avg(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
avg(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, avg, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 118).
?DOC(" Median aggregate\n").
-spec median(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
median(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, median, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 129).
?DOC(" Min aggregate\n").
-spec min(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
min(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, min, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 140).
?DOC(" Max aggregate\n").
-spec max(
    query_builder(),
    binary(),
    binary(),
    list(aarondb@shared@ast:body_clause())
) -> query_builder().
max(Builder, Into, Target, Filter) ->
    Clause = {aggregate, Into, max, {var, Target}, Filter},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 154).
?DOC(
    " Vector similarity search: binds `variable` to entities whose stored vector\n"
    " is within `threshold` of `vector`, resolved by the engine's vector/HNSW\n"
    " index. (Previously this emitted a value-equality `Positive` clause — a\n"
    " placeholder — now it emits the real `ast.Similarity` clause.)\n"
).
-spec similar(query_builder(), binary(), list(float()), float()) -> query_builder().
similar(Builder, Variable, Vector, Threshold) ->
    Clause = {similarity, Variable, {val, {vec, Vector}}, Threshold},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 169).
?DOC(
    " Bind `variable` to the transaction-time basis used by nested clauses.\n"
    "\n"
    " This is an exact `At` query: nested clauses observe only datoms whose\n"
    " transaction id is at most `tx`. For a complete query-level snapshot API,\n"
    " prefer `aarondb.as_of_tx`.\n"
).
-spec temporal_at(
    query_builder(),
    binary(),
    aarondb@shared@ast:part(),
    integer()
) -> query_builder().
temporal_at(Builder, Variable, Entity, Tx) ->
    Clause = {temporal, tx, Tx, at, Variable, Entity, []},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 184).
?DOC(
    " Bind `variable` to the valid-time basis used by nested clauses.\n"
    "\n"
    " This is an exact `At` query: nested clauses observe only datoms whose\n"
    " valid time is at most `valid_time`. For a complete query-level snapshot API,\n"
    " prefer `aarondb.as_of_valid`.\n"
).
-spec valid_temporal_at(
    query_builder(),
    binary(),
    aarondb@shared@ast:part(),
    integer()
) -> query_builder().
valid_temporal_at(Builder, Variable, Entity, Valid_time) ->
    Clause = {temporal, valid, Valid_time, at, Variable, Entity, []},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 195).
?DOC(" Filter results since a specific value (exclusive)\n").
-spec since(query_builder(), binary(), aarondb@shared@ast:part()) -> query_builder().
since(Builder, Variable, Val) ->
    Clause = {filter, {gt, {var, Variable}, Val}},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 205).
?DOC(" Limit results\n").
-spec limit(query_builder(), integer()) -> query_builder().
limit(Builder, N) ->
    {query_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        {some, N},
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 210).
?DOC(" Offset results\n").
-spec offset(query_builder(), integer()) -> query_builder().
offset(Builder, N) ->
    {query_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        {some, N}}.

-file("src/aarondb/q.gleam", 215).
?DOC(" Order results\n").
-spec order_by(query_builder(), binary(), aarondb@shared@ast:order_direction()) -> query_builder().
order_by(Builder, Variable, Direction) ->
    {query_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        {some, {order_by, Variable, Direction}},
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 224).
?DOC(" Find the shortest path between two entities via an edge attribute.\n").
-spec shortest_path(
    query_builder(),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    binary(),
    binary(),
    gleam@option:option(binary()),
    gleam@option:option(integer())
) -> query_builder().
shortest_path(Builder, From, To, Edge, Path_var, Cost_var, Max_depth) ->
    Clause = {shortest_path, From, To, Edge, Path_var, Cost_var, Max_depth},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 238).
?DOC(" Calculate PageRank for nodes connected by an edge.\n").
-spec pagerank(
    query_builder(),
    binary(),
    binary(),
    binary(),
    float(),
    integer()
) -> query_builder().
pagerank(Builder, Entity_var, Edge, Rank_var, Damping, Iterations) ->
    Clause = {page_rank, Entity_var, Edge, Rank_var, Damping, Iterations},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 251).
?DOC(" Query an external data source (Virtual Predicate).\n").
-spec virtual(
    query_builder(),
    binary(),
    list(aarondb@shared@ast:part()),
    list(binary())
) -> query_builder().
virtual(Builder, Predicate, Args, Outputs) ->
    Clause = {virtual, Predicate, Args, Outputs},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 262).
?DOC(" Label each node with a connected component ID.\n").
-spec connected_components(query_builder(), binary(), binary(), binary()) -> query_builder().
connected_components(Builder, Edge, Entity_var, Component_var) ->
    Clause = {connected_components, Edge, Entity_var, Component_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 273).
?DOC(" Find all nodes reachable from a starting node.\n").
-spec reachable(query_builder(), aarondb@shared@ast:part(), binary(), binary()) -> query_builder().
reachable(Builder, From, Edge, Node_var) ->
    Clause = {reachable, From, Edge, Node_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 284).
?DOC(" Find all nodes within K hops of a starting node.\n").
-spec neighbors(
    query_builder(),
    aarondb@shared@ast:part(),
    binary(),
    integer(),
    binary()
) -> query_builder().
neighbors(Builder, From, Edge, Depth, Node_var) ->
    Clause = {neighbors, From, Edge, Depth, Node_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 296).
?DOC(" Detect cycles in directed graph. Each result binds a List of entity refs forming a cycle.\n").
-spec cycle_detect(query_builder(), binary(), binary()) -> query_builder().
cycle_detect(Builder, Edge, Cycle_var) ->
    Clause = {cycle_detect, Edge, Cycle_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 306).
?DOC(" Calculate betweenness centrality (Brandes' algorithm) for each node.\n").
-spec betweenness_centrality(query_builder(), binary(), binary(), binary()) -> query_builder().
betweenness_centrality(Builder, Edge, Entity_var, Score_var) ->
    Clause = {betweenness_centrality, Edge, Entity_var, Score_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 317).
?DOC(" Topological ordering of a DAG. Returns empty if cycles exist.\n").
-spec topological_sort(query_builder(), binary(), binary(), binary()) -> query_builder().
topological_sort(Builder, Edge, Entity_var, Order_var) ->
    Clause = {topological_sort, Edge, Entity_var, Order_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 328).
?DOC(" Generic filter expression.\n").
-spec filter(query_builder(), aarondb@shared@ast:expression()) -> query_builder().
filter(Builder, Expr) ->
    Clause = {filter, Expr},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 334).
?DOC(" Pull attributes for an entity into a variable.\n").
-spec pull(
    query_builder(),
    binary(),
    aarondb@shared@ast:part(),
    list(aarondb@shared@ast:pull_item())
) -> query_builder().
pull(Builder, Variable, Entity, Pattern) ->
    Clause = {pull, Variable, Entity, Pattern},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 345).
?DOC(" Semantic cognitive search over stored concept, context, and relevance facts.\n").
-spec cognitive(
    query_builder(),
    aarondb@shared@ast:part(),
    aarondb@shared@ast:part(),
    float(),
    binary()
) -> query_builder().
cognitive(Builder, Concept, Context, Threshold, Engram_var) ->
    Clause = {cognitive, Concept, Context, Threshold, Engram_var},
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/q.gleam", 358).
?DOC(
    " Convert builder to a list of clauses for backwards compatibility.\n"
    " NOTE: This will lose find/limit/offset/order info.\n"
).
-spec to_clauses(query_builder()) -> list(aarondb@shared@ast:body_clause()).
to_clauses(Builder) ->
    erlang:element(3, Builder).

-file("src/aarondb/q.gleam", 363).
?DOC(" Convert builder to a full Query AST.\n").
-spec to_query(query_builder()) -> aarondb@shared@ast:'query'().
to_query(Builder) ->
    {'query',
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.
