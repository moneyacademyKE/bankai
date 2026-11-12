-record(token, {
    id :: binary(),
    capabilities :: list(aarondb@auth:capability()),
    issuer :: binary()
}).
