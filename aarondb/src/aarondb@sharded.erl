-module(aarondb@sharded).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/sharded.gleam").
-export([start_sharded/3, start_local_sharded/3, transact/2, transact_shard/3, query_at/4, 'query'/2, bloom_query/4, global_vector_search/4, stop/1, calculate_migration_plan/2, migrate_shard_data/4, rebalance/1, add_shard/2]).
-export_type([migration_plan/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type migration_plan() :: {migration_plan,
        list({integer(),
            list({aarondb@fact:eid(), binary(), aarondb@fact:value()})})}.

-file("src/aarondb/sharded.gleam", 626).
-spec create_shard_map(
    gleam@dict:dict(integer(), gleam@erlang@process:subject(aarondb@transactor:message()))
) -> aarondb@shared@query_types:shard_map().
create_shard_map(Shards) ->
    Vnode_count = 100,
    Vnodes = begin
        _pipe = maps:to_list(Shards),
        gleam@list:fold(
            _pipe,
            maps:new(),
            fun(Acc, Pair) ->
                {Shard_id, _} = Pair,
                _pipe@1 = lists:seq(0, Vnode_count),
                gleam@list:fold(
                    _pipe@1,
                    Acc,
                    fun(V_acc, I) ->
                        V_hash = erlang:phash2(
                            {str,
                                <<<<(gleam@string:inspect(Shard_id))/binary,
                                        ":"/utf8>>/binary,
                                    (gleam@string:inspect(I))/binary>>}
                        ),
                        gleam@dict:insert(V_acc, V_hash, Shard_id)
                    end
                )
            end
        )
    end,
    Sorted_hashes = begin
        _pipe@2 = maps:keys(Vnodes),
        gleam@list:sort(_pipe@2, fun gleam@int:compare/2)
    end,
    Nodes = begin
        _pipe@3 = maps:to_list(Shards),
        gleam@list:fold(
            _pipe@3,
            maps:new(),
            fun(Acc@1, Pair@1) ->
                {Id, Sub} = Pair@1,
                Pid@1 = case gleam@erlang@process:subject_owner(Sub) of
                    {ok, Pid} -> Pid;
                    _assert_fail ->
                        erlang:error(#{gleam_error => let_assert,
                                    message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                    file => <<?FILEPATH/utf8>>,
                                    module => <<"aarondb/sharded"/utf8>>,
                                    function => <<"create_shard_map"/utf8>>,
                                    line => 650,
                                    value => _assert_fail,
                                    start => 20046,
                                    'end' => 20093,
                                    pattern_start => 20057,
                                    pattern_end => 20064})
                end,
                gleam@dict:insert(Acc@1, Id, Pid@1)
            end
        )
    end,
    {shard_map, Nodes, Vnodes, Sorted_hashes}.

-file("src/aarondb/sharded.gleam", 661).
-spec string_inspect_actor_error(gleam@otp@actor:start_error()) -> binary().
string_inspect_actor_error(E) ->
    gleam@string:inspect(E).

-file("src/aarondb/sharded.gleam", 31).
?DOC(" Start a sharded database cluster.\n").
-spec start_sharded(
    binary(),
    integer(),
    gleam@option:option(aarondb@storage:storage_adapter())
) -> {ok,
        aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))} |
    {error, binary()}.
