-module(aarondb@index@art).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/index/art.gleam").
-export([new/0, insert/3, lookup/2, bytes_to_value/1, delete/3, search_prefix_entries/2, search_prefix/2]).
-export_type([node_/0, art/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type node_() :: {node,
        bitstring(),
        gleam@dict:dict(integer(), node_()),
        list(aarondb@fact:entity_id())}.

-type art() :: {art, node_()}.

-file("src/aarondb/index/art.gleam", 19).
?DOC(" Create a new empty ART index.\n").
-spec new() -> art().
new() ->
    {art, {node, <<>>, maps:new(), []}}.

-file("src/aarondb/index/art.gleam", 124).
-spec do_split_prefix(bitstring(), bitstring(), bitstring()) -> {bitstring(),
    bitstring(),
    bitstring()}.
do_split_prefix(P1, P2, Acc) ->
    case {P1, P2} of
        {<<B1:8, T1/bitstring>>, <<B2:8, T2/bitstring>>} when B1 =:= B2 ->
            do_split_prefix(T1, T2, <<Acc/bitstring, B1:8>>);

        {_, _} ->
            {Acc, P1, P2}
    end.

-file("src/aarondb/index/art.gleam", 117).
-spec split_common_prefix(bitstring(), bitstring()) -> {bitstring(),
    bitstring(),
    bitstring()}.
split_common_prefix(P1, P2) ->
    do_split_prefix(P1, P2, <<>>).

-file("src/aarondb/index/art.gleam", 29).
-spec do_insert(node_(), bitstring(), aarondb@fact:entity_id()) -> node_().
do_insert(Node, Key, Entity) ->
    case Key of
        <<>> ->
            {node,
                erlang:element(2, Node),
                erlang:element(3, Node),
                [Entity | erlang:element(4, Node)]};

        _ ->
            {Common, Rest_node, Rest_key} = split_common_prefix(
                erlang:element(2, Node),
                Key
            ),
            case Rest_node of
                <<>> ->
                    case Rest_key of
                        <<First:8, Tail/bitstring>> ->
                            Child = case gleam_stdlib:map_get(
                                erlang:element(3, Node),
                                First
                            ) of
                                {ok, C} ->
                                    C;

                                {error, nil} ->
                                    {node, Tail, maps:new(), [Entity]}
                            end,
                            Updated_child = case gleam_stdlib:map_get(
                                erlang:element(3, Node),
                                First
                            ) of
                                {ok, _} ->
                                    do_insert(Child, Tail, Entity);

                                {error, nil} ->
                                    Child
                            end,
                            {node,
                                erlang:element(2, Node),
                                gleam@dict:insert(
                                    erlang:element(3, Node),
                                    First,
                                    Updated_child
                                ),
                                erlang:element(4, Node)};

                        _ ->
                            {node,
                                erlang:element(2, Node),
                                erlang:element(3, Node),
                                [Entity | erlang:element(4, Node)]}
                    end;

                _ ->
                    {First_node@1, Tail_node@1} = case Rest_node of
                        <<First_node:8, Tail_node/bitstring>> -> {
                        First_node,
                            Tail_node};
                        _assert_fail ->
                            erlang:error(#{gleam_error => let_assert,
                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                        file => <<?FILEPATH/utf8>>,
                                        module => <<"aarondb/index/art"/utf8>>,
                                        function => <<"do_insert"/utf8>>,
                                        line => 60,
                                        value => _assert_fail,
                                        start => 1896,
                                        'end' => 1951,
                                        pattern_start => 1907,
                                        pattern_end => 1939})
                    end,
                    Old_node = {node,
                        Tail_node@1,
                        erlang:element(3, Node),
                        erlang:element(4, Node)},
                    case Rest_key of
                        <<First_key:8, Tail_key/bitstring>> ->
                            New_leaf = {node, Tail_key, maps:new(), [Entity]},
                            {node,
                                Common,
                                maps:from_list(
                                    [{First_node@1, Old_node},
                                        {First_key, New_leaf}]
                                ),
                                []};

                        _ ->
                            {node,
                                Common,
                                maps:from_list([{First_node@1, Old_node}]),
                                [Entity]}
                    end
            end
    end.

-file("src/aarondb/index/art.gleam", 137).
-spec value_to_bytes(aarondb@fact:value()) -> bitstring().
value_to_bytes(V) ->
    case V of
        {int, I} ->
            <<0:8, I:64>>;

        {float, F} ->
            <<1:8, F:64/float>>;

        {str, S} ->
            <<2:8, S/binary>>;

        {ref, {entity_id, Id}} ->
            <<3:8, Id:64>>;

        {bool, true} ->
            <<4:8, 1:8>>;

        {bool, false} ->
            <<4:8, 0:8>>;

        {vec, L} ->
            Bytes = gleam@list:fold(
                L,
                <<>>,
                fun(Acc, F@1) -> <<Acc/bitstring, F@1:64/float>> end
            ),
            <<5:8, Bytes/bitstring>>;

        {list, L@1} ->
            Bytes@1 = gleam@list:fold(
                L@1,
                <<>>,
                fun(Acc@1, Val) ->
                    <<Acc@1/bitstring, ((value_to_bytes(Val)))/bitstring>>
                end
            ),
            <<6:8, Bytes@1/bitstring>>;

        {map, M} ->
            Bytes@2 = gleam@dict:fold(
                M,
                <<>>,
                fun(Acc@2, K, V@1) ->
                    K_bits = <<K/binary>>,
                    <<Acc@2/bitstring,
                        ((string:length(K))):32,
                        K_bits/bitstring,
                        ((value_to_bytes(V@1)))/bitstring>>
                end
            ),
            <<7:8, ((maps:size(M))):32, Bytes@2/bitstring>>;

        {blob, B} ->
            <<8:8, B/bitstring>>
    end.

-file("src/aarondb/index/art.gleam", 24).
?DOC(" Insert an entity ID into the tree for a given fact value.\n").
-spec insert(art(), aarondb@fact:value(), aarondb@fact:entity_id()) -> art().
insert(Tree, Key, Entity) ->
    Key_bytes = value_to_bytes(Key),
    {art, do_insert(erlang:element(2, Tree), Key_bytes, Entity)}.

-file("src/aarondb/index/art.gleam", 97).
-spec do_lookup(node_(), bitstring()) -> list(aarondb@fact:entity_id()).
do_lookup(Node, Key) ->
    {_, Rest_node, Rest_key} = split_common_prefix(erlang:element(2, Node), Key),
    case Rest_node of
        <<>> ->
            case Rest_key of
                <<First:8, Tail/bitstring>> ->
                    case gleam_stdlib:map_get(erlang:element(3, Node), First) of
                        {ok, Child} ->
                            do_lookup(Child, Tail);

                        {error, nil} ->
                            []
                    end;

                _ ->
                    erlang:element(4, Node)
            end;

        _ ->
            []
    end.

-file("src/aarondb/index/art.gleam", 92).
?DOC(" Lookup all entities associated with a value.\n").
-spec lookup(art(), aarondb@fact:value()) -> list(aarondb@fact:entity_id()).
lookup(Tree, Key) ->
    Key_bytes = value_to_bytes(Key),
    do_lookup(erlang:element(2, Tree), Key_bytes).

-file("src/aarondb/index/art.gleam", 173).
-spec bytes_to_value(bitstring()) -> gleam@option:option(aarondb@fact:value()).
bytes_to_value(B) ->
    case B of
        <<0:8, I:64>> ->
            {some, {int, I}};

        <<1:8, F:64/float>> ->
            {some, {float, F}};

        <<2:8, Rest/bitstring>> ->
            case gleam@bit_array:to_string(Rest) of
                {ok, S} ->
                    {some, {str, S}};

                {error, _} ->
                    none
            end;

        <<3:8, Id:64>> ->
            {some, {ref, {entity_id, Id}}};

        <<4:8, 1:8>> ->
            {some, {bool, true}};

        <<4:8, 0:8>> ->
            {some, {bool, false}};

        <<8:8, B@1/bitstring>> ->
            {some, {blob, B@1}};

        _ ->
            none
    end.

-file("src/aarondb/index/art.gleam", 198).
-spec do_delete(node_(), bitstring(), aarondb@fact:entity_id()) -> node_().
do_delete(Node, Key, Entity) ->
    case Key of
        <<>> ->
            {node,
                erlang:element(2, Node),
                erlang:element(3, Node),
                gleam@list:filter(
                    erlang:element(4, Node),
                    fun(E) -> E /= Entity end
                )};

        _ ->
            {_, Rest_node, Rest_key} = split_common_prefix(
                erlang:element(2, Node),
                Key
            ),
            case Rest_node of
                <<>> ->
                    case Rest_key of
                        <<First:8, Tail/bitstring>> ->
                            case gleam_stdlib:map_get(
                                erlang:element(3, Node),
                                First
                            ) of
                                {ok, Child} ->
                                    Updated_child = do_delete(
                                        Child,
                                        Tail,
                                        Entity
                                    ),
                                    {node,
                                        erlang:element(2, Node),
                                        gleam@dict:insert(
                                            erlang:element(3, Node),
                                            First,
                                            Updated_child
                                        ),
                                        erlang:element(4, Node)};

                                {error, nil} ->
                                    Node
                            end;

                        _ ->
                            {node,
                                erlang:element(2, Node),
                                erlang:element(3, Node),
                                gleam@list:filter(
                                    erlang:element(4, Node),
                                    fun(E@1) -> E@1 /= Entity end
                                )}
                    end;

                _ ->
                    Node
            end
    end.

-file("src/aarondb/index/art.gleam", 193).
?DOC(" Remove an entity ID from the tree for a given fact value.\n").
-spec delete(art(), aarondb@fact:value(), aarondb@fact:entity_id()) -> art().
delete(Tree, Key, Entity) ->
    Key_bytes = value_to_bytes(Key),
    {art, do_delete(erlang:element(2, Tree), Key_bytes, Entity)}.

-file("src/aarondb/index/art.gleam", 305).
-spec collect_all_entries(node_(), bitstring()) -> list({aarondb@fact:value(),
    aarondb@fact:entity_id()}).
collect_all_entries(Node, Path_acc) ->
    Current_key_bytes = <<Path_acc/bitstring,
        ((erlang:element(2, Node)))/bitstring>>,
    Current_entries = case bytes_to_value(Current_key_bytes) of
        {some, Val} ->
            gleam@list:map(erlang:element(4, Node), fun(Eid) -> {Val, Eid} end);

        none ->
            []
    end,
    Children_entries = begin
        _pipe = maps:to_list(erlang:element(3, Node)),
        gleam@list:flat_map(
            _pipe,
            fun(Pair) ->
                {Byte, Child} = Pair,
                collect_all_entries(
                    Child,
                    <<Current_key_bytes/bitstring, Byte:8>>
                )
            end
        )
    end,
    lists:append(Current_entries, Children_entries).

-file("src/aarondb/index/art.gleam", 247).
-spec do_search_prefix_entries(node_(), bitstring(), bitstring()) -> list({aarondb@fact:value(),
    aarondb@fact:entity_id()}).
do_search_prefix_entries(Node, Search_prefix, Path_acc) ->
    case Search_prefix of
        <<>> ->
            collect_all_entries(Node, Path_acc);

        _ ->
            {_, Rest_node, Rest_search} = split_common_prefix(
                erlang:element(2, Node),
                Search_prefix
            ),
            case Rest_node of
                <<>> ->
                    Current_path = <<Path_acc/bitstring,
                        ((erlang:element(2, Node)))/bitstring>>,
                    case Rest_search of
                        <<First:8, Tail/bitstring>> ->
                            case gleam_stdlib:map_get(
                                erlang:element(3, Node),
                                First
                            ) of
                                {ok, Child} ->
                                    do_search_prefix_entries(
                                        Child,
                                        Tail,
                                        <<Current_path/bitstring, First:8>>
                                    );

                                {error, nil} ->
                                    []
                            end;

                        <<>> ->
                            collect_all_entries(Node, Path_acc);

                        _ ->
                            []
                    end;

                _ ->
                    case Rest_search of
                        <<>> ->
                            collect_all_entries(Node, Path_acc);

                        _ ->
                            []
                    end
            end
    end.

-file("src/aarondb/index/art.gleam", 239).
?DOC(
    " Search for all entities where the indexed value starts with the given prefix.\n"
    " Returns the Value and EntityId.\n"
).
-spec search_prefix_entries(art(), binary()) -> list({aarondb@fact:value(),
    aarondb@fact:entity_id()}).
search_prefix_entries(Tree, Prefix) ->
    Prefix_bytes = <<2:8, Prefix/binary>>,
    do_search_prefix_entries(erlang:element(2, Tree), Prefix_bytes, <<>>).

-file("src/aarondb/index/art.gleam", 371).
-spec collect_all_values(node_()) -> list(aarondb@fact:entity_id()).
collect_all_values(Node) ->
    Child_values = begin
        _pipe = maps:values(erlang:element(3, Node)),
        gleam@list:flat_map(_pipe, fun collect_all_values/1)
    end,
    lists:append(erlang:element(4, Node), Child_values).

-file("src/aarondb/index/art.gleam", 334).
-spec do_search_prefix(node_(), bitstring()) -> list(aarondb@fact:entity_id()).
do_search_prefix(Node, Prefix) ->
    case Prefix of
        <<>> ->
            collect_all_values(Node);

        _ ->
            {_, Rest_node, Rest_prefix} = split_common_prefix(
                erlang:element(2, Node),
                Prefix
            ),
            case Rest_node of
                <<>> ->
                    case Rest_prefix of
                        <<First:8, Tail/bitstring>> ->
                            case gleam_stdlib:map_get(
                                erlang:element(3, Node),
                                First
                            ) of
                                {ok, Child} ->
                                    do_search_prefix(Child, Tail);

                                {error, nil} ->
                                    []
                            end;

                        <<>> ->
                            collect_all_values(Node);

                        _ ->
                            []
                    end;

                _ ->
                    case Rest_prefix of
                        <<>> ->
                            collect_all_values(Node);

                        _ ->
                            []
                    end
            end
    end.

-file("src/aarondb/index/art.gleam", 329).
-spec search_prefix(art(), binary()) -> list(aarondb@fact:entity_id()).
search_prefix(Tree, Prefix) ->
    Prefix_bytes = <<2:8, Prefix/binary>>,
    do_search_prefix(erlang:element(2, Tree), Prefix_bytes).
