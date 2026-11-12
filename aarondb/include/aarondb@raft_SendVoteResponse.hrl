-record(send_vote_response, {
    to :: gleam@erlang@process:pid_(),
    term :: integer(),
    granted :: boolean()
}).