start_sharded(Cluster_id, Shard_count, Adapter) ->
    Self = gleam@erlang@process:new_subject(),
    _pipe = gleam@list:fold(
        lists:seq(1, Shard_count),
        [],
        fun(Acc, I) -> [I | Acc] end
    ),
    gleam@list:each(
        _pipe,
        fun(I@1) ->
            proc_lib:spawn_link(
                fun() ->
                    Shard_cluster_id = <<<<Cluster_id/binary, "_s"/utf8>>/binary,
                        (gleam@string:inspect(I@1))/binary>>,
                    Res = case aarondb:start_distributed(
                        Shard_cluster_id,
                        Adapter
                    ) of
                        {ok, Db} ->
                            {ok, {I@1, Db}};

                        {error, E} ->
                            {error,
                                <<<<<<"Failed to start shard "/utf8,
                                            (gleam@string:inspect(I@1))/binary>>/binary,
                                        ": "/utf8>>/binary,
                                    (string_inspect_actor_error(E))/binary>>}
                    end,
                    gleam@erlang@process:send(Self, Res)
                end
            )
        end
    ),
    Shards = begin
        _pipe@1 = gleam@list:fold(
            lists:seq(1, Shard_count),
            [],
            fun(Acc@1, _) ->
                case gleam@erlang@process:'receive'(Self, 600000) of
                    {ok, Res@1} ->
                        [Res@1 | Acc@1];

                    {error, _} ->
                        [{error, <<"Timeout starting shards"/utf8>>} | Acc@1]
                end
            end
        ),
        gleam@list:try_map(_pipe@1, fun(X) -> X end)
    end,
    case Shards of
        {ok, S} ->
            Shard_dicts = maps:from_list(S),
            Shard_map = create_shard_map(Shard_dicts),
            {ok, {sharded_db, Shard_dicts, Shard_count, Cluster_id, Shard_map}};

        {error, E@1} ->
            {error, E@1}
    end.

-file("src/aarondb/sharded.gleam", 83).
?DOC(" Start a sharded database cluster in local (named) mode.\n").
-spec start_local_sharded(
    binary(),
    integer(),
    gleam@option:option(aarondb@storage:storage_adapter())
) -> {ok,
        aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))} |
    {error, binary()}.
start_local_sharded(Cluster_id, Shard_count, Adapter) ->
    Self = gleam@erlang@process:new_subject(),
    _pipe = gleam@list:fold(
        lists:seq(1, Shard_count),
        [],
        fun(Acc, I) -> [I | Acc] end
    ),
    gleam@list:each(
        _pipe,
        fun(I@1) ->
            proc_lib:spawn_link(
                fun() ->
                    Shard_cluster_id = <<<<Cluster_id/binary, "_s"/utf8>>/binary,
                        (gleam@string:inspect(I@1))/binary>>,
                    Res = case aarondb:start_distributed(
                        Shard_cluster_id,
                        Adapter
                    ) of
                        {ok, Db} ->
                            {ok, {I@1, Db}};

                        {error, E} ->
                            {error,
                                <<<<<<"Failed to start local shard "/utf8,
                                            (gleam@string:inspect(I@1))/binary>>/binary,
                                        ": "/utf8>>/binary,
                                    (string_inspect_actor_error(E))/binary>>}
                    end,
                    gleam@erlang@process:send(Self, Res)
                end
            )
        end
    ),
    Shards = begin
        _pipe@1 = gleam@list:fold(
            lists:seq(1, Shard_count),
            [],
            fun(Acc@1, _) ->
                case gleam@erlang@process:'receive'(Self, 300000) of
                    {ok, Res@1} ->
                        [Res@1 | Acc@1];

                    {error, _} ->
                        [{error, <<"Timeout starting shards"/utf8>>} | Acc@1]
                end
            end
        ),
        gleam@list:try_map(_pipe@1, fun(X) -> X end)
    end,
    case Shards of
        {ok, S} ->
            Shard_dicts = maps:from_list(S),
            Shard_map = create_shard_map(Shard_dicts),
            {ok, {sharded_db, Shard_dicts, Shard_count, Cluster_id, Shard_map}};

        {error, E@1} ->
            {error, E@1}
    end.

