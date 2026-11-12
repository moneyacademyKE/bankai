-record(hard_state, {
    term :: integer(),
    voted_for :: gleam@option:option(binary()),
    commit_index :: integer()
}).
