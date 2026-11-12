-module(aarondb@transactor@schema).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/schema.gleam").
-export([validate_unique/2, validate_cardinality_one/2, validate_composite/2]).

-file("src/aarondb/transactor/schema.gleam", 9).
-spec validate_unique(aarondb@shared@state:db_state(), binary()) -> gleam@option:option(binary()).
validate_unique(State, Attr) ->
    Datoms = begin
        _pipe = aarondb@index:filter_by_attribute(
            erlang:element(4, State),
            Attr
        ),
        gleam@list:filter(_pipe, fun(D) -> erlang:element(8, D) =:= assert end)
    end,
    Val_map = gleam@list:fold(
        Datoms,
        maps:new(),
        fun(Acc, D@1) ->
            Existing = begin
                _pipe@1 = gleam_stdlib:map_get(Acc, erlang:element(4, D@1)),
                gleam@result:unwrap(_pipe@1, [])
            end,
            gleam@dict:insert(
                Acc,
                erlang:element(4, D@1),
                [erlang:element(2, D@1) | Existing]
            )
        end
    ),
    Has_dupes = gleam@dict:fold(
        Val_map,
        false,
        fun(Acc@1, _, Eids) ->
            Acc@1 orelse (erlang:length(gleam@list:unique(Eids)) > 1)
        end
    ),
    case Has_dupes of
        true ->
            {some,
                <<"Cannot make non-unique attribute unique: existing data has duplicates"/utf8>>};

        false ->
            none
    end.

-file("src/aarondb/transactor/schema.gleam", 31).
-spec validate_cardinality_one(aarondb@shared@state:db_state(), binary()) -> gleam@option:option(binary()).
validate_cardinality_one(State, Attr) ->
    Datoms = begin
        _pipe = aarondb@index:filter_by_attribute(
            erlang:element(4, State),
            Attr
        ),
        gleam@list:filter(_pipe, fun(D) -> erlang:element(8, D) =:= assert end)
    end,
    Ent_map = gleam@list:fold(
        Datoms,
        maps:new(),
        fun(Acc, D@1) ->
            Existing = begin
                _pipe@1 = gleam_stdlib:map_get(Acc, erlang:element(2, D@1)),
                gleam@result:unwrap(_pipe@1, [])
            end,
            gleam@dict:insert(
                Acc,
                erlang:element(2, D@1),
                [erlang:element(4, D@1) | Existing]
            )
        end
    ),
    Has_multi = gleam@dict:fold(
        Ent_map,
        false,
        fun(Acc@1, _, Vals) ->
            Acc@1 orelse (erlang:length(gleam@list:unique(Vals)) > 1)
        end
    ),
    case Has_multi of
        true ->
            {some,
                <<"Cannot set cardinality to ONE: existing entities have multiple values"/utf8>>};

        false ->
            none
    end.

-file("src/aarondb/transactor/schema.gleam", 56).
-spec validate_composite(aarondb@shared@state:db_state(), list(binary())) -> boolean().
validate_composite(State, Attrs) ->
    Entity_map = gleam@list:fold(
        Attrs,
        maps:new(),
        fun(Acc, Attr) ->
            Datoms = begin
                _pipe = aarondb@index:filter_by_attribute(
                    erlang:element(4, State),
                    Attr
                ),
                gleam@list:filter(
                    _pipe,
                    fun(D) -> erlang:element(8, D) =:= assert end
                )
            end,
            gleam@list:fold(
                Datoms,
                Acc,
                fun(Acc2, D@1) ->
                    Existing = begin
                        _pipe@1 = gleam_stdlib:map_get(
                            Acc2,
                            erlang:element(2, D@1)
                        ),
                        gleam@result:unwrap(_pipe@1, [])
                    end,
                    gleam@dict:insert(
                        Acc2,
                        erlang:element(2, D@1),
                        [{Attr, erlang:element(4, D@1)} | Existing]
                    )
                end
            )
        end
    ),
    Entity_pairs = begin
        _pipe@2 = maps:to_list(Entity_map),
        gleam@list:filter(
            _pipe@2,
            fun(Item) ->
                erlang:length(erlang:element(2, Item)) =:= erlang:length(Attrs)
            end
        )
    end,
    gleam@list:any(
        Entity_pairs,
        fun(P1) ->
            gleam@list:any(
                Entity_pairs,
                fun(P2) ->
                    (erlang:element(1, P1) /= erlang:element(1, P2)) andalso gleam@list:all(
                        Attrs,
                        fun(A) ->
                            V1 = gleam@list:key_find(erlang:element(2, P1), A),
                            V2 = gleam@list:key_find(erlang:element(2, P2), A),
                            V1 =:= V2
                        end
                    )
                end
            )
        end
    ).
