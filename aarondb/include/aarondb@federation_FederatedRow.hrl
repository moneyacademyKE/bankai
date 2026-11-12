-record(federated_row, {
    source :: binary(),
    row :: gleam@dict:dict(binary(), aarondb@fact:value())
}).
