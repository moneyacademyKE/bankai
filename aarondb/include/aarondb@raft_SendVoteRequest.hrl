-record(send_vote_request, {
    to :: gleam@erlang@process:pid_(),
    term :: integer(),
    candidate :: gleam@erlang@process:pid_()
}).
