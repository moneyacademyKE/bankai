-module(aarondb@raft_durability).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/raft_durability.gleam").
-export([open/1, save/3, load/1, backup/2, remove_for_test/1, overwrite_for_test/2, interrupt_before_rename_for_test/2]).
-export_type([store/0, error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # raft_durability — filesystem-backed persistence boundary for cluster Raft\n"
    "\n"
    " The adapter commits a complete Raft recovery image through an Erlang-owned\n"
    " write/rename/fsync sequence. A recovery image is accepted only when its\n"
    " SHA-256 checksum and term encoding verify. Corruption is an alarm, never a\n"
    " repair path. The state image is opaque to this adapter so callers can keep\n"
    " command, membership, lease, idempotency, and projection-checkpoint state in\n"
    " one atomically recovered envelope.\n"
).

-type store() :: {store, binary()}.

-type error() :: {io, binary()} | {corrupt, binary()}.

-file("src/aarondb/raft_durability.gleam", 21).
-spec open(binary()) -> store().
open(Path) ->
    {store, Path}.

-file("src/aarondb/raft_durability.gleam", 34).
?DOC(
    " Atomically writes `hard state + log + snapshot + state image` and fsyncs both\n"
    " the file and directory before acknowledging success.\n"
).
-spec save(store(), aarondb@raft_runtime:persisted(), binary()) -> {ok, nil} |
    {error, error()}.
save(Store, Persisted, State_image) ->
    {store, Path} = Store,
    case aarondb_raft_durability_ffi:save(Path, Persisted, State_image) of
        {ok, nil} ->
            {ok, nil};

        {error, Reason} ->
            {error, {io, Reason}}
    end.

-file("src/aarondb/raft_durability.gleam", 51).
?DOC(
    " Reads exactly one verified image. Missing storage is a normal empty-node\n"
    " bootstrap condition; malformed/torn/corrupt storage is a terminal alarm.\n"
).
-spec load(store()) -> {ok, {aarondb@raft_runtime:persisted(), binary()}} |
    {error, error()}.
load(Store) ->
    {store, Path} = Store,
    case aarondb_raft_durability_ffi:load(Path) of
        {ok, Image} ->
            {ok, Image};

        {error, {<<"corrupt"/utf8>>, Reason}} ->
            {error, {corrupt, Reason}};

        {error, {_, Reason@1}} ->
            {error, {io, Reason@1}}
    end.

-file("src/aarondb/raft_durability.gleam", 65).
?DOC(
    " Exports the already verified durable image. It never serializes a partial\n"
    " in-memory state or overwrites the source store.\n"
).
-spec backup(store(), binary()) -> {ok, nil} | {error, error()}.
backup(Store, Destination) ->
    {store, Path} = Store,
    case aarondb_raft_durability_ffi:backup(Path, Destination) of
        {ok, nil} ->
            {ok, nil};

        {error, Reason} ->
            {error, {io, Reason}}
    end.

-file("src/aarondb/raft_durability.gleam", 74).
-spec remove_for_test(binary()) -> {ok, nil} | {error, binary()}.
remove_for_test(Path) ->
    aarondb_raft_durability_ffi:remove(Path).

-file("src/aarondb/raft_durability.gleam", 77).
-spec overwrite_for_test(binary(), binary()) -> {ok, nil} | {error, binary()}.
overwrite_for_test(Path, Bytes) ->
    aarondb_raft_durability_ffi:overwrite_for_test(Path, Bytes).

-file("src/aarondb/raft_durability.gleam", 83).
?DOC(
    " Test-only fault injection: writes and syncs a partial sibling image then\n"
    " aborts before rename. The previously acknowledged recovery image must remain\n"
    " the only readable state.\n"
).
-spec interrupt_before_rename_for_test(binary(), binary()) -> {ok, nil} |
    {error, binary()}.
interrupt_before_rename_for_test(Path, Partial_bytes) ->
    aarondb_raft_durability_ffi:interrupt_before_rename_for_test(
        Path,
        Partial_bytes
    ).
