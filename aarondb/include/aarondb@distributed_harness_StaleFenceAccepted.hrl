-record(stale_fence_accepted, {
    resource :: binary(),
    expected :: integer(),
    received :: integer()
}).
