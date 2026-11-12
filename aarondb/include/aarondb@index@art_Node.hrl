-record(node, {
    prefix :: bitstring(),
    children :: gleam@dict:dict(integer(), aarondb@index@art:node_()),
    values :: list(aarondb@fact:entity_id())
}).
