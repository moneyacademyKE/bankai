-record(vote_request, {
    term :: integer(),
    candidate :: gleam@erlang@process:pid_()
}).
