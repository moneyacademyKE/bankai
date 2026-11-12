-module(aarondb@index@bm25).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/index/bm25.gleam").
-export([empty/1, remove_entity/2, add/3, build/2, remove/3, score/5, search/5]).
-export_type([b_m25_index/0, search_result/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " A local, in-memory BM25 index for one string attribute.\n"
    "\n"
    " ## Contract\n"
    "\n"
    " Documents are keyed by entity. `add` replaces an existing entity document\n"
    " atomically within the immutable index; callers do not need to retract the\n"
    " prior text first. `remove` is idempotent and removes the indexed entity\n"
    " regardless of the supplied historical text, which prevents stale input from\n"
    " corrupting document-frequency statistics.\n"
    "\n"
    " Tokenisation lowercases ASCII letters and digits, splits every other\n"
    " grapheme as a boundary, and does not apply stemming or stop-word removal.\n"
    " Ranking uses BM25's standard `k1`/`b` formula. Search returns only positive\n"
    " scores, ordered by descending score and then ascending entity ID to make ties\n"
    " deterministic. This module is an index primitive: database transaction and\n"
    " query-engine integration are not claimed by this contract.\n"
).

-type b_m25_index() :: {b_m25_index,
        gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:entity_id(), integer())),
        gleam@dict:dict(binary(), integer()),
        gleam@dict:dict(aarondb@fact:entity_id(), integer()),
        float(),
        integer(),
        binary()}.

-type search_result() :: {search_result, aarondb@fact:entity_id(), float()}.

-file("src/aarondb/index/bm25.gleam", 49).
-spec empty(binary()) -> b_m25_index().
empty(Attribute) ->
    {b_m25_index, maps:new(), maps:new(), maps:new(), +0.0, 0, Attribute}.

-file("src/aarondb/index/bm25.gleam", 295).
-spec is_alphanumeric(binary()) -> boolean().
is_alphanumeric(Char) ->
    Code = case gleam@string:to_utf_codepoints(Char) of
        [Cp] ->
            gleam_stdlib:identity(Cp);

        _ ->
            0
    end,
    (((Code >= 48) andalso (Code =< 57)) orelse ((Code >= 65) andalso (Code =< 90)))
    orelse ((Code >= 97) andalso (Code =< 122)).

-file("src/aarondb/index/bm25.gleam", 280).
-spec tokenize(binary()) -> list(binary()).
tokenize(Text) ->
    _pipe = Text,
    _pipe@1 = string:lowercase(_pipe),
    _pipe@2 = gleam@string:to_graphemes(_pipe@1),
    _pipe@3 = gleam@list:map(_pipe@2, fun(Char) -> case is_alphanumeric(Char) of
                true ->
                    Char;

                false ->
                    <<" "/utf8>>
            end end),
    _pipe@4 = erlang:list_to_binary(_pipe@3),
    _pipe@5 = gleam@string:split(_pipe@4, <<" "/utf8>>),
    gleam@list:filter(_pipe@5, fun(S) -> string:length(S) > 0 end).

-file("src/aarondb/index/bm25.gleam", 134).
?DOC(" Removes an entity document using the index's own term and length state.\n").
-spec remove_entity(b_m25_index(), aarondb@fact:entity_id()) -> b_m25_index().
remove_entity(Index, Entity) ->
    Old_length = gleam_stdlib:map_get(erlang:element(4, Index), Entity),
    case Old_length of
        {error, _} ->
            Index;

        {ok, Doc_length} ->
            {New_tf, New_df} = gleam@dict:fold(
                erlang:element(2, Index),
                {maps:new(), maps:new()},
                fun(Acc, Term, Entries) ->
                    {Tf_acc, Df_acc} = Acc,
                    case gleam_stdlib:map_get(Entries, Entity) of
                        {error, _} ->
                            Df = begin
                                _pipe = gleam_stdlib:map_get(
                                    erlang:element(3, Index),
                                    Term
                                ),
                                gleam@result:unwrap(_pipe, 0)
                            end,
                            {gleam@dict:insert(Tf_acc, Term, Entries),
                                gleam@dict:insert(Df_acc, Term, Df)};

                        {ok, _} ->
                            Remaining = gleam@dict:delete(Entries, Entity),
                            Tf_next = case maps:size(Remaining) of
                                0 ->
                                    Tf_acc;

                                _ ->
                                    gleam@dict:insert(Tf_acc, Term, Remaining)
                            end,
                            Df@1 = begin
                                _pipe@1 = gleam_stdlib:map_get(
                                    erlang:element(3, Index),
                                    Term
                                ),
                                gleam@result:unwrap(_pipe@1, 0)
                            end,
                            Df_next = case Df@1 =< 1 of
                                true ->
                                    Df_acc;

                                false ->
                                    gleam@dict:insert(Df_acc, Term, Df@1 - 1)
                            end,
                            {Tf_next, Df_next}
                    end
                end
            ),
            New_count = gleam@int:max(0, erlang:element(6, Index) - 1),
            Old_total_len = erlang:element(5, Index) * erlang:float(
                erlang:element(6, Index)
            ),
            New_avg_len = case New_count of
                0 ->
                    +0.0;

                _ ->
                    case erlang:float(New_count) of
                        +0.0 -> +0.0;
                        -0.0 -> -0.0;
                        Gleam@denominator -> (Old_total_len - erlang:float(
                            Doc_length
                        ))
                        / Gleam@denominator
                    end
            end,
            {b_m25_index,
                New_tf,
                New_df,
                gleam@dict:delete(erlang:element(4, Index), Entity),
                New_avg_len,
                New_count,
                erlang:element(7, Index)}
    end.

