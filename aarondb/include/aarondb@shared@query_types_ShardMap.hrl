-record(shard_map, {
    nodes :: gleam@dict:dict(integer(), gleam@erlang@process:pid_()),
    vnodes :: gleam@dict:dict(integer(), integer()),
    sorted_hashes :: list(integer())
}).
