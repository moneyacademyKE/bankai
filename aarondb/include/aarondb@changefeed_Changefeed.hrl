-record(changefeed, {
    source :: aarondb@durable_log:durable_log(),
    cursor :: integer(),
    available_credit :: integer()
}).