-file("src/aarondb/sharded.gleam", 136).
?DOC(
    " Ingest facts into the sharded database in parallel.\n"
    " Routing is determined by hashing the Entity ID (Eid).\n"
).
-spec transact(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, list(aarondb@shared@state:db_state())} | {error, binary()}.
transact(Db, Facts) ->
    case aarondb@sharding@semantics:group_facts(
        Facts,
        erlang:element(3, erlang:element(5, Db)),
        erlang:element(4, erlang:element(5, Db))
    ) of
        {error, Error} ->
            {error, Error};

        {ok, Grouped} ->
            Grouped_list = maps:to_list(Grouped),
            case Grouped_list of
                [] ->
                    {ok, []};

                _ ->
                    Self = gleam@erlang@process:new_subject(),
                    gleam@list:each(
                        Grouped_list,
                        fun(Pair) ->
                            {Shard_id, Shard_facts} = Pair,
                            proc_lib:spawn_link(
                                fun() ->
                                    Shard_db@1 = case gleam_stdlib:map_get(
                                        erlang:element(2, Db),
                                        Shard_id
                                    ) of
                                        {ok, Shard_db} -> Shard_db;
                                        _assert_fail ->
                                            erlang:error(
                                                    #{gleam_error => let_assert,
                                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                        file => <<?FILEPATH/utf8>>,
                                                        module => <<"aarondb/sharded"/utf8>>,
                                                        function => <<"transact"/utf8>>,
                                                        line => 157,
                                                        value => _assert_fail,
                                                        start => 4259,
                                                        'end' => 4314,
                                                        pattern_start => 4270,
                                                        pattern_end => 4282}
                                                )
                                    end,
                                    Res = case aarondb@transactor:transact(
                                        Shard_db@1,
                                        Shard_facts
                                    ) of
                                        {ok, State} ->
                                            {ok, State};

                                        {error, E} ->
                                            {error,
                                                <<<<<<"Shard "/utf8,
                                                            (gleam@string:inspect(
                                                                Shard_id
                                                            ))/binary>>/binary,
                                                        " transact failed: "/utf8>>/binary,
                                                    E/binary>>}
                                    end,
                                    gleam@erlang@process:send(Self, Res)
                                end
                            )
                        end
                    ),
                    _pipe = gleam@list:fold(
                        lists:seq(1, erlang:length(Grouped_list)),
                        [],
                        fun(Acc, _) ->
                            Res@2 = case gleam@erlang@process:'receive'(
                                Self,
                                15000
                            ) of
                                {ok, Res@1} ->
                                    Res@1;

                                {error, _} ->
                                    {error,
                                        <<"Timeout waiting for shard"/utf8>>}
                            end,
                            [Res@2 | Acc]
                        end
                    ),
                    gleam@list:try_map(_pipe, fun(X) -> X end)
            end
    end.

-file("src/aarondb/sharded.gleam", 186).
?DOC(" Transact on a specific shard regardless of entity hashing.\n").
-spec transact_shard(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    integer(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()})
) -> {ok, aarondb@shared@state:db_state()} | {error, binary()}.
transact_shard(Db, Shard_id, Facts) ->
    case gleam_stdlib:map_get(erlang:element(2, Db), Shard_id) of
        {ok, Shard_db} ->
            aarondb@transactor:transact(Shard_db, Facts);

        {error, _} ->
            {error,
                <<<<"Shard "/utf8, (gleam@string:inspect(Shard_id))/binary>>/binary,
                    " not found"/utf8>>}
    end.

-file("src/aarondb/sharded.gleam", 465).
-spec aarondb_aggregate(
    list(aarondb@fact:value()),
    aarondb@shared@ast:agg_func()
) -> {ok, aarondb@fact:value()} | {error, binary()}.
aarondb_aggregate(Vals, Func) ->
    aarondb@algo@aggregate:aggregate(Vals, Func).

