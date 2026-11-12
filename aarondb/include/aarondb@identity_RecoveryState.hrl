-record(recovery_state, {
    alarms :: list(aarondb@identity:recovery_alarm()),
    force_recovery_used :: boolean()
}).
