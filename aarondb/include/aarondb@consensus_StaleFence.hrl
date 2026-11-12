-record(stale_fence, {
    resource :: binary(),
    expected :: integer(),
    received :: integer()
}).
