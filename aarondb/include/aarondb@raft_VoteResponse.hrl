-record(vote_response, {
    term :: integer(),
    granted :: boolean(),
    from :: gleam@erlang@process:pid_()
}).