-file("src/aarondb/sharded.gleam", 408).
-spec coordinate_reduce(
    list(gleam@dict:dict(binary(), aarondb@fact:value())),
    gleam@dict:dict(binary(), aarondb@shared@ast:agg_func())
) -> list(gleam@dict:dict(binary(), aarondb@fact:value())).
coordinate_reduce(Rows, Aggregates) ->
    case Rows of
        [] ->
            [];

        [First_row | _] ->
            Grouping_vars = begin
                _pipe = maps:keys(First_row),
                gleam@list:filter(
                    _pipe,
                    fun(K) -> not gleam@dict:has_key(Aggregates, K) end
                )
            end,
            Grouped = gleam@list:fold(
                Rows,
                maps:new(),
                fun(Acc, Row) ->
                    Group_key = gleam@list:map(
                        Grouping_vars,
                        fun(V) -> _pipe@1 = gleam_stdlib:map_get(Row, V),
                            gleam@result:unwrap(_pipe@1, {int, 0}) end
                    ),
                    Members = begin
                        _pipe@2 = gleam_stdlib:map_get(Acc, Group_key),
                        gleam@result:unwrap(_pipe@2, [])
                    end,
                    gleam@dict:insert(Acc, Group_key, [Row | Members])
                end
            ),
            _pipe@3 = maps:to_list(Grouped),
            gleam@list:map(
                _pipe@3,
                fun(Pair) ->
                    {Key_vals, Members@1} = Pair,
                    Base_row = begin
                        _pipe@4 = gleam@list:zip(Grouping_vars, Key_vals),
                        maps:from_list(_pipe@4)
                    end,
                    _pipe@5 = maps:to_list(Aggregates),
                    gleam@list:fold(
                        _pipe@5,
                        Base_row,
                        fun(Row_acc, Agg_pair) ->
                            {Var, Func} = Agg_pair,
                            Shard_vals = gleam@list:filter_map(
                                Members@1,
                                fun(M) -> gleam_stdlib:map_get(M, Var) end
                            ),
                            Final_val = begin
                                Secondary = case Func of
                                    count ->
                                        sum;

                                    Other ->
                                        Other
                                end,
                                _pipe@6 = aarondb_aggregate(
                                    Shard_vals,
                                    Secondary
                                ),
                                gleam@result:unwrap(_pipe@6, {int, 0})
                            end,
                            gleam@dict:insert(Row_acc, Var, Final_val)
                        end
                    )
                end
            )
    end.

-file("src/aarondb/sharded.gleam", 207).
?DOC(" Query the sharded database at a specific temporal basis.\n").
-spec query_at(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    aarondb@shared@ast:'query'(),
    gleam@option:option(integer()),
    gleam@option:option(integer())
) -> aarondb@shared@query_types:query_result().
query_at(Db, Query, As_of_tx, As_of_valid) ->
    Shard_list = maps:to_list(erlang:element(2, Db)),
    Self = gleam@erlang@process:new_subject(),
    gleam@list:each(
        Shard_list,
        fun(Pair) ->
            {_, Shard_db} = Pair,
            proc_lib:spawn_link(
                fun() ->
                    Res = aarondb@engine:run(
                        aarondb:get_state(Shard_db),
                        Query,
                        [],
                        As_of_tx,
                        As_of_valid
                    ),
                    gleam@erlang@process:send(Self, Res)
                end
            )
        end
    ),
    gleam@list:fold(
        lists:seq(1, erlang:length(Shard_list)),
        {query_result,
            [],
            {query_metadata, none, none, 0, 0, <<""/utf8>>, none, maps:new()},
            none},
        fun(Acc, _) ->
            Res@1 = begin
                _pipe = gleam@erlang@process:'receive'(Self, 15000),
                gleam@result:unwrap(
                    _pipe,
                    {query_result,
                        [],
                        {query_metadata,
                            none,
                            none,
                            0,
                            0,
                            <<""/utf8>>,
                            none,
                            maps:new()},
                        none}
                )
            end,
            Merged_metadata = {query_metadata,
                case {erlang:element(2, erlang:element(3, Acc)),
                    erlang:element(2, erlang:element(3, Res@1))} of
                    {{some, A}, {some, B}} ->
                        {some, gleam@int:max(A, B)};

                    {{some, _}, none} ->
                        erlang:element(2, erlang:element(3, Acc));

                    {none, {some, _}} ->
                        erlang:element(2, erlang:element(3, Res@1));

                    {none, none} ->
                        none
                end,
                case {erlang:element(3, erlang:element(3, Acc)),
                    erlang:element(3, erlang:element(3, Res@1))} of
                    {{some, A@1}, {some, B@1}} ->
                        {some, gleam@int:max(A@1, B@1)};

                    {{some, _}, none} ->
                        erlang:element(3, erlang:element(3, Acc));

                    {none, {some, _}} ->
                        erlang:element(3, erlang:element(3, Res@1));

                    {none, none} ->
                        none
                end,
                erlang:element(4, erlang:element(3, Acc)) + erlang:element(
                    4,
                    erlang:element(3, Res@1)
                ),
                erlang:element(5, erlang:element(3, Acc)) + erlang:element(
                    5,
                    erlang:element(3, Res@1)
                ),
                erlang:element(6, erlang:element(3, Acc)),
                none,
                maps:merge(
                    erlang:element(8, erlang:element(3, Acc)),
                    erlang:element(8, erlang:element(3, Res@1))
                )},
            All_rows = lists:append(
                erlang:element(2, Acc),
                erlang:element(2, Res@1)
            ),
            case maps:size(erlang:element(8, Merged_metadata)) > 0 of
                true ->
                    Rows = coordinate_reduce(
                        All_rows,
                        erlang:element(8, Merged_metadata)
                    ),
                    {query_result, Rows, Merged_metadata, none};

                false ->
                    {query_result, All_rows, Merged_metadata, none}
            end
        end
    ).

