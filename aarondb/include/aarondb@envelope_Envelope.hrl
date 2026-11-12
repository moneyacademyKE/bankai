-record(envelope, {
    version :: integer(),
    domain :: binary(),
    payload :: bitstring(),
    payload_hash :: bitstring(),
    author :: bitstring(),
    parents :: list(bitstring()),
    logical_clock :: integer(),
    key_epoch :: integer(),
    signature :: bitstring()
}).
