-module(aarondb@sharding@semantics).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/sharding/semantics.gleam").
-export([route/3, group_facts/3, reduce_query_replies/1, retry_decision/4]).
-export_type([query_reply/0, query_reduction/0, retry_decision/0]).

-type query_reply() :: {query_succeeded,
        integer(),
        aarondb@shared@query_types:query_result()} |
    {query_unavailable, integer()} |
    {query_timed_out, integer(), integer()}.

-type query_reduction() :: {complete, aarondb@shared@query_types:query_result()} |
    {partial,
        aarondb@shared@query_types:query_result(),
        list(integer()),
        list({integer(), integer()})}.

-type retry_decision() :: {retry_now, integer()} |
    {retry_exhausted, integer()} |
    {deadline_elapsed, integer()}.

-file("src/aarondb/sharding/semantics.gleam", 32).
-spec route(
    aarondb@fact:eid(),
    gleam@dict:dict(integer(), integer()),
    list(integer())
) -> gleam@option:option(integer()).
route(Eid, Vnodes, Sorted_hashes) ->
    Hash = case Eid of
        {uid, {entity_id, Id}} ->
            erlang:phash2({int, Id});

        {lookup, {_, Value}} ->
            erlang:phash2(Value)
    end,
    Target = begin
        _pipe = gleam@list:find(
            Sorted_hashes,
            fun(Vnode_hash) -> Vnode_hash >= Hash end
        ),
        gleam@result:lazy_unwrap(
            _pipe,
            fun() -> _pipe@1 = gleam@list:first(Sorted_hashes),
                gleam@result:unwrap(_pipe@1, 0) end
        )
    end,
    case gleam_stdlib:map_get(Vnodes, Target) of
        {ok, Shard_id} ->
            {some, Shard_id};

        {error, _} ->
            none
    end.

-file("src/aarondb/sharding/semantics.gleam", 50).
-spec group_facts(
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    gleam@dict:dict(integer(), integer()),
    list(integer())
) -> {ok,
        gleam@dict:dict(integer(), list({aarondb@fact:eid(),
            binary(),
            aarondb@fact:value()}))} |
    {error, binary()}.
group_facts(Facts, Vnodes, Sorted_hashes) ->
    gleam@list:fold(
        Facts,
        {ok, maps:new()},
        fun(Grouped, Item) ->
            gleam@result:'try'(
                Grouped,
                fun(Grouped@1) ->
                    case route(erlang:element(1, Item), Vnodes, Sorted_hashes) of
                        {some, Shard_id} ->
                            Assigned = begin
                                _pipe = gleam_stdlib:map_get(
                                    Grouped@1,
                                    Shard_id
                                ),
                                gleam@result:unwrap(_pipe, [])
                            end,
                            {ok,
                                gleam@dict:insert(
                                    Grouped@1,
                                    Shard_id,
                                    [Item | Assigned]
                                )};

                        none ->
                            {error,
                                <<"cannot route fact: shard map has no virtual nodes"/utf8>>}
                    end
                end
            )
        end
    ).

-file("src/aarondb/sharding/semantics.gleam", 145).
-spec maximum(gleam@option:option(integer()), gleam@option:option(integer())) -> gleam@option:option(integer()).
maximum(Left, Right) ->
    case {Left, Right} of
        {{some, A}, {some, B}} ->
            {some, gleam@int:max(A, B)};

        {{some, _}, none} ->
            Left;

        {none, {some, _}} ->
            Right;

        {none, none} ->
            none
    end.

-file("src/aarondb/sharding/semantics.gleam", 119).
-spec merge(
    aarondb@shared@query_types:query_result(),
    aarondb@shared@query_types:query_result()
) -> aarondb@shared@query_types:query_result().
merge(Left, Right) ->
    {query_result,
        lists:append(erlang:element(2, Left), erlang:element(2, Right)),
        {query_metadata,
            maximum(
                erlang:element(2, erlang:element(3, Left)),
                erlang:element(2, erlang:element(3, Right))
            ),
            maximum(
                erlang:element(3, erlang:element(3, Left)),
                erlang:element(3, erlang:element(3, Right))
            ),
            erlang:element(4, erlang:element(3, Left)) + erlang:element(
                4,
                erlang:element(3, Right)
            ),
            erlang:element(5, erlang:element(3, Left)) + erlang:element(
                5,
                erlang:element(3, Right)
            ),
            case erlang:element(6, erlang:element(3, Left)) of
                <<""/utf8>> ->
                    erlang:element(6, erlang:element(3, Right));

                Plan ->
                    Plan
            end,
            none,
            maps:merge(
                erlang:element(8, erlang:element(3, Left)),
                erlang:element(8, erlang:element(3, Right))
            )},
        none}.

-file("src/aarondb/sharding/semantics.gleam", 103).
-spec empty_result() -> aarondb@shared@query_types:query_result().
empty_result() ->
    {query_result,
        [],
        {query_metadata, none, none, 0, 0, <<""/utf8>>, none, maps:new()},
        none}.

-file("src/aarondb/sharding/semantics.gleam", 67).
-spec reduce_query_replies(list(query_reply())) -> query_reduction().
reduce_query_replies(Replies) ->
    Initial = empty_result(),
    {Result, Unavailable, Timed_out} = gleam@list:fold(
        Replies,
        {Initial, [], []},
        fun(Acc, Reply) ->
            {Current, Missing, Expired} = Acc,
            case Reply of
                {query_succeeded, _, Next} ->
                    {merge(Current, Next), Missing, Expired};

                {query_unavailable, Shard_id} ->
                    {Current, [Shard_id | Missing], Expired};

                {query_timed_out, Shard_id@1, Deadline_ms} ->
                    {Current, Missing, [{Shard_id@1, Deadline_ms} | Expired]}
            end
        end
    ),
    case {Unavailable, Timed_out} of
        {[], []} ->
            {complete, Result};

        {_, _} ->
            {partial,
                Result,
                lists:reverse(Unavailable),
                lists:reverse(Timed_out)}
    end.

-file("src/aarondb/sharding/semantics.gleam", 87).
-spec retry_decision(integer(), integer(), boolean(), integer()) -> retry_decision().
retry_decision(Attempt, Max_attempts, Deadline_elapsed, Deadline_ms) ->
    case Deadline_elapsed of
        true ->
            {deadline_elapsed, Deadline_ms};

        false ->
            case Attempt < Max_attempts of
                true ->
                    {retry_now, Attempt + 1};

                false ->
                    {retry_exhausted, Attempt}
            end
    end.
