-module(aarondb@raft_runtime).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/raft_runtime.gleam").
-export([new/2, recover/3, persist/1, quorum/1, last_index/1, last_term/1, start_election/1, win_election/2, commit_quorum/3, apply_committed/1, handle/2, bootstrap_leader/1, add_learner/2, promote_voter/2, compact/3]).
-export_type([role/0, member/0, log_entry/0, snapshot/0, hard_state/0, persisted/0, state/0, rpc/0, reply/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # raft_runtime — deterministic durable Raft protocol model\n"
    "\n"
    " A transport-free reference runtime. Adapters persist `HardState` and deliver\n"
    " authenticated RPCs; this module makes protocol decisions and never claims\n"
    " network durability on its own.\n"
).

-type role() :: follower | candidate | leader.

-type member() :: {voter, binary()} | {learner, binary()}.

-type log_entry() :: {log_entry, integer(), binary()}.

-type snapshot() :: {snapshot, integer(), integer(), binary()}.

-type hard_state() :: {hard_state,
        integer(),
        gleam@option:option(binary()),
        integer()}.

-type persisted() :: {persisted,
        hard_state(),
        list(log_entry()),
        gleam@option:option(snapshot()),
        integer()}.

-type state() :: {state,
        binary(),
        role(),
        hard_state(),
        list(member()),
        list(log_entry()),
        integer(),
        gleam@option:option(binary()),
        gleam@option:option(snapshot())}.

-type rpc() :: {request_vote, integer(), binary(), integer(), integer()} |
    {append_entries,
        integer(),
        binary(),
        integer(),
        integer(),
        list(log_entry()),
        integer()} |
    {install_snapshot, integer(), binary(), snapshot()} |
    {read_index, integer(), binary(), integer()}.

-type reply() :: {vote_granted, integer(), boolean()} |
    {append_accepted, integer(), integer()} |
    {append_rejected, integer(), integer()} |
    {snapshot_accepted, integer(), integer()} |
    {read_index_accepted, integer(), integer()} |
    {stale_term, integer()}.

-file("src/aarondb/raft_runtime.gleam", 91).
-spec new(binary(), list(member())) -> state().
new(Node, Members) ->
    {state,
        Node,
        follower,
        {hard_state, 0, none, -1},
        Members,
        [],
        -1,
        none,
        none}.

-file("src/aarondb/raft_runtime.gleam", 97).
?DOC(
    " Restores only durable state. Leadership never survives recovery; the node must\n"
    " establish a current-term quorum again.\n"
).
-spec recover(binary(), list(member()), persisted()) -> state().
recover(Node, Members, Saved) ->
    {state,
        Node,
        follower,
        erlang:element(2, Saved),
        Members,
        erlang:element(3, Saved),
        erlang:element(5, Saved),
        none,
        erlang:element(4, Saved)}.

-file("src/aarondb/raft_runtime.gleam", 110).
-spec persist(state()) -> persisted().
persist(State) ->
    {persisted,
        erlang:element(4, State),
        erlang:element(6, State),
        erlang:element(9, State),
        erlang:element(7, State)}.

-file("src/aarondb/raft_runtime.gleam", 436).
-spec voters(list(member())) -> list(member()).
voters(Members) ->
    gleam@list:filter(Members, fun(Member) -> case Member of
                {voter, _} ->
                    true;

                _ ->
                    false
            end end).

-file("src/aarondb/raft_runtime.gleam", 114).
-spec quorum(state()) -> integer().
quorum(State) ->
    (erlang:length(voters(erlang:element(5, State))) div 2) + 1.

-file("src/aarondb/raft_runtime.gleam", 374).
-spec snapshot_index(gleam@option:option(snapshot())) -> integer().
snapshot_index(Snapshot) ->
    case Snapshot of
        {some, {snapshot, Index, _, _}} ->
            Index;

        none ->
            -1
    end.

-file("src/aarondb/raft_runtime.gleam", 118).
-spec last_index(state()) -> integer().
last_index(State) ->
    snapshot_index(erlang:element(9, State)) + erlang:length(
        erlang:element(6, State)
    ).

-file("src/aarondb/raft_runtime.gleam", 381).
-spec snapshot_term(gleam@option:option(snapshot())) -> integer().
snapshot_term(Snapshot) ->
    case Snapshot of
        {some, {snapshot, _, Term, _}} ->
            Term;

        none ->
            0
    end.

-file("src/aarondb/raft_runtime.gleam", 122).
-spec last_term(state()) -> integer().
last_term(State) ->
    case lists:reverse(erlang:element(6, State)) of
        [{log_entry, Term, _} | _] ->
            Term;

        [] ->
            snapshot_term(erlang:element(9, State))
    end.

-file("src/aarondb/raft_runtime.gleam", 445).
-spec is_voter(list(member()), binary()) -> boolean().
is_voter(Members, Id) ->
    gleam@list:any(Members, fun(Member) -> case Member of
                {voter, Member_id} ->
                    Member_id =:= Id;

                _ ->
                    false
            end end).

-file("src/aarondb/raft_runtime.gleam", 131).
?DOC(
    " Begins an election only for voting members. Persist the returned hard state\n"
    " before dispatching vote RPCs.\n"
).
-spec start_election(state()) -> state().
start_election(State) ->
    case is_voter(erlang:element(5, State), erlang:element(2, State)) of
        false ->
            State;

        true ->
            {state,
                erlang:element(2, State),
                candidate,
                {hard_state,
                    erlang:element(2, erlang:element(4, State)) + 1,
                    {some, erlang:element(2, State)},
                    erlang:element(4, erlang:element(4, State))},
                erlang:element(5, State),
                erlang:element(6, State),
                erlang:element(7, State),
                none,
                erlang:element(9, State)}
    end.

-file("src/aarondb/raft_runtime.gleam", 149).
?DOC(" Turns a candidate into leader only from explicit, same-term quorum evidence.\n").
-spec win_election(state(), integer()) -> state().
win_election(State, Granted_votes) ->
    case (erlang:element(3, State) =:= candidate) andalso (Granted_votes >= quorum(
        State
    )) of
        true ->
            {state,
                erlang:element(2, State),
                leader,
                erlang:element(4, State),
                erlang:element(5, State),
                erlang:element(6, State),
                erlang:element(7, State),
                {some, erlang:element(2, State)},
                erlang:element(9, State)};

        false ->
            State
    end.

-file("src/aarondb/raft_runtime.gleam", 395).
-spec term_at_log(list(log_entry()), integer()) -> integer().
term_at_log(Log, Wanted) ->
    case Log of
        [] ->
            -1;

        [{log_entry, Term, _} | Rest] ->
            case Wanted =:= 0 of
                true ->
                    Term;

                false ->
                    term_at_log(Rest, Wanted - 1)
            end
    end.

-file("src/aarondb/raft_runtime.gleam", 388).
-spec term_at(state(), integer()) -> integer().
term_at(State, Index) ->
    case Index =:= snapshot_index(erlang:element(9, State)) of
        true ->
            snapshot_term(erlang:element(9, State));

        false ->
            term_at_log(
                erlang:element(6, State),
                (Index - snapshot_index(erlang:element(9, State))) - 1
            )
    end.

-file("src/aarondb/raft_runtime.gleam", 157).
?DOC(" A leader may commit an index only after caller evidence proves current-term quorum replication.\n").
-spec commit_quorum(state(), integer(), integer()) -> state().
commit_quorum(State, Index, Replicated) ->
    case (((erlang:element(3, State) =:= leader) andalso (Replicated >= quorum(
        State
    )))
    andalso (Index > erlang:element(4, erlang:element(4, State))))
    andalso (term_at(State, Index) =:= erlang:element(
        2,
        erlang:element(4, State)
    )) of
        true ->
            {state,
                erlang:element(2, State),
                erlang:element(3, State),
                {hard_state,
                    erlang:element(2, erlang:element(4, State)),
                    erlang:element(3, erlang:element(4, State)),
                    Index},
                erlang:element(5, State),
                erlang:element(6, State),
                erlang:element(7, State),
                erlang:element(8, State),
                erlang:element(9, State)};

        false ->
            State
    end.

-file("src/aarondb/raft_runtime.gleam", 173).
-spec apply_committed(state()) -> {ok, state()} | {error, binary()}.
apply_committed(State) ->
    case erlang:element(7, State) < erlang:element(4, erlang:element(4, State)) of
        true ->
            {ok,
                {state,
                    erlang:element(2, State),
                    erlang:element(3, State),
                    erlang:element(4, State),
                    erlang:element(5, State),
                    erlang:element(6, State),
                    erlang:element(4, erlang:element(4, State)),
                    erlang:element(8, State),
                    erlang:element(9, State)}};

        false ->
            {ok, State}
    end.

-file("src/aarondb/raft_runtime.gleam", 422).
-spec min(integer(), integer()) -> integer().
min(Left, Right) ->
    case Left < Right of
        true ->
            Left;

        false ->
            Right
    end.

-file("src/aarondb/raft_runtime.gleam", 343).
-spec read_index(state(), integer(), binary(), integer()) -> {state(), reply()}.
read_index(State, Term, Leader, Committed) ->
    case (Term < erlang:element(2, erlang:element(4, State))) orelse (erlang:element(
        8,
        State
    )
    /= {some, Leader}) of
        true ->
            {State, {stale_term, erlang:element(2, erlang:element(4, State))}};

        false ->
            {State,
                {read_index_accepted,
                    Term,
                    min(Committed, erlang:element(4, erlang:element(4, State)))}}
    end.

-file("src/aarondb/raft_runtime.gleam", 358).
-spec step_down(state(), integer(), gleam@option:option(binary())) -> state().
step_down(State, Term, Leader) ->
    {state,
        erlang:element(2, State),
        follower,
        {hard_state, Term, none, erlang:element(4, erlang:element(4, State))},
        erlang:element(5, State),
        erlang:element(6, State),
        erlang:element(7, State),
        Leader,
        erlang:element(9, State)}.

-file("src/aarondb/raft_runtime.gleam", 321).
-spec install_snapshot(state(), integer(), binary(), snapshot()) -> {state(),
    reply()}.
install_snapshot(State, Term, Leader, Snapshot) ->
    case (Term < erlang:element(2, erlang:element(4, State))) orelse (erlang:element(
        2,
        Snapshot
    )
    < erlang:element(4, erlang:element(4, State))) of
        true ->
            {State, {stale_term, erlang:element(2, erlang:element(4, State))}};

        false ->
            Next = begin
                _record = step_down(State, Term, {some, Leader}),
                {state,
                    erlang:element(2, _record),
                    erlang:element(3, _record),
                    {hard_state, Term, none, erlang:element(2, Snapshot)},
                    erlang:element(5, _record),
                    [],
                    erlang:element(2, Snapshot),
                    erlang:element(8, _record),
                    {some, Snapshot}}
            end,
            {Next, {snapshot_accepted, Term, erlang:element(2, Snapshot)}}
    end.

-file("src/aarondb/raft_runtime.gleam", 429).
-spec max(integer(), integer()) -> integer().
max(Left, Right) ->
    case Left > Right of
        true ->
            Left;

        false ->
            Right
    end.

-file("src/aarondb/raft_runtime.gleam", 414).
-spec take(list(PMU), integer()) -> list(PMU).
take(Items, Count) ->
    case {Items, Count} of
        {_, 0} ->
            [];

        {[], _} ->
            [];

        {[Item | Rest], _} ->
            [Item | take(Rest, Count - 1)]
    end.

-file("src/aarondb/raft_runtime.gleam", 406).
-spec truncate_and_append(state(), integer(), list(log_entry())) -> list(log_entry()).
truncate_and_append(State, Prev, Entries) ->
    lists:append(
        take(
            erlang:element(6, State),
            Prev - snapshot_index(erlang:element(9, State))
        ),
        Entries
    ).

-file("src/aarondb/raft_runtime.gleam", 279).
-spec append(
    state(),
    integer(),
    binary(),
    integer(),
    integer(),
    list(log_entry()),
    integer()
) -> {state(), reply()}.
append(State, Term, Leader, Prev, Prev_term, Entries, Committed) ->
    case Term < erlang:element(2, erlang:element(4, State)) of
        true ->
            {State, {stale_term, erlang:element(2, erlang:element(4, State))}};

        false ->
            Follower = case Leader =:= erlang:element(2, State) of
                true ->
                    State;

                false ->
                    step_down(State, Term, {some, Leader})
            end,
            case term_at(Follower, Prev) =:= Prev_term of
                false ->
                    {Follower, {append_rejected, Term, last_index(Follower)}};

                true ->
                    Next_log = truncate_and_append(Follower, Prev, Entries),
                    Candidate_commit = min(
                        Committed,
                        snapshot_index(erlang:element(9, Follower)) + erlang:length(
                            Next_log
                        )
                    ),
                    Next = {state,
                        erlang:element(2, Follower),
                        erlang:element(3, Follower),
                        {hard_state,
                            Term,
                            erlang:element(3, erlang:element(4, Follower)),
                            max(
                                erlang:element(4, erlang:element(4, Follower)),
                                Candidate_commit
                            )},
                        erlang:element(5, Follower),
                        Next_log,
                        erlang:element(7, Follower),
                        erlang:element(8, Follower),
                        erlang:element(9, Follower)},
                    {Next, {append_accepted, Term, last_index(Next)}}
            end
    end.

-file("src/aarondb/raft_runtime.gleam", 367).
-spec log_up_to_date(state(), integer(), integer()) -> boolean().
log_up_to_date(State, Index, Term) ->
    case Term > last_term(State) of
        true ->
            true;

        false ->
            (Term =:= last_term(State)) andalso (Index >= last_index(State))
    end.

-file("src/aarondb/raft_runtime.gleam", 245).
-spec vote(state(), integer(), binary(), integer(), integer()) -> {state(),
    reply()}.
vote(State, Term, Candidate, Candidate_index, Candidate_term) ->
    case Term < erlang:element(2, erlang:element(4, State)) of
        true ->
            {State, {stale_term, erlang:element(2, erlang:element(4, State))}};

        false ->
            Stepped = step_down(State, Term, none),
            Vote_is_available = case erlang:element(
                3,
                erlang:element(4, Stepped)
            ) of
                none ->
                    true;

                {some, Voted} ->
                    Voted =:= Candidate
            end,
            Allowed = (is_voter(erlang:element(5, Stepped), Candidate) andalso log_up_to_date(
                Stepped,
                Candidate_index,
                Candidate_term
            ))
            andalso Vote_is_available,
            case Allowed of
                true ->
                    Next = {state,
                        erlang:element(2, Stepped),
                        erlang:element(3, Stepped),
                        {hard_state,
                            Term,
                            {some, Candidate},
                            erlang:element(4, erlang:element(4, Stepped))},
                        erlang:element(5, Stepped),
                        erlang:element(6, Stepped),
                        erlang:element(7, Stepped),
                        erlang:element(8, Stepped),
                        erlang:element(9, Stepped)},
                    {Next, {vote_granted, Term, true}};

                false ->
                    {Stepped, {vote_granted, Term, false}}
            end
    end.

-file("src/aarondb/raft_runtime.gleam", 180).
-spec handle(state(), rpc()) -> {state(), reply()}.
handle(State, Rpc) ->
    case Rpc of
        {request_vote, Term, Candidate, Index, Last} ->
            vote(State, Term, Candidate, Index, Last);

        {append_entries, Term@1, Leader, Prev_index, Prev_term, Entries, Commit} ->
            append(
                State,
                Term@1,
                Leader,
                Prev_index,
                Prev_term,
                Entries,
                Commit
            );

        {install_snapshot, Term@2, Leader@1, Snapshot} ->
            install_snapshot(State, Term@2, Leader@1, Snapshot);

        {read_index, Term@3, Leader@2, Committed} ->
            read_index(State, Term@3, Leader@2, Committed)
    end.

-file("src/aarondb/raft_runtime.gleam", 195).
?DOC(
    " The only automatic bootstrap: a one-voter cluster. Multi-node bootstrap\n"
    " needs externally authenticated member configuration.\n"
).
-spec bootstrap_leader(state()) -> state().
bootstrap_leader(State) ->
    case (erlang:length(voters(erlang:element(5, State))) =:= 1) andalso is_voter(
        erlang:element(5, State),
        erlang:element(2, State)
    ) of
        true ->
            {state,
                erlang:element(2, State),
                leader,
                erlang:element(4, State),
                erlang:element(5, State),
                erlang:element(6, State),
                erlang:element(7, State),
                {some, erlang:element(2, State)},
                erlang:element(9, State)};

        false ->
            State
    end.

-file("src/aarondb/raft_runtime.gleam", 454).
-spec is_member(list(member()), binary()) -> boolean().
is_member(Members, Id) ->
    gleam@list:any(Members, fun(Member) -> case Member of
                {voter, Member_id} ->
                    Member_id =:= Id;

                {learner, Member_id@1} ->
                    Member_id@1 =:= Id
            end end).

-file("src/aarondb/raft_runtime.gleam", 205).
-spec add_learner(state(), binary()) -> state().
add_learner(State, Id) ->
    case is_member(erlang:element(5, State), Id) of
        true ->
            State;

        false ->
            {state,
                erlang:element(2, State),
                erlang:element(3, State),
                erlang:element(4, State),
                lists:append(erlang:element(5, State), [{learner, Id}]),
                erlang:element(6, State),
                erlang:element(7, State),
                erlang:element(8, State),
                erlang:element(9, State)}
    end.

-file("src/aarondb/raft_runtime.gleam", 214).
?DOC(
    " Promotion is deliberately explicit so an adapter can make it a committed\n"
    " joint-consensus configuration entry rather than a local mutation.\n"
).
-spec promote_voter(state(), binary()) -> state().
promote_voter(State, Id) ->
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        gleam@list:map(erlang:element(5, State), fun(Member) -> case Member of
                    {learner, Member_id} when Member_id =:= Id ->
                        {voter, Id};

                    _ ->
                        Member
                end end),
        erlang:element(6, State),
        erlang:element(7, State),
        erlang:element(8, State),
        erlang:element(9, State)}.

-file("src/aarondb/raft_runtime.gleam", 226).
-spec compact(state(), integer(), binary()) -> {ok, state()} | {error, binary()}.
compact(State, Index, State_image) ->
    case (Index =< erlang:element(4, erlang:element(4, State))) andalso (Index
    >= snapshot_index(erlang:element(9, State))) of
        true ->
            {ok,
                {state,
                    erlang:element(2, State),
                    erlang:element(3, State),
                    erlang:element(4, State),
                    erlang:element(5, State),
                    erlang:element(6, State),
                    erlang:element(7, State),
                    erlang:element(8, State),
                    {some,
                        {snapshot, Index, term_at(State, Index), State_image}}}};

        false ->
            {error, <<"snapshot index must be committed and monotonic"/utf8>>}
    end.