-file("src/aarondb/sharded.gleam", 199).
?DOC(
    " Query the sharded database (Parallel Scatter-Gather).\n"
    " Warning: This performs a full scan across all shards.\n"
).
-spec 'query'(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    aarondb@shared@ast:'query'()
) -> aarondb@shared@query_types:query_result().
'query'(Db, Query) ->
    query_at(Db, Query, none, none).

-file("src/aarondb/sharded.gleam", 316).
?DOC(
    " Perform a Bloom Filter Optimized distributed join.\n"
    " This runs in two passes:\n"
    " 1. Probe: Executes the probe clauses to identify join keys.\n"
    " 2. Build: Executes the build clauses on shards using a Bloom filter of identified keys.\n"
).
-spec bloom_query(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    binary(),
    list(aarondb@shared@ast:body_clause()),
    list(aarondb@shared@ast:body_clause())
) -> aarondb@shared@query_types:query_result().
bloom_query(Db, Join_var, Probe_clauses, Build_clauses) ->
    Probe_res = 'query'(Db, {'query', [], Probe_clauses, none, none, none}),
    Keys = begin
        _pipe = gleam@list:fold(
            erlang:element(2, Probe_res),
            [],
            fun(Acc, Row) -> case gleam_stdlib:map_get(Row, Join_var) of
                    {ok, Val} ->
                        [aarondb@fact:to_string(Val) | Acc];

                    {error, _} ->
                        Acc
                end end
        ),
        gleam@list:unique(_pipe)
    end,
    Filter_size = gleam@int:max(1024, erlang:length(Keys) * 10),
    _ = gleam@list:fold(
        Keys,
        aarondb@algo@bloom:new(Filter_size, 3),
        fun(F, K) -> aarondb@algo@bloom:insert(F, K) end
    ),
    Build_res = 'query'(Db, {'query', [], Build_clauses, none, none, none}),
    Final_rows = gleam@list:fold(
        erlang:element(2, Probe_res),
        [],
        fun(Acc@1, Probe_row) ->
            Probe_val = gleam_stdlib:map_get(Probe_row, Join_var),
            Matching_build = gleam@list:filter(
                erlang:element(2, Build_res),
                fun(Build_row) ->
                    gleam_stdlib:map_get(Build_row, Join_var) =:= Probe_val
                end
            ),
            _pipe@1 = gleam@list:map(
                Matching_build,
                fun(Br) -> maps:merge(Probe_row, Br) end
            ),
            lists:append(_pipe@1, Acc@1)
        end
    ),
    {query_result,
        Final_rows,
        {query_metadata,
            case {erlang:element(2, erlang:element(3, Probe_res)),
                erlang:element(2, erlang:element(3, Build_res))} of
                {{some, A}, {some, B}} ->
                    {some, gleam@int:max(A, B)};

                {{some, _}, none} ->
                    erlang:element(2, erlang:element(3, Probe_res));

                {none, {some, _}} ->
                    erlang:element(2, erlang:element(3, Build_res));

                {none, none} ->
                    none
            end,
            case {erlang:element(3, erlang:element(3, Probe_res)),
                erlang:element(3, erlang:element(3, Build_res))} of
                {{some, A@1}, {some, B@1}} ->
                    {some, gleam@int:max(A@1, B@1)};

                {{some, _}, none} ->
                    erlang:element(3, erlang:element(3, Probe_res));

                {none, {some, _}} ->
                    erlang:element(3, erlang:element(3, Build_res));

                {none, none} ->
                    none
            end,
            erlang:element(4, erlang:element(3, Probe_res)) + erlang:element(
                4,
                erlang:element(3, Build_res)
            ),
            erlang:element(5, erlang:element(3, Probe_res)) + erlang:element(
                5,
                erlang:element(3, Build_res)
            ),
            erlang:element(6, erlang:element(3, Probe_res)),
            none,
            maps:merge(
                erlang:element(8, erlang:element(3, Probe_res)),
                erlang:element(8, erlang:element(3, Build_res))
            )},
        none}.

