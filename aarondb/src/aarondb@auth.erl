-module(aarondb@auth).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/auth.gleam").
-export([authorize/2, decode_token/1]).
-export_type([action/0, resource/0, capability/0, token/0, raw_cap/0, raw_token/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # auth — capability-based authorization\n"
    "\n"
    " Identity and authority for the gateway/MCP surface: `Action`, `Resource`,\n"
    " `Capability`, and `Token` types plus `authorize/3` and `decode_token/1`.\n"
    "\n"
    " ⚠️ Tokens are JSON-decoded here, **not** cryptographically signed or\n"
    " verified — this layer models capabilities, it does not authenticate\n"
    " provenance. Signature verification (if required) must happen upstream.\n"
).

-type action() :: read | write | admin.

-type resource() :: all | {shard, integer()} | {database, binary()}.

-type capability() :: {capability, action(), resource()}.

-type token() :: {token, binary(), list(capability()), binary()}.

-type raw_cap() :: {raw_cap, binary(), binary()}.

-type raw_token() :: {raw_token, binary(), list(raw_cap()), binary()}.

-file("src/aarondb/auth.gleam", 72).
-spec subsumes_resource(resource(), resource()) -> boolean().
subsumes_resource(Provided, Required) ->
    case {Provided, Required} of
        {all, _} ->
            true;

        {{database, P}, {database, R}} when P =:= R ->
            true;

        {{database, _}, {shard, _}} ->
            true;

        {{shard, P@1}, {shard, R@1}} when P@1 =:= R@1 ->
            true;

        {_, _} ->
            false
    end.

-file("src/aarondb/auth.gleam", 60).
?DOC(
    " Rich Hickey 🧙🏾‍♂️:\n"
    " Subsumption is a logical property. A broader capability subsumes a narrower one.\n"
    " e.g. Read(All) subsumes Read(Shard(1)).\n"
).
-spec subsumes(capability(), capability()) -> boolean().
subsumes(Provided, Required) ->
    case {erlang:element(2, Provided), erlang:element(2, Required)} of
        {admin, _} ->
            subsumes_resource(
                erlang:element(3, Provided),
                erlang:element(3, Required)
            );

        {P_act, R_act} when P_act =:= R_act ->
            subsumes_resource(
                erlang:element(3, Provided),
                erlang:element(3, Required)
            );

        {_, _} ->
            false
    end.

-file("src/aarondb/auth.gleam", 41).
?DOC(
    " Verifies if a given Token satisfies a list of required capabilities.\n"
    " Time Complexity: O(R * P) where R is required caps, P is provided caps.\n"
    " Space Complexity: O(1) auxiliary space.\n"
).
-spec authorize(token(), list(capability())) -> {ok, nil} | {error, binary()}.
authorize(Token, Required) ->
    Is_authorized = gleam@list:all(
        Required,
        fun(Req) ->
            gleam@list:any(
                erlang:element(3, Token),
                fun(Prov) -> subsumes(Prov, Req) end
            )
        end
    ),
    case Is_authorized of
        true ->
            {ok, nil};

        false ->
            {error,
                <<"Unauthorized: Insufficient capabilities in token."/utf8>>}
    end.

-file("src/aarondb/auth.gleam", 96).
?DOC(
    " Example simple parser from a JSON-like token format.\n"
    " In a real UCAN, you'd verify proper base64 + EdDSA signatures here.\n"
).
-spec decode_token(binary()) -> {ok, token()} |
    {error, gleam@json:decode_error()}.
decode_token(Payload) ->
    Cap_decoder = begin
        gleam@dynamic@decode:field(
            <<"op"/utf8>>,
            {decoder, fun gleam@dynamic@decode:decode_string/1},
            fun(Op) ->
                gleam@dynamic@decode:field(
                    <<"res"/utf8>>,
                    {decoder, fun gleam@dynamic@decode:decode_string/1},
                    fun(Res) ->
                        gleam@dynamic@decode:success({raw_cap, Op, Res})
                    end
                )
            end
        )
    end,
    Token_decoder = begin
        gleam@dynamic@decode:field(
            <<"id"/utf8>>,
            {decoder, fun gleam@dynamic@decode:decode_string/1},
            fun(Id) ->
                gleam@dynamic@decode:field(
                    <<"caps"/utf8>>,
                    gleam@dynamic@decode:list(Cap_decoder),
                    fun(Caps) ->
                        gleam@dynamic@decode:field(
                            <<"iss"/utf8>>,
                            {decoder, fun gleam@dynamic@decode:decode_string/1},
                            fun(Iss) ->
                                gleam@dynamic@decode:success(
                                    {raw_token, Id, Caps, Iss}
                                )
                            end
                        )
                    end
                )
            end
        )
    end,
    case gleam@json:parse(Payload, Token_decoder) of
        {ok, Raw} ->
            Caps@1 = gleam@list:filter_map(
                erlang:element(3, Raw),
                fun(C) ->
                    Action = case erlang:element(2, C) of
                        <<"read"/utf8>> ->
                            {ok, read};

                        <<"write"/utf8>> ->
                            {ok, write};

                        <<"admin"/utf8>> ->
                            {ok, admin};

                        _ ->
                            {error, nil}
                    end,
                    Resource = case erlang:element(3, C) of
                        <<"all"/utf8>> ->
                            {ok, all};

                        S ->
                            case gleam_stdlib:string_starts_with(
                                S,
                                <<"shard:"/utf8>>
                            ) of
                                true ->
                                    Num_str = gleam@string:replace(
                                        S,
                                        <<"shard:"/utf8>>,
                                        <<""/utf8>>
                                    ),
                                    case gleam_stdlib:parse_int(Num_str) of
                                        {ok, N} ->
                                            {ok, {shard, N}};

                                        {error, _} ->
                                            {error, nil}
                                    end;

                                false ->
                                    case gleam_stdlib:string_starts_with(
                                        S,
                                        <<"db:"/utf8>>
                                    ) of
                                        true ->
                                            {ok,
                                                {database,
                                                    gleam@string:replace(
                                                        S,
                                                        <<"db:"/utf8>>,
                                                        <<""/utf8>>
                                                    )}};

                                        false ->
                                            {error, nil}
                                    end
                            end
                    end,
                    case {Action, Resource} of
                        {{ok, A}, {ok, R}} ->
                            {ok, {capability, A, R}};

                        {_, _} ->
                            {error, nil}
                    end
                end
            ),
            {ok,
                {token, erlang:element(2, Raw), Caps@1, erlang:element(4, Raw)}};

        {error, E} ->
            {error, E}
    end.