-file("src/aarondb/index/bm25.gleam", 77).
?DOC(" Adds or replaces one entity document.\n").
-spec add(b_m25_index(), aarondb@fact:entity_id(), binary()) -> b_m25_index().
add(Index, Entity, Text) ->
    Base = remove_entity(Index, Entity),
    Terms = tokenize(Text),
    Doc_length = erlang:length(Terms),
    Term_counts = gleam@list:fold(
        Terms,
        maps:new(),
        fun(Acc, Term) -> case gleam_stdlib:map_get(Acc, Term) of
                {ok, Count} ->
                    gleam@dict:insert(Acc, Term, Count + 1);

                {error, _} ->
                    gleam@dict:insert(Acc, Term, 1)
            end end
    ),
    {New_tf, New_df} = gleam@dict:fold(
        Term_counts,
        {erlang:element(2, Base), erlang:element(3, Base)},
        fun(Acc@1, Term@1, Count@1) ->
            {Tf_acc, Df_acc} = Acc@1,
            Term_entry = case gleam_stdlib:map_get(Tf_acc, Term@1) of
                {ok, Entry} ->
                    gleam@dict:insert(Entry, Entity, Count@1);

                {error, _} ->
                    maps:from_list([{Entity, Count@1}])
            end,
            Df = begin
                _pipe = gleam_stdlib:map_get(Df_acc, Term@1),
                gleam@result:unwrap(_pipe, 0)
            end,
            {gleam@dict:insert(Tf_acc, Term@1, Term_entry),
                gleam@dict:insert(Df_acc, Term@1, Df + 1)}
        end
    ),
    Old_total_len = erlang:element(5, Base) * erlang:float(
        erlang:element(6, Base)
    ),
    New_count = erlang:element(6, Base) + 1,
    New_avg_len = case erlang:float(New_count) of
        +0.0 -> +0.0;
        -0.0 -> -0.0;
        Gleam@denominator -> (Old_total_len + erlang:float(Doc_length)) / Gleam@denominator
    end,
    {b_m25_index,
        New_tf,
        New_df,
        gleam@dict:insert(erlang:element(4, Base), Entity, Doc_length),
        New_avg_len,
        New_count,
        erlang:element(7, Base)}.

-file("src/aarondb/index/bm25.gleam", 65).
?DOC(
    " Builds an index from string datoms for `attribute`.\n"
    "\n"
    " If input contains multiple datoms for an entity, the last datom in input\n"
    " wins, matching `add` replacement semantics. Callers that retain historical\n"
    " datoms should filter to their desired active snapshot before building.\n"
).
-spec build(list(aarondb@fact:datom()), binary()) -> b_m25_index().
build(Datoms, Attribute) ->
    _pipe = Datoms,
    _pipe@1 = gleam@list:filter(
        _pipe,
        fun(D) -> erlang:element(3, D) =:= Attribute end
    ),
    gleam@list:fold(
        _pipe@1,
        empty(Attribute),
        fun(Idx, Datom) -> case erlang:element(4, Datom) of
                {str, Text} ->
                    add(Idx, erlang:element(2, Datom), Text);

                _ ->
                    Idx
            end end
    ).

-file("src/aarondb/index/bm25.gleam", 125).
?DOC(
    " Removes an entity document. The supplied text is intentionally ignored:\n"
    " indexed state is the source of truth, so removal is safe and idempotent.\n"
).
-spec remove(b_m25_index(), aarondb@fact:entity_id(), binary()) -> b_m25_index().
remove(Index, Entity, _) ->
    remove_entity(Index, Entity).

-file("src/aarondb/index/bm25.gleam", 316).
-spec get_doc_len(b_m25_index(), aarondb@fact:entity_id()) -> integer().
get_doc_len(Index, Entity) ->
    _pipe = gleam_stdlib:map_get(erlang:element(4, Index), Entity),
    gleam@result:unwrap(_pipe, 0).

-file("src/aarondb/index/bm25.gleam", 312).
-spec get_doc_freq(b_m25_index(), binary()) -> integer().
get_doc_freq(Index, Term) ->
    _pipe = gleam_stdlib:map_get(erlang:element(3, Index), Term),
    gleam@result:unwrap(_pipe, 0).