-file("src/aarondb/sharded.gleam", 471).
?DOC(
    " Perform a global vector similarity search across all shards.\n"
    " Phase 50: Distributed V-Link.\n"
).
-spec global_vector_search(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    list(float()),
    float(),
    integer()
) -> list(aarondb@vec_index:search_result()).
global_vector_search(Db, Query_vec, Threshold, K) ->
    Shard_list = maps:to_list(erlang:element(2, Db)),
    Self = gleam@erlang@process:new_subject(),
    gleam@list:each(
        Shard_list,
        fun(Pair) ->
            {_, Shard_db} = Pair,
            proc_lib:spawn_link(
                fun() ->
                    Db_state = aarondb:get_state(Shard_db),
                    Res = aarondb@vec_index:search(
                        erlang:element(15, Db_state),
                        Query_vec,
                        Threshold,
                        K
                    ),
                    gleam@erlang@process:send(Self, Res)
                end
            )
        end
    ),
    _pipe@1 = gleam@list:fold(
        lists:seq(1, erlang:length(Shard_list)),
        [],
        fun(Acc, _) ->
            Shard_results = begin
                _pipe = gleam@erlang@process:'receive'(Self, 5000),
                gleam@result:unwrap(_pipe, [])
            end,
            lists:append(Acc, Shard_results)
        end
    ),
    _pipe@2 = gleam@list:sort(
        _pipe@1,
        fun(A, B) ->
            gleam@float:compare(erlang:element(3, B), erlang:element(3, A))
        end
    ),
    gleam@list:take(_pipe@2, K).

-file("src/aarondb/sharded.gleam", 501).
?DOC(" Stop the sharded database.\n").
-spec stop(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))
) -> nil.
stop(Db) ->
    Shard_list = maps:to_list(erlang:element(2, Db)),
    gleam@list:each(
        Shard_list,
        fun(Pair) ->
            {_, Shard_db} = Pair,
            Pid@1 = case gleam@erlang@process:subject_owner(Shard_db) of
                {ok, Pid} -> Pid;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"aarondb/sharded"/utf8>>,
                                function => <<"stop"/utf8>>,
                                line => 505,
                                value => _assert_fail,
                                start => 15183,
                                'end' => 15235,
                                pattern_start => 15194,
                                pattern_end => 15201})
            end,
            gleam@erlang@process:unlink(Pid@1),
            gleam@erlang@process:kill(Pid@1)
        end
    ).

-file("src/aarondb/sharded.gleam", 606).
-spec get_shard_id_from_map(
    aarondb@fact:eid(),
    aarondb@shared@query_types:shard_map()
) -> integer().
get_shard_id_from_map(Eid, Shard_map) ->
    Hash = case Eid of
        {uid, {entity_id, Id}} ->
            erlang:phash2({int, Id});

        {lookup, {_, Val}} ->
            erlang:phash2(Val)
    end,
    Target = begin
        _pipe = gleam@list:find(
            erlang:element(4, Shard_map),
            fun(H) -> H >= Hash end
        ),
        gleam@result:lazy_unwrap(
            _pipe,
            fun() -> _pipe@1 = gleam@list:first(erlang:element(4, Shard_map)),
                gleam@result:unwrap(_pipe@1, 0) end
        )
    end,
    _pipe@2 = gleam_stdlib:map_get(erlang:element(3, Shard_map), Target),
    gleam@result:unwrap(_pipe@2, 0).

