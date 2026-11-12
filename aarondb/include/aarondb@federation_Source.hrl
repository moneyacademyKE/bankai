-record(source, {
    name :: binary(),
    db :: gleam@erlang@process:subject(aarondb@transactor:message())
}).
