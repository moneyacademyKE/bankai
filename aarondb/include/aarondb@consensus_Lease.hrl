-record(lease, {
    resource :: binary(),
    holder :: binary(),
    fence :: integer(),
    expires_at :: integer()
}).