-file("src/aarondb/index/bm25.gleam", 305).
-spec get_term_freq(b_m25_index(), aarondb@fact:entity_id(), binary()) -> integer().
get_term_freq(Index, Entity, Term) ->
    case gleam_stdlib:map_get(erlang:element(2, Index), Term) of
        {ok, Entity_map} ->
            _pipe = gleam_stdlib:map_get(Entity_map, Entity),
            gleam@result:unwrap(_pipe, 0);

        {error, _} ->
            0
    end.

-file("src/aarondb/index/bm25.gleam", 243).
-spec score_valid(
    b_m25_index(),
    aarondb@fact:entity_id(),
    binary(),
    float(),
    float()
) -> float().
score_valid(Index, Entity, Query, K1, B) ->
    Terms = tokenize(Query),
    gleam@list:fold(
        Terms,
        +0.0,
        fun(Acc, Term) ->
            Tf = get_term_freq(Index, Entity, Term),
            Df = get_doc_freq(Index, Term),
            Doc_len = get_doc_len(Index, Entity),
            Idf_numerator = (erlang:float(erlang:element(6, Index)) - erlang:float(
                Df
            ))
            + 0.5,
            Idf_denominator = erlang:float(Df) + 0.5,
            Idf = begin
                _pipe = gleam@float:logarithm(1.0 + (case Idf_denominator of
                        +0.0 -> +0.0;
                        -0.0 -> -0.0;
                        Gleam@denominator -> Idf_numerator / Gleam@denominator
                    end)),
                gleam@result:unwrap(_pipe, +0.0)
            end,
            Safe_idf = gleam@float:max(+0.0, Idf),
            Tf_float = erlang:float(Tf),
            Numerator = Tf_float * (K1 + 1.0),
            Avg_dl_safe = case erlang:element(5, Index) of
                +0.0 ->
                    1.0;

                Val ->
                    Val
            end,
            Denominator = Tf_float + (K1 * ((1.0 - B) + (B * (case Avg_dl_safe of
                +0.0 -> +0.0;
                -0.0 -> -0.0;
                Gleam@denominator@1 -> erlang:float(Doc_len) / Gleam@denominator@1
            end)))),
            case Denominator of
                +0.0 ->
                    Acc;

                _ ->
                    Acc + (Safe_idf * (case Denominator of
                        +0.0 -> +0.0;
                        -0.0 -> -0.0;
                        Gleam@denominator@2 -> Numerator / Gleam@denominator@2
                    end))
            end
        end
    ).

-file("src/aarondb/index/bm25.gleam", 239).
-spec valid_parameters(float(), float()) -> boolean().
valid_parameters(K1, B) ->
    ((K1 >= +0.0) andalso (B >= +0.0)) andalso (B =< 1.0).

-file("src/aarondb/index/bm25.gleam", 196).
?DOC(
    " Scores an entity for a query using standard BM25 parameters.\n"
    "\n"
    " `k1` must be non-negative and `b` must be in `[0.0, 1.0]`; invalid\n"
    " parameters return `0.0` to preserve this total compatibility API.\n"
).
-spec score(b_m25_index(), aarondb@fact:entity_id(), binary(), float(), float()) -> float().
score(Index, Entity, Query, K1, B) ->
    case valid_parameters(K1, B) of
        false ->
            +0.0;

        true ->
            score_valid(Index, Entity, Query, K1, B)
    end.

-file("src/aarondb/index/bm25.gleam", 231).
-spec compare_results(search_result(), search_result()) -> gleam@order:order().
compare_results(A, B) ->
    case gleam@float:compare(erlang:element(3, B), erlang:element(3, A)) of
        eq ->
            gleam@int:compare(
                aarondb@fact:eid_to_integer(erlang:element(2, A)),
                aarondb@fact:eid_to_integer(erlang:element(2, B))
            );

        Other ->
            Other
    end.

-file("src/aarondb/index/bm25.gleam", 211).
?DOC(
    " Searches every indexed entity and returns deterministic positive-score hits.\n"
    " `limit` must be positive; invalid BM25 parameters or limit return `[]`.\n"
).
-spec search(b_m25_index(), binary(), float(), float(), integer()) -> list(search_result()).
search(Index, Query, K1, B, Limit) ->
    case valid_parameters(K1, B) andalso (Limit > 0) of
        false ->
            [];

        true ->
            _pipe = maps:keys(erlang:element(4, Index)),
            _pipe@1 = gleam@list:map(
                _pipe,
                fun(Entity) ->
                    {search_result,
                        Entity,
                        score_valid(Index, Entity, Query, K1, B)}
                end
            ),
            _pipe@2 = gleam@list:filter(
                _pipe@1,
                fun(Result) -> erlang:element(3, Result) > +0.0 end
            ),
            _pipe@3 = gleam@list:sort(_pipe@2, fun compare_results/2),
            gleam@list:take(_pipe@3, Limit)
    end.
