-record(append_entries, {
    term :: integer(),
    leader :: binary(),
    prev_index :: integer(),
    prev_term :: integer(),
    entries :: list(aarondb@raft_runtime:log_entry()),
    leader_commit :: integer()
}).
