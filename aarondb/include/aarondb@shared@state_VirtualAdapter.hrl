-record(virtual_adapter, {
    execute :: fun((list(aarondb@fact:value())) -> {ok,
            list(list(aarondb@fact:value()))} |
        {error, aarondb@shared@state:virtual_adapter_error()}),
    max_rows :: integer()
}).
