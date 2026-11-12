-module(aarondb@gateway).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/gateway.gleam").
-export([authorize_and_transact/4, authorize_and_query/4]).
-export_type([gateway_error/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # gateway — authorized access to the core\n"
    "\n"
    " The in-process authorization boundary over the database: checks a `Token`'s\n"
    " capabilities via `auth`, then transacts or queries the core.\n"
    " `authorize_and_transact/4` and `authorize_and_query/4`. No HTTP — this is the\n"
    " programmatic surface the MCP server is built on.\n"
).

-type gateway_error() :: {unauthorized, binary()} |
    {transact_error, binary()} |
    {query_error, binary()}.

-file("src/aarondb/gateway.gleam", 21).
?DOC(
    " Rich Hickey 🧙🏾‍♂️: The Gateway is a pure authorization boundary.\n"
    " It verifies capabilities before any AST reaches the internal logic.\n"
).
-spec authorize_and_transact(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    list(aarondb@auth:capability())
) -> {ok, integer()} | {error, gateway_error()}.
authorize_and_transact(Db, Token_str, Facts, Required_caps) ->
    case aarondb@auth:decode_token(Token_str) of
        {ok, Token} ->
            case aarondb@auth:authorize(Token, Required_caps) of
                {ok, nil} ->
                    case aarondb:transact(Db, Facts) of
                        {ok, Receipt} ->
                            {ok, erlang:element(6, Receipt)};

                        {error, E} ->
                            {error, {transact_error, E}}
                    end;

                {error, E@1} ->
                    {error,
                        {unauthorized,
                            <<"Insufficient Capabilities: "/utf8, E@1/binary>>}}
            end;

        {error, _} ->
            {error, {unauthorized, <<"Invalid Capability Token Format"/utf8>>}}
    end.

-file("src/aarondb/gateway.gleam", 43).
-spec authorize_and_query(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    list(aarondb@shared@ast:body_clause()),
    list(aarondb@auth:capability())
) -> {ok, aarondb@shared@query_types:query_result()} | {error, gateway_error()}.
authorize_and_query(Db, Token_str, Query_ast, Required_caps) ->
    case aarondb@auth:decode_token(Token_str) of
        {ok, Token} ->
            case aarondb@auth:authorize(Token, Required_caps) of
                {ok, nil} ->
                    {ok, aarondb:'query'(Db, Query_ast)};

                {error, E} ->
                    {error,
                        {unauthorized,
                            <<"Insufficient Capabilities: "/utf8, E/binary>>}}
            end;

        {error, _} ->
            {error, {unauthorized, <<"Invalid Capability Token Format"/utf8>>}}
    end.
