-record(query_context, {
    attributes :: list(binary()),
    entities :: list(aarondb@fact:entity_id()),
    timestamp :: integer()
}).
