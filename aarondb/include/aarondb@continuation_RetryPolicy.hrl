-record(retry_policy, {
    max_retries_per_provider :: integer(),
    base_backoff_ms :: integer(),
    providers :: list(binary())
}).
