-record(raft_state, {
    role :: aarondb@raft:raft_role(),
    current_term :: integer(),
    voted_for :: gleam@option:option(gleam@erlang@process:pid_()),
    peers :: list(gleam@erlang@process:pid_()),
    votes_received :: integer(),
    leader_pid :: gleam@option:option(gleam@erlang@process:pid_())
}).
