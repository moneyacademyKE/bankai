-record(index_adapter, {
    name :: binary(),
    create :: fun((binary()) -> gleam@dynamic:dynamic_()),
    update :: fun((gleam@dynamic:dynamic_(), list(aarondb@fact:datom())) -> gleam@dynamic:dynamic_()),
    search :: fun((gleam@dynamic:dynamic_(), aarondb@shared@state:index_query(), float()) -> list(aarondb@fact:entity_id()))
}).
