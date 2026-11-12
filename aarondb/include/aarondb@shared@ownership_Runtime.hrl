-record(runtime, {
    adapter :: aarondb@storage:storage_adapter(),
    subscribers :: list(gleam@erlang@process:subject(list(aarondb@fact:datom()))),
    reactive_actor :: gleam@erlang@process:subject(aarondb@shared@state:reactive_message()),
    followers :: list(gleam@erlang@process:pid_()),
    is_distributed :: boolean(),
    ets_name :: gleam@option:option(binary())
}).
