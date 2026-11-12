-record(tarjan_state, {
    index :: integer(),
    indices :: gleam@dict:dict(aarondb@fact:entity_id(), integer()),
    lowlinks :: gleam@dict:dict(aarondb@fact:entity_id(), integer()),
    on_stack :: gleam@set:set(aarondb@fact:entity_id()),
    stack :: list(aarondb@fact:entity_id()),
    components :: gleam@dict:dict(aarondb@fact:entity_id(), integer()),
    comp_id :: integer()
}).
