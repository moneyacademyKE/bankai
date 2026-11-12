-record(keyring, {
    keys :: list(aarondb@envelope:key()),
    maximum_frame_bytes :: integer(),
    maximum_parents :: integer()
}).
