-record(compare_and_set, {
    key :: binary(),
    expected :: gleam@option:option(binary()),
    replacement :: binary()
}).
