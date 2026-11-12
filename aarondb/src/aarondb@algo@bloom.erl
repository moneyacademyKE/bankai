-module(aarondb@algo@bloom).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/algo/bloom.gleam").
-export([new/2, insert/2, might_contain/2]).
-export_type([bloom_filter/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type bloom_filter() :: {bloom_filter, bitstring(), integer(), integer()}.

-file("src/aarondb/algo/bloom.gleam", 10).
?DOC(" Create a new Bloom Filter with specified size (in bits) and number of hash functions.\n").
-spec new(integer(), integer()) -> bloom_filter().
new(Size_bits, Hash_count) ->
    Byte_size = case Size_bits rem 8 of
        0 ->
            Size_bits div 8;

        _ ->
            (Size_bits div 8) + 1
    end,
    Bits = gleam@list:fold(
        gleam@list:repeat(0, Byte_size),
        <<>>,
        fun(Acc, Byte) -> <<Acc/bitstring, Byte:8>> end
    ),
    {bloom_filter, Bits, Byte_size * 8, Hash_count}.

-file("src/aarondb/algo/bloom.gleam", 47).
-spec set_bit(bitstring(), integer()) -> bitstring().
set_bit(Bits, Index) ->
    Byte_index = Index div 8,
    Bit_offset = Index rem 8,
    case erlang:byte_size(Bits) > Byte_index of
        true ->
            Prefix_bits = Byte_index * 8,
            {Prefix@1, Byte@1, Suffix@1} = case Bits of
                <<Prefix:Prefix_bits/bitstring, Byte:8, Suffix/bitstring>> -> {
                Prefix,
                    Byte,
                    Suffix};
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"aarondb/algo/bloom"/utf8>>,
                                function => <<"set_bit"/utf8>>,
                                line => 54,
                                value => _assert_fail,
                                start => 1512,
                                'end' => 1584,
                                pattern_start => 1523,
                                pattern_end => 1577})
            end,
            New_byte = erlang:'bor'(Byte@1, erlang:'bsl'(1, 7 - Bit_offset)),
            <<Prefix@1/bitstring, New_byte:8, Suffix@1/bitstring>>;

        false ->
            Bits
    end.

-file("src/aarondb/algo/bloom.gleam", 26).
?DOC(" Insert a key into the Bloom filter.\n").
-spec insert(bloom_filter(), binary()) -> bloom_filter().
insert(Filter, Key) ->
    gleam@int:range(
        1,
        erlang:element(4, Filter),
        Filter,
        fun(F, I) ->
            Index = erlang:phash2({Key, I}, erlang:element(3, F)),
            New_bits = set_bit(erlang:element(2, F), Index),
            {bloom_filter, New_bits, erlang:element(3, F), erlang:element(4, F)}
        end
    ).

-file("src/aarondb/algo/bloom.gleam", 63).
-spec get_bit(bitstring(), integer()) -> boolean().
get_bit(Bits, Index) ->
    Byte_index = Index div 8,
    Bit_offset = Index rem 8,
    case erlang:byte_size(Bits) > Byte_index of
        true ->
            Prefix_bits = Byte_index * 8,
            Byte@1 = case Bits of
                <<_:Prefix_bits/bitstring, Byte:8, _/bitstring>> -> Byte;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"aarondb/algo/bloom"/utf8>>,
                                function => <<"get_bit"/utf8>>,
                                line => 70,
                                value => _assert_fail,
                                start => 1971,
                                'end' => 2033,
                                pattern_start => 1982,
                                pattern_end => 2026})
            end,
            Mask = erlang:'bsl'(1, 7 - Bit_offset),
            erlang:'band'(Byte@1, Mask) /= 0;

        false ->
            false
    end.

-file("src/aarondb/algo/bloom.gleam", 35).
?DOC(" Check if a key might be in the set.\n").
-spec might_contain(bloom_filter(), binary()) -> boolean().
might_contain(Filter, Key) ->
    gleam@int:range(
        1,
        erlang:element(4, Filter),
        true,
        fun(Acc, I) -> case Acc of
                false ->
                    false;

                true ->
                    Index = erlang:phash2({Key, I}, erlang:element(3, Filter)),
                    get_bit(erlang:element(2, Filter), Index)
            end end
    ).
