-record(send_heartbeat, {
    to :: gleam@erlang@process:pid_(),
    term :: integer(),
    leader :: gleam@erlang@process:pid_()
}).
