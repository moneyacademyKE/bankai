-record(command_request, {
    idempotency_key :: binary(),
    command :: aarondb@command:command()
}).
