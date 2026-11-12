-record(bootstrap, {
    snapshot :: aarondb@durable_log:snapshot(),
    tail :: list(aarondb@durable_log:entry()),
    cursor :: integer()
}).
