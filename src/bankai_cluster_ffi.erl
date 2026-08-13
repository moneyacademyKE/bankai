-module(bankai_cluster_ffi).
-export([claim/8, transition/8, validate_fence/3, status/3, reset_for_test/1,
         force_no_quorum_for_test/1]).

%% AaronDB command/consensus admission only. Task heads remain Bankai Mnesia.
-define(TABLE, bankai_cluster_command_state_v2).
-define(TTL_NS, 300000000000).

claim(Workspace, _Cluster, Node, Task, Holder, Expected, Replacement, Now) ->
    ensure_table(),
    CommandId = command_id(<<"claim">>, Task, Expected, Replacement, Holder),
    {State, Admissions} = entry_for(Workspace, Node),
    case maps:find(CommandId, Admissions) of
        {ok, {KnownFence, KnownIndex}} ->
            {ok, {KnownFence, KnownIndex, true, CommandId}};
        error ->
            case current_lease(State, Task, Now) of
                {held, _OtherHolder, _Fence} ->
                    {error, <<"clustered claim already held">>};
                available ->
                    {Prepared, Index} = append_command(State, Node, <<"claim">>),
                    case aarondb@consensus:lease(
                           Prepared, Index, replication_count(Prepared), Now,
                           {acquire, Task, Holder, ?TTL_NS}) of
                        {ok, {Committed, {some, {lease, _, _, NewFence, _}}}} ->
                            save(Workspace, Node, Committed,
                                 maps:put(CommandId, {NewFence, Index}, Admissions)),
                            {ok, {NewFence, Index, false, CommandId}};
                        {error, Reason} -> {error, admission_error(Reason)}
                    end
            end
    end.

transition(Workspace, _Cluster, Node, Task, Expected, Replacement, Fence, _Now) ->
    ensure_table(),
    CommandId = command_id(<<"transition">>, Task, Expected, Replacement,
                           integer_to_binary(Fence)),
    {State, Admissions} = entry_for(Workspace, Node),
    case maps:find(CommandId, Admissions) of
        {ok, {SavedFence, Index}} -> {ok, {SavedFence, Index, true, CommandId}};
        error ->
            case aarondb@consensus:validate_fence(State, Task, Fence) of
                {error, Reason} -> {error, admission_error(Reason)};
                {ok, nil} ->
                    {Prepared, Index} = append_command(State, Node, <<"transition">>),
                    Request = {command_request, CommandId,
                               {put, <<"task:", Task/binary>>, Replacement}},
                    case aarondb@consensus:submit(
                           Prepared, Index, replication_count(Prepared), Request) of
                        {ok, {Committed, _}} ->
                            save(Workspace, Node, Committed,
                                 maps:put(CommandId, {Fence, Index}, Admissions)),
                            {ok, {Fence, Index, false, CommandId}};
                        {error, Reason} -> {error, admission_error(Reason)}
                    end
            end
    end.

validate_fence(Workspace, Task, Fence) ->
    ensure_table(),
    case ets:lookup(?TABLE, Workspace) of
        [{Workspace, _Node, State, _Admissions}] ->
            case aarondb@consensus:validate_fence(State, Task, Fence) of
                {ok, nil} -> {ok, nil};
                {error, Reason} -> {error, admission_error(Reason)}
            end;
        [] -> {error, <<"clustered command state is not initialized">>}
    end.

status(Workspace, _Cluster, Node) ->
    ensure_table(),
    {State, _Admissions} = entry_for(Workspace, Node),
    {state, Raft, _Commands, Leases, _LastNow} = State,
    {state, _NodeId, Role, {hard_state, Term, _Vote, Commit}, _Members,
     _Log, _Applied, Leader, _Snapshot} = Raft,
    LeaderText = case Leader of none -> <<>>; {some, Value} -> Value end,
    case aarondb@consensus:linearizable_read(
           State, Commit, Role =:= leader, <<"bankai-read-index">>) of
        {ok, _} ->
            {ok, {LeaderText, Commit, Commit, quorum_text(Role), length(Leases)}};
        {error, Reason} -> {error, admission_error({read_index, Term, Reason})}
    end.

