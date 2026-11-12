-record(state, {
    consensus :: aarondb@consensus:state(),
    log :: aarondb@durable_log:durable_log(),
    projection :: aarondb@projection:projection(),
    index :: aarondb@projection_index:index(),
    recovery :: aarondb@identity:recovery_state()
}).
