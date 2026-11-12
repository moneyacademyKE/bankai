-module(aarondb@storage@mnesia).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/storage/mnesia.gleam").
-export([init_mnesia/0, persist_datom/1, persist_batch/1, recover_datoms/0, adapter/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # storage/mnesia — recovery-oriented Mnesia StorageAdapter\n"
    "\n"
    " Thin Gleam wrapper over the `aarondb_mnesia_ffi` Erlang FFI: creates a\n"
    " disc-copy `datoms` schema and persists/recovers datoms transactionally.\n"
    " Initialization never rewrites an existing incompatible schema: it reports a\n"
    " descriptive `Error` and leaves persisted data untouched. Back up and\n"
    " migrate explicitly—or intentionally reset the table—before retrying.\n"
    " STATUS: Supported for one local BEAM node's recovery path only. `init_mnesia`\n"
    " and reads/writes return explicit errors, including startup, schema-mismatch,\n"
    " and aborted-transaction failures; they never reset an incompatible table.\n"
    " Test isolation: run the suite with a disposable Mnesia directory, e.g.\n"
    " `ERL_FLAGS=\"-mnesia dir <temporary-directory>\" gleam test`. The adapter\n"
    " owns no schema migration or cleanup operation: existing data is never reset.\n"
    " Concurrent initialization re-checks the existing table schema. This adapter\n"
    " does not provide multi-node durability, HA, schema migration,\n"
    " concurrent-writer performance guarantee. See ADR 0002.\n"
).

-file("src/aarondb/storage/mnesia.gleam", 23).
-spec init_mnesia() -> {ok, nil} | {error, binary()}.
init_mnesia() ->
    aarondb_mnesia_ffi:init().

-file("src/aarondb/storage/mnesia.gleam", 26).
-spec persist_datom(aarondb@fact:datom()) -> {ok, nil} | {error, binary()}.
persist_datom(Datom) ->
    aarondb_mnesia_ffi:persist(Datom).

-file("src/aarondb/storage/mnesia.gleam", 29).
-spec persist_batch(list(aarondb@fact:datom())) -> {ok, nil} | {error, binary()}.
persist_batch(Datoms) ->
    aarondb_mnesia_ffi:persist_batch(Datoms).

-file("src/aarondb/storage/mnesia.gleam", 51).
-spec map_err({ok, list(aarondb@fact:datom())} | {error, binary()}) -> {ok,
        list(aarondb@fact:datom())} |
    {error, aarondb@storage:storage_error()}.
map_err(Res) ->
    case Res of
        {ok, Datoms} ->
            {ok, Datoms};

        {error, Error} ->
            {error, {transaction_error, Error}}
    end.

-file("src/aarondb/storage/mnesia.gleam", 61).
-spec recover_datoms() -> {ok, list(aarondb@fact:datom())} | {error, binary()}.
recover_datoms() ->
    aarondb_mnesia_ffi:recover().

-file("src/aarondb/storage/mnesia.gleam", 44).
-spec map_write_err({ok, nil} | {error, binary()}) -> {ok, nil} |
    {error, aarondb@storage:storage_error()}.
map_write_err(Res) ->
    case Res of
        {ok, nil} ->
            {ok, nil};

        {error, Error} ->
            {error, {transaction_error, Error}}
    end.

-file("src/aarondb/storage/mnesia.gleam", 31).
-spec adapter() -> aarondb@storage:storage_adapter().
adapter() ->
    {storage_adapter,
        fun(Datoms) -> _pipe = aarondb_mnesia_ffi:persist_batch(Datoms),
            map_write_err(_pipe) end,
        fun(Datoms@1) -> _pipe@1 = aarondb_mnesia_ffi:persist_batch(Datoms@1),
            map_write_err(_pipe@1) end,
        fun(_) -> _pipe@2 = aarondb_mnesia_ffi:recover(),
            map_err(_pipe@2) end,
        fun() -> _pipe@3 = aarondb_mnesia_ffi:recover(),
            map_err(_pipe@3) end,
        fun(Pattern) -> _pipe@4 = aarondb_mnesia_ffi:select(Pattern),
            map_err(_pipe@4) end}.
