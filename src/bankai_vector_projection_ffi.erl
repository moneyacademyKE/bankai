-module(bankai_vector_projection_ffi).
-export([search/6, exact_search/6, status/1, reset_workspace/1, warm/3, warm_with_deadline/4]).

%% A daemon-local, non-authoritative HNSW projection. A cache row is backed by
%% AaronDB's projection_index lifecycle record: a replacement corpus first enters
%% rebuilding, is populated at every consecutive committed offset, then becomes
%% queryable only after it catches up to the source watermark.
-define(CACHE, bankai_vector_projection_cache_v1).

search(Workspace, Offset, Documents, Query, Threshold, Limit) ->
    query(Workspace, Offset, Documents, Query, Threshold, Limit,
          fun aarondb@vec_index:search/4).

exact_search(Workspace, Offset, Documents, Query, Threshold, Limit) ->
    query(Workspace, Offset, Documents, Query, Threshold, Limit,
          fun(Index, Vector, Cutoff, Count) ->
              case aarondb@vec_index:exact_search(Index, Vector, Cutoff, Count) of
                  {ok, Results} -> Results;
                  {error, nil} -> []
              end
          end).

status(Workspace) ->
    ensure_table(),
    case ets:lookup(?CACHE, Workspace) of
        [{Workspace, Offset, _Signature, _Index, _Meta, Count, Lifecycle}] ->
            {index, _Schema, Generation, Health, _Applied, _Values} = Lifecycle,
            {ok, {Offset, Count, health_name(Health), Generation,
                  bankai@embed:active_backend()}};
        [] -> {error, <<"vector projection has not been built">>}
    end.

reset_workspace(Workspace) ->
    ensure_table(),
    ets:delete(?CACHE, Workspace),
    {ok, nil}.

%% Build the managed projection at daemon boot so the cache table is owned by
%% the long-lived acceptor process. An ETS table dies with its owner; created
%% lazily inside a per-connection handler it is destroyed when the handler
%% exits, silently discarding the HNSW graph between requests.
%%
%% bk-86b0: the build runs in a separate worker under a hard deadline. With
%% the semantic backend the per-insert greedy_search cost is quadratic and
%% used to wedge boot before the socket was ever bound; now the acceptor
%% waits at most TimeoutMs, then kills the worker and returns {error, ...}
%% so serve can print the skip notice and LISTEN with text-search degraded.
warm(Workspace, Offset, Documents) ->
    warm_with_deadline(Workspace, Offset, Documents, warm_deadline_ms()).

warm_with_deadline(Workspace, Offset, Documents, TimeoutMs) ->
    %% Create the cache table in the ACCEPTOR, not the worker: an ETS table
    %% dies with its owner, and the worker always exits (normally or killed).
    ensure_table(),
    Parent = self(),
    Worker = erlang:spawn(fun() ->
        warm_worker(Parent, Workspace, Offset, Documents)
    end),
    receive
        {Worker, ok, Count} -> {ok, Count};
        {Worker, error, Message} -> {error, Message}
    after max(0, TimeoutMs) ->
        %% Untrappable kill — a wedged greedy_search cannot swallow it. The
        %% worker holds no locks and the cache row is only inserted at the
        %% end of a successful rebuild, so a kill mid-build leaves the
        %% previous projection intact and the table reusable.
        exit(Worker, kill),
        {error, iolist_to_binary(io_lib:format(
            "vector projection warm timed out after ~pms; continuing with text search",
            [TimeoutMs]))}
    end.

warm_worker(Parent, Workspace, Offset, Documents) ->
    try
        {_Index, _Meta} = ensure_projection(Workspace, Offset, Documents),
        Parent ! {self(), ok, length(Documents)}
    catch
        Class:Reason ->
            Parent ! {self(), error, iolist_to_binary(io_lib:format(
                "vector projection warm failure (~p): ~p", [Class, Reason]))}
    end.

%% Boot-warm deadline: BANKAI_VECTOR_WARM_TIMEOUT_MS, default 30s. Read at
%% call time (never cached) so tests and operators can retune a live node.
warm_deadline_ms() ->
    case os:getenv("BANKAI_VECTOR_WARM_TIMEOUT_MS") of
        false -> 30000;
        Raw ->
            case string:to_integer(Raw) of
                {Int, []} when Int >= 0 -> Int;
                _ -> 30000
            end
    end.

query(_Workspace, _Offset, _Documents, Query, _Threshold, Limit, _Search)
  when Limit =< 0 ->
    {ok, []};
query(_Workspace, _Offset, _Documents, <<>>, _Threshold, _Limit, _Search) ->
    {ok, []};
