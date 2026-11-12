-record(notify, {
    changed_attributes :: list(binary()),
    current_state :: aarondb@shared@state:db_state()
}).
