-module(aarondb@rag).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/rag.gleam").
-export([build_query/1]).
-export_type([semantic_intent/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # rag — supported semantic-intent query macros\n"
    "\n"
    " This module is the authoritative semantic-intent convenience layer for the\n"
    " local MCP `recall` tool. It compiles a small closed set of `SemanticIntent`\n"
    " values into ordinary AaronDB query ASTs; it owns no storage, transport, or\n"
    " ranking engine. Execution remains in the normal Cognitive and graph clause\n"
    " solvers.\n"
    "\n"
    " It is not a separate \"Graph RAG engine\", a remote retrieval service, or an\n"
    " adaptive-learning system. Add a new intent only with an engine-backed AST\n"
    " contract and direct regression coverage.\n"
).

-type semantic_intent() :: {concept_recall, binary(), float(), integer()} |
    {connected_concept, integer(), binary(), binary()} |
    {evidence_graph, integer(), integer(), integer()}.

-file("src/aarondb/rag.gleam", 91).
-spec add_clause(aarondb@q:query_builder(), aarondb@shared@ast:body_clause()) -> aarondb@q:query_builder().
add_clause(Builder, Clause) ->
    {query_builder,
        erlang:element(2, Builder),
        lists:append(erlang:element(3, Builder), [Clause]),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/aarondb/rag.gleam", 95).
-spec set_limit(aarondb@q:query_builder(), integer()) -> aarondb@q:query_builder().
set_limit(Builder, Lim) ->
    {query_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        {some, Lim},
        erlang:element(6, Builder)}.

-file("src/aarondb/rag.gleam", 37).
?DOC(
    " Compiles a semantic intent into a pure AaronDB Query AST.\n"
    " Time Complexity: O(1) AST generation.\n"
    " Space Complexity: O(1) AST size.\n"
).
-spec build_query(semantic_intent()) -> aarondb@shared@ast:'query'().
build_query(Intent) ->
    Builder = case Intent of
        {concept_recall, Ctx, Threshold, Lim} ->
            _pipe = aarondb@q:select([<<"?engram"/utf8>>]),
            _pipe@1 = add_clause(
                _pipe,
                {cognitive,
                    aarondb@q:s(Ctx),
                    aarondb@q:s(Ctx),
                    Threshold,
                    <<"?engram"/utf8>>}
            ),
            set_limit(_pipe@1, Lim);

        {connected_concept, From_id, Target_ctx, Edge} ->
            _pipe@2 = aarondb@q:select([<<"?path"/utf8>>, <<"?engram"/utf8>>]),
            _pipe@3 = add_clause(
                _pipe@2,
                {cognitive,
                    aarondb@q:s(Target_ctx),
                    aarondb@q:s(Target_ctx),
                    0.5,
                    <<"?engram"/utf8>>}
            ),
            add_clause(
                _pipe@3,
                {shortest_path,
                    {uid, aarondb@fact:ref(From_id)},
                    aarondb@q:v(<<"?engram"/utf8>>),
                    Edge,
                    <<"?path"/utf8>>,
                    none,
                    {some, 5}}
            );

        {evidence_graph, A_id, B_id, Max_depth} ->
            _pipe@4 = aarondb@q:select([<<"?path"/utf8>>]),
            add_clause(
                _pipe@4,
                {shortest_path,
                    {uid, aarondb@fact:ref(A_id)},
                    {uid, aarondb@fact:ref(B_id)},
                    <<"engram/supports"/utf8>>,
                    <<"?path"/utf8>>,
                    none,
                    {some, Max_depth}}
            )
    end,
    {'query',
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.
