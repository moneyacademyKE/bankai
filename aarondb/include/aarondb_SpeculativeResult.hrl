-record(speculative_result, {
    state :: aarondb@shared@state:db_state(),
    datoms :: list(aarondb@fact:datom())
}).
