-module(aarondb@index@ets).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/index/ets.gleam").
-export([init_tables/1, insert_datom/3, insert_avet/3, lookup_datoms/2, delete/2, get_av/3, prune_historical/3, serialize_term/1, deserialize_term/1, get_raw_binary/2, prune_historical_aevt/3]).
-export_type([table_type/0]).

-type table_type() :: set | ordered_set | bag | duplicate_bag.

-file("src/aarondb/index/ets.gleam", 9).
-spec init_tables(binary()) -> nil.
init_tables(Db_name) ->
    Eavt = <<Db_name/binary, "_eavt"/utf8>>,
    Aevt = <<Db_name/binary, "_aevt"/utf8>>,
    Avet = <<Db_name/binary, "_avet"/utf8>>,
    aarondb_ets_ffi:init_table(Eavt, duplicate_bag),
    aarondb_ets_ffi:init_table(Aevt, duplicate_bag),
    aarondb_ets_ffi:init_table(Avet, set),
    nil.

-file("src/aarondb/index/ets.gleam", 30).
-spec insert_datom(binary(), any(), aarondb@fact:datom()) -> nil.
insert_datom(Table, Key, Datom) ->
    aarondb_ets_ffi:insert(Table, {Key, Datom}).

-file("src/aarondb/index/ets.gleam", 34).
-spec insert_avet(
    binary(),
    {binary(), aarondb@fact:value()},
    aarondb@fact:entity_id()
) -> nil.
insert_avet(Table, Key, Eid) ->
    aarondb_ets_ffi:insert(Table, {Key, Eid}).

-file("src/aarondb/index/ets.gleam", 45).
-spec lookup_datoms(binary(), any()) -> list(aarondb@fact:datom()).
lookup_datoms(Table, Key) ->
    _pipe = aarondb_ets_ffi:lookup(Table, Key),
    gleam@list:map(
        _pipe,
        fun(Obj) ->
            {_, Val} = Obj,
            Val
        end
    ).

-file("src/aarondb/index/ets.gleam", 56).
-spec delete(binary(), any()) -> nil.
delete(Table, Key) ->
    aarondb_ets_ffi:delete(Table, Key).

-file("src/aarondb/index/ets.gleam", 63).
-spec get_av(binary(), binary(), aarondb@fact:value()) -> gleam@option:option(aarondb@fact:entity_id()).
get_av(Table, Attr, Val) ->
    case aarondb_ets_ffi:lookup(Table, {Attr, Val}) of
        [{_, Eid}] ->
            {some, Eid};

        _ ->
            none
    end.

-file("src/aarondb/index/ets.gleam", 73).
-spec prune_historical(binary(), aarondb@fact:entity_id(), binary()) -> nil.
prune_historical(Table, Eid, Attr) ->
    aarondb_ets_ffi:prune_eavt(Table, Eid, Attr).

-file("src/aarondb/index/ets.gleam", 77).
-spec serialize_term(any()) -> bitstring().
serialize_term(Term) ->
    erlang:term_to_binary(Term).

-file("src/aarondb/index/ets.gleam", 84).
-spec deserialize_term(bitstring()) -> {ok, gleam@dynamic:dynamic_()} |
    {error, nil}.
deserialize_term(B) ->
    aarondb_term_ffi:decode_term(B).

-file("src/aarondb/index/ets.gleam", 91).
-spec get_raw_binary(binary(), any()) -> {ok, bitstring()} | {error, nil}.
get_raw_binary(Table, Key) ->
    aarondb_ets_ffi:get_raw_binary(Table, Key).

-file("src/aarondb/index/ets.gleam", 98).
-spec prune_historical_aevt(binary(), binary(), aarondb@fact:entity_id()) -> nil.
prune_historical_aevt(Table, Attr, Eid) ->
    aarondb_ets_ffi:prune_aevt(Table, Attr, Eid).
