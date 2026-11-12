-record(hybrid_index, {
    hot :: gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    cold :: list(bitstring()),
    capacity :: integer()
}).