query(Workspace, Offset, Documents, Query, Threshold, Limit, Search) ->
    try
        {Index, Meta} = ensure_projection(Workspace, Offset, Documents),
        Results = Search(Index, bankai@embed:embed(Query), Threshold, Limit),
        {ok, lists:sort(fun compare_match/2,
                        [to_match(Result, Meta) || Result <- Results])}
    catch
        Class:Reason ->
            {error, iolist_to_binary(io_lib:format(
                "vector projection failure (~p): ~p", [Class, Reason]))}
    end.

ensure_table() ->
    case ets:info(?CACHE) of
        undefined ->
            try ets:new(?CACHE, [named_table, public, set,
                                 {read_concurrency, true},
                                 {write_concurrency, true}]) of
                _ -> ok
            catch error:badarg -> ok
            end;
        _ -> ok
    end.

ensure_projection(Workspace, Offset, Documents) ->
    ensure_table(),
    Signature = corpus_signature(Documents),
    case ets:lookup(?CACHE, Workspace) of
        [{Workspace, Offset, Signature, Index, Meta, _Count, Lifecycle}] ->
            case aarondb@projection_index:query(Lifecycle) of
                {ok, _} -> {Index, Meta};
                {error, _} -> rebuild(Workspace, Offset, Documents, Lifecycle, Signature)
            end;
        [{Workspace, _PriorOffset, _PriorSignature, _Index, _Meta, _Count, Lifecycle}] ->
            rebuild(Workspace, Offset, Documents, Lifecycle, Signature);
        [] ->
            {ok, Lifecycle} = aarondb@projection_index:new(1),
            rebuild(Workspace, Offset, Documents, Lifecycle, Signature)
    end.

rebuild(Workspace, Offset, Documents, Previous, Signature) ->
    {ok, Building} = aarondb@projection_index:begin_rebuild(Previous, 1),
    {Index, Meta} = build(Documents),
    Membership = membership_frame(Documents),
    Applied = apply_through(Building, Offset, Membership),
    {ok, Lifecycle} = aarondb@projection_index:swap(Building, Applied, Offset),
    true = ets:insert(?CACHE,
                      {Workspace, Offset, Signature, Index, Meta,
                       length(Documents), Lifecycle}),
    {Index, Meta}.

%% The HNSW corpus is rebuilt from an authoritative snapshot. Its lifecycle is
%% still driven through every committed source offset: a snapshot-membership frame
%% is attached at the watermark, while prior offsets are explicit no-op frames.
%% `swap` therefore refuses a generation that has not reached the exact cursor.
apply_through(Index, Offset, Membership) when Offset < 0 -> Index;
apply_through(Index, Offset, Membership) ->
    apply_offset(Index, 0, Offset, Membership).

apply_offset(Index, Offset, High, Membership) when Offset > High -> Index;
apply_offset(Index, Offset, High, Membership) ->
    Value = case Offset =:= High of
        true -> Membership;
        false -> <<"committed-change">>
    end,
    {ok, Applied} = aarondb@projection_index:apply(Index, Offset, Value),
    apply_offset(Applied, Offset + 1, High, Membership).

membership_frame(Documents) ->
    iolist_to_binary([
        [Kind, <<":">>, Id, <<"\n">>] || {Kind, Id, _Text} <- Documents
    ]).

%% Offset only tells us whether Mnesia changed. This deterministic corpus frame
%% also catches memory-document changes, which live outside task change events.
corpus_signature(Documents) ->
    Entries = [[Kind, <<":">>, Id, <<":">>, Text, <<"\n">>]
               || {Kind, Id, Text} <- Documents],
    iolist_to_binary([bankai@embed:active_backend(), <<"\n">>, Entries]).

build(Documents) ->
    Config = aarondb@vec_index:deterministic_config(
               lists:duplicate(length(Documents), 0)),
    lists:foldl(fun insert_document/2,
                {aarondb@vec_index:new_with_config(Config), #{}}, Documents).

insert_document({Kind, Id, Text}, {Index, Meta}) ->
    {uid, Entity} = aarondb@fact:deterministic_uid(<<Kind/binary, ":", Id/binary>>),
    Next = aarondb@vec_index:insert(Index, Entity, bankai@embed:embed(Text)),
    {Next, maps:put(Entity, {Kind, Id}, Meta)}.

to_match({search_result, Entity, Score}, Meta) ->
    {Kind, Id} = maps:get(Entity, Meta),
    {Kind, Id, Score}.

compare_match({KindA, IdA, ScoreA}, {KindB, IdB, ScoreB}) ->
    case ScoreA =:= ScoreB of
        false -> ScoreA > ScoreB;
        true -> case KindA =:= KindB of
            false -> KindA =< KindB;
            true -> IdA =< IdB
        end
    end.

health_name(building) -> <<"building">>;
health_name(rebuilding) -> <<"rebuilding">>;
health_name(queryable) -> <<"queryable">>;
health_name({degraded, _}) -> <<"degraded">>;
health_name({failed, _}) -> <<"failed">>.
