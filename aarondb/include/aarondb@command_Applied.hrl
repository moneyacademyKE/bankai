-record(applied, {
    idempotency_key :: binary(),
    fingerprint :: binary(),
    result :: aarondb@command:command_result()
}).
