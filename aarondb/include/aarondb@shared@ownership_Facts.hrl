-record(facts, {
    eavt :: gleam@dict:dict(aarondb@fact:entity_id(), list(aarondb@fact:datom())),
    aevt :: gleam@dict:dict(binary(), list(aarondb@fact:datom())),
    avet :: gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:value(), aarondb@fact:entity_id())),
    latest_tx :: integer(),
    schema :: gleam@dict:dict(binary(), aarondb@fact:attribute_config())
}).
