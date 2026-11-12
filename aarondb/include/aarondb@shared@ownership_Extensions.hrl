-record(extensions, {
    functions :: gleam@dict:dict(binary(), fun((aarondb@shared@state:db_state(), integer(), integer(), list(aarondb@fact:value())) -> list({aarondb@fact:eid(),
        binary(),
        aarondb@fact:value()}))),
    composites :: list(list(binary())),
    registry :: gleam@dict:dict(binary(), aarondb@shared@state:index_adapter()),
    extensions :: gleam@dict:dict(binary(), aarondb@shared@state:extension_instance()),
    predicates :: gleam@dict:dict(binary(), fun((aarondb@fact:value()) -> boolean())),
    stored_rules :: list(aarondb@shared@ast:rule()),
    virtual_predicates :: gleam@dict:dict(binary(), aarondb@shared@state:virtual_adapter())
}).