reset_for_test(Workspace) ->
    ensure_table(),
    ets:delete(?TABLE, Workspace),
    {ok, nil}.

force_no_quorum_for_test(Workspace) ->
    ensure_table(),
    case ets:lookup(?TABLE, Workspace) of
        [{Workspace, Node, {state, Raft, Commands, Leases, LastNow}, Admissions}] ->
            {state, NodeId, _Role, Hard, Members, Log, Applied, _Leader, Snapshot} = Raft,
            Follower = {state, NodeId, follower, Hard, Members, Log, Applied, none, Snapshot},
            true = ets:insert(?TABLE, {Workspace, Node,
                                       {state, Follower, Commands, Leases, LastNow}, Admissions}),
            {ok, nil};
        [] -> {error, <<"clustered command state is not initialized">>}
    end.

entry_for(Workspace, Node) ->
    case ets:lookup(?TABLE, Workspace) of
        [{Workspace, _SavedNode, State, Admissions}] -> {State, Admissions};
        [] -> {initial(Node), #{}}
    end.

initial(Node) ->
    Raft0 = aarondb@raft_runtime:new(Node, [{voter, Node}]),
    Raft1 = aarondb@raft_runtime:start_election(Raft0),
    Raft2 = aarondb@raft_runtime:win_election(Raft1, 1),
    aarondb@consensus:new(Raft2).

append_command({state, Raft, Commands, Leases, LastNow}, Node, Command) ->
    Index = aarondb@raft_runtime:last_index(Raft) + 1,
    {state, _Id, _Role, {hard_state, Term, _Vote, Commit}, _Members,
     _Log, _Applied, _Leader, _Snapshot} = Raft,
    Rpc = {append_entries, Term, Node, Index - 1,
           aarondb@raft_runtime:last_term(Raft), [{log_entry, Term, Command}], Commit},
    {AdvancedRaft, _Reply} = aarondb@raft_runtime:handle(Raft, Rpc),
    {{state, AdvancedRaft, Commands, Leases, LastNow}, Index}.

current_lease({state, _Raft, _Commands, Leases, _LastNow}, Task, Now) ->
    case lists:keyfind(Task, 2, Leases) of
        false -> available;
        {lease, _Resource, _Holder, _Fence, Expiry} when Expiry =< Now -> available;
        {lease, _Resource, Holder, Fence, _Expiry} -> {held, Holder, Fence}
    end.

replication_count({state, Raft, _Commands, _Leases, _LastNow}) ->
    aarondb@raft_runtime:quorum(Raft).

save(Workspace, Node, State, Admissions) ->
    true = ets:insert(?TABLE, {Workspace, Node, State, Admissions}).

command_id(Kind, Task, Expected, Replacement, Holder) ->
    <<"bankai-command-v1|", Kind/binary, "|", Task/binary, "|",
      Expected/binary, "|", Replacement/binary, "|", Holder/binary>>.

quorum_text(leader) -> <<"healthy">>;
quorum_text(_) -> <<"unavailable">>.

admission_error({redirect, {some, Leader}}) ->
    <<"cluster leader redirect: ", Leader/binary>>;
admission_error(quorum_unavailable) -> <<"cluster quorum unavailable">>;
admission_error(Reason) ->
    iolist_to_binary(io_lib:format("cluster command rejected: ~p", [Reason])).

ensure_table() ->
    case ets:info(?TABLE) of
        undefined ->
            try ets:new(?TABLE, [named_table, public, set,
                                 {read_concurrency, true}, {write_concurrency, true}]) of
                _ -> ok
            catch error:badarg -> ok
            end;
        _ -> ok
    end.
