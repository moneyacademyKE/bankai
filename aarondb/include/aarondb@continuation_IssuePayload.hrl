-record(issue_payload, {
    plan_id :: binary(),
    task_id :: binary(),
    effect_key :: binary(),
    request_id :: binary(),
    first_failed_at_ms :: integer(),
    last_failed_at_ms :: integer(),
    failure_class :: aarondb@continuation:failure_class(),
    retry_count :: integer(),
    fallback_outcome :: aarondb@continuation:fallback_outcome(),
    message :: binary()
}).
