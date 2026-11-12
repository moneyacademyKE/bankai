-record(evidence, {
    request_id :: binary(),
    failure_class :: aarondb@continuation:failure_class(),
    first_failed_at_ms :: integer(),
    last_failed_at_ms :: integer(),
    message :: binary()
}).
