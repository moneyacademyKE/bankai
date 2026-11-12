-record(cas_applied, {
    key :: binary(),
    previous :: gleam@option:option(binary()),
    value :: binary()
}).