-file("src/aarondb/sharded.gleam", 519).
?DOC(
    " Calculate which facts need to move based on the current distribution.\n"
    " Pure function: f(ClusterState) -> MigrationPlan\n"
).
-spec calculate_migration_plan(
    list({integer(), list(gleam@dict:dict(binary(), aarondb@fact:value()))}),
    aarondb@shared@query_types:shard_map()
) -> migration_plan().
calculate_migration_plan(Shards, Shard_map) ->
    Moves = gleam@list:map(
        Shards,
        fun(Pair) ->
            {Shard_id, Rows} = Pair,
            Facts_to_migrate = gleam@list:fold(
                Rows,
                [],
                fun(Acc, Row) ->
                    E = begin
                        _pipe = gleam_stdlib:map_get(Row, <<"e"/utf8>>),
                        gleam@result:unwrap(_pipe, {int, 0})
                    end,
                    A = <<"a"/utf8>>,
                    V = begin
                        _pipe@1 = gleam_stdlib:map_get(Row, <<"v"/utf8>>),
                        gleam@result:unwrap(_pipe@1, {int, 0})
                    end,
                    Eid = case E of
                        {int, Id} ->
                            {uid, {entity_id, Id}};

                        _ ->
                            {uid, {entity_id, 0}}
                    end,
                    New_shard_id = get_shard_id_from_map(Eid, Shard_map),
                    case New_shard_id /= Shard_id of
                        true ->
                            [{Eid, A, V} | Acc];

                        false ->
                            Acc
                    end
                end
            ),
            {Shard_id, Facts_to_migrate}
        end
    ),
    {migration_plan, Moves}.

-file("src/aarondb/sharded.gleam", 556).
?DOC(
    " Manually migrate data from one shard to another.\n"
    "\n"
    " ⚠️ NOT YET IMPLEMENTED. A correct implementation must scan the source\n"
    " shard's facts, apply `filter`, transact the matches into the destination\n"
    " shard (and retract from the source) under transaction safety, then return\n"
    " the count moved. Returns an explicit error rather than a silent `Ok(0)`\n"
    " that would falsely claim success. No callers exist today.\n"
).
-spec migrate_shard_data(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    integer(),
    integer(),
    fun(({aarondb@fact:eid(), binary(), aarondb@fact:value()}) -> boolean())
) -> {ok, integer()} | {error, binary()}.
migrate_shard_data(_, _, _, _) ->
    {error, <<"migrate_shard_data is not implemented — see doc comment"/utf8>>}.

-file("src/aarondb/sharded.gleam", 570).
?DOC(
    " Rebalance is deliberately unsupported.\n"
    "\n"
    " A correct implementation needs an atomic or recoverable copy/verify/cut-over\n"
    " protocol. Returning an explicit error is safer than duplicating facts without\n"
    " retracting their source copies.\n"
).
-spec rebalance(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))
) -> {ok,
        aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))} |
    {error, binary()}.
rebalance(_) ->
    {error,
        <<"shard rebalancing is not supported — no atomic migration protocol"/utf8>>}.

-file("src/aarondb/sharded.gleam", 581).
?DOC(
    " Add a shard without attempting migration.\n"
    "\n"
    " Existing facts remain on their current shards. The returned cluster updates\n"
    " routing only for future writes. Rebalancing is deliberately unsupported\n"
    " until a copy/verify/cut-over/retract protocol can preserve data atomically.\n"
).
-spec add_shard(
    aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message())),
    gleam@option:option(aarondb@storage:storage_adapter())
) -> {ok,
        aarondb@shared@query_types:sharded_db(gleam@erlang@process:subject(aarondb@transactor:message()))} |
    {error, binary()}.
add_shard(Db, Adapter) ->
    New_shard_id = erlang:element(3, Db),
    Shard_cluster_id = <<<<(erlang:element(4, Db))/binary, "_s"/utf8>>/binary,
        (gleam@string:inspect(New_shard_id))/binary>>,
    case aarondb:start_distributed(Shard_cluster_id, Adapter) of
        {ok, Shard_db} ->
            New_shards = gleam@dict:insert(
                erlang:element(2, Db),
                New_shard_id,
                Shard_db
            ),
            New_shard_count = erlang:element(3, Db) + 1,
            New_shard_map = create_shard_map(New_shards),
            {ok,
                {sharded_db,
                    New_shards,
                    New_shard_count,
                    erlang:element(4, Db),
                    New_shard_map}};

        {error, E} ->
            {error,
                <<"Failed to add shard: "/utf8,
                    (string_inspect_actor_error(E))/binary>>}
    end.
