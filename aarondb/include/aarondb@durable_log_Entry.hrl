-record(entry, {
    offset :: integer(),
    payload :: binary(),
    idempotency_key :: binary(),
    checksum :: binary()
}).
