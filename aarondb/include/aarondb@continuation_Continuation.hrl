-record(continuation, {
    work :: aarondb@continuation:work(),
    policy :: aarondb@continuation:retry_policy(),
    provider_index :: integer(),
    retry_count :: integer(),
    evidence :: gleam@option:option(aarondb@continuation:evidence()),
    completed_effect_keys :: list(binary()),
    status :: aarondb@continuation:status()
}).
