-record(storage_adapter, {
    insert :: fun((list(aarondb@fact:datom())) -> {ok, nil} |
        {error, aarondb@storage:storage_error()}),
    append :: fun((list(aarondb@fact:datom())) -> {ok, nil} |
        {error, aarondb@storage:storage_error()}),
    read :: fun((binary()) -> {ok, list(aarondb@fact:datom())} |
        {error, aarondb@storage:storage_error()}),
    read_all :: fun(() -> {ok, list(aarondb@fact:datom())} |
        {error, aarondb@storage:storage_error()}),
    query_datoms :: fun(({aarondb@shared@ast:part(),
        binary(),
        aarondb@shared@ast:part()}) -> {ok, list(aarondb@fact:datom())} |
        {error, aarondb@storage:storage_error()})
}).
