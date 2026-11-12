-module(aarondb@mcp@server).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/mcp/server.gleam").
-export([send_response/1, execute_tool/3, handle_request/2, start/1]).
-export_type([json_rpc_request/0, json_rpc_response/0, json_rpc_error/0, server_message/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # mcp/server — Model Context Protocol entry point\n"
    "\n"
    " JSON-RPC MCP server: `handle_request/2` dispatches tool calls through the\n"
    " `gateway` (which enforces `auth`) and the `rag` semantic-intent layer.\n"
    " `start/1` exposes a typed actor for request/response integration.\n"
).

-type json_rpc_request() :: {json_rpc_request,
        binary(),
        gleam@option:option(binary()),
        binary(),
        gleam@option:option(gleam@dynamic:dynamic_())}.

-type json_rpc_response() :: {json_rpc_response,
        binary(),
        gleam@option:option(binary()),
        gleam@option:option(gleam@json:json()),
        gleam@option:option(json_rpc_error())}.

-type json_rpc_error() :: {json_rpc_error,
        integer(),
        binary(),
        gleam@option:option(gleam@json:json())}.

-type server_message() :: {request,
        json_rpc_request(),
        gleam@erlang@process:subject(json_rpc_response())} |
    stop.

-file("src/aarondb/mcp/server.gleam", 58).
-spec response_to_json(json_rpc_response()) -> gleam@json:json().
response_to_json(Response) ->
    gleam@json:object(
        [{<<"jsonrpc"/utf8>>, gleam@json:string(erlang:element(2, Response))},
            {<<"id"/utf8>>,
                gleam@json:nullable(
                    erlang:element(3, Response),
                    fun gleam@json:string/1
                )},
            {<<"result"/utf8>>,
                gleam@json:nullable(
                    erlang:element(4, Response),
                    fun(X) -> X end
                )},
            {<<"error"/utf8>>,
                gleam@json:nullable(
                    erlang:element(5, Response),
                    fun(E) ->
                        gleam@json:object(
                            [{<<"code"/utf8>>,
                                    gleam@json:int(erlang:element(2, E))},
                                {<<"message"/utf8>>,
                                    gleam@json:string(erlang:element(3, E))},
                                {<<"data"/utf8>>,
                                    gleam@json:nullable(
                                        erlang:element(4, E),
                                        fun(X@1) -> X@1 end
                                    )}]
                        )
                    end
                )}]
    ).

-file("src/aarondb/mcp/server.gleam", 54).
-spec send_response(json_rpc_response()) -> nil.
send_response(Response) ->
    _pipe = response_to_json(Response),
    _pipe@1 = gleam@json:to_string(_pipe),
    gleam_stdlib:println(_pipe@1).

-file("src/aarondb/mcp/server.gleam", 313).
-spec value_to_json(aarondb@fact:value()) -> gleam@json:json().
value_to_json(Value) ->
    case Value of
        {str, Value@1} ->
            gleam@json:string(Value@1);

        {int, Value@2} ->
            gleam@json:int(Value@2);

        {float, Value@3} ->
            gleam@json:float(Value@3);

        {bool, Value@4} ->
            gleam@json:bool(Value@4);

        {list, Values} ->
            gleam@json:array(Values, fun value_to_json/1);

        {vec, Values@1} ->
            gleam@json:array(Values@1, fun gleam@json:float/1);

        {ref, {entity_id, Id}} ->
            gleam@json:object([{<<"ref"/utf8>>, gleam@json:int(Id)}]);

        {map, Values@2} ->
            gleam@json:object(
                begin
                    _pipe = maps:to_list(Values@2),
                    gleam@list:map(
                        _pipe,
                        fun(Pair) ->
                            {Key, Value@5} = Pair,
                            {Key, value_to_json(Value@5)}
                        end
                    )
                end
            );

        {blob, Value@6} ->
            gleam@json:object(
                [{<<"blob_base64"/utf8>>,
                        gleam@json:string(
                            gleam_stdlib:base64_encode(Value@6, true)
                        )}]
            )
    end.

-file("src/aarondb/mcp/server.gleam", 337).
-spec pull_result_to_json(aarondb@shared@query_types:pull_result()) -> gleam@json:json().
pull_result_to_json(Value) ->
    case Value of
        {pull_map, Values} ->
            gleam@json:object(
                begin
                    _pipe = maps:to_list(Values),
                    gleam@list:map(
                        _pipe,
                        fun(Pair) ->
                            {Key, Value@1} = Pair,
                            {Key, pull_result_to_json(Value@1)}
                        end
                    )
                end
            );

        {pull_single, Value@2} ->
            value_to_json(Value@2);

        {pull_many, Values@1} ->
            gleam@json:array(Values@1, fun value_to_json/1);

        {pull_nested_many, Values@2} ->
            gleam@json:array(Values@2, fun pull_result_to_json/1);

        {pull_raw_binary, Value@3} ->
            gleam@json:object(
                [{<<"blob_base64"/utf8>>,
                        gleam@json:string(
                            gleam_stdlib:base64_encode(Value@3, true)
                        )}]
            )
    end.

-file("src/aarondb/mcp/server.gleam", 172).
-spec handle_read(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@dynamic:dynamic_()
) -> {ok, gleam@json:json()} | {error, binary()}.
handle_read(Db, Args) ->
    Decoder = begin
        gleam@dynamic@decode:field(
            <<"id"/utf8>>,
            {decoder, fun gleam@dynamic@decode:decode_int/1},
            fun(Id) ->
                gleam@dynamic@decode:field(
                    <<"capability_token"/utf8>>,
                    {decoder, fun gleam@dynamic@decode:decode_string/1},
                    fun(Capability_token) ->
                        gleam@dynamic@decode:success({Id, Capability_token})
                    end
                )
            end
        )
    end,
    case gleam@dynamic@decode:run(Args, Decoder) of
        {ok, {Id@1, Capability_token@1}} ->
            case aarondb@auth:decode_token(Capability_token@1) of
                {ok, Token} ->
                    case aarondb@auth:authorize(
                        Token,
                        [{capability, read, all}]
                    ) of
                        {ok, nil} ->
                            {ok,
                                gleam@json:object(
                                    [{<<"id"/utf8>>, gleam@json:int(Id@1)},
                                        {<<"engram"/utf8>>,
                                            pull_result_to_json(
                                                aarondb:pull(
                                                    Db,
                                                    aarondb@fact:uid(Id@1),
                                                    aarondb:pull_all()
                                                )
                                            )}]
                                )};

                        {error, E} ->
                            {error, <<"Unauthorized: "/utf8, E/binary>>}
                    end;

                {error, _} ->
                    {error, <<"Unauthorized: Invalid token format"/utf8>>}
            end;

        {error, E@1} ->
            {error,
                <<"Invalid params: "/utf8, (gleam@string:inspect(E@1))/binary>>}
    end.

-file("src/aarondb/mcp/server.gleam", 358).
-spec row_to_json(gleam@dict:dict(binary(), aarondb@fact:value())) -> gleam@json:json().
row_to_json(Row) ->
    gleam@json:object(
        begin
            _pipe = maps:to_list(Row),
            gleam@list:map(
                _pipe,
                fun(Pair) ->
                    {Key, Value} = Pair,
                    {Key, value_to_json(Value)}
                end
            )
        end
    ).

-file("src/aarondb/mcp/server.gleam", 140).
-spec handle_recall(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@dynamic:dynamic_()
) -> {ok, gleam@json:json()} | {error, binary()}.
handle_recall(Db, Args) ->
    Decoder = begin
        gleam@dynamic@decode:field(
            <<"context"/utf8>>,
            gleam@dynamic@decode:list(
                {decoder, fun gleam@dynamic@decode:decode_string/1}
            ),
            fun(Contexts) ->
                gleam@dynamic@decode:field(
                    <<"capability_token"/utf8>>,
                    {decoder, fun gleam@dynamic@decode:decode_string/1},
                    fun(Capability_token) ->
                        gleam@dynamic@decode:success(
                            {Contexts, Capability_token}
                        )
                    end
                )
            end
        )
    end,
    case gleam@dynamic@decode:run(Args, Decoder) of
        {ok, {Contexts@1, Capability_token@1}} ->
            Ctx_str = gleam@result:unwrap(
                gleam@list:first(Contexts@1),
                <<"unclassified"/utf8>>
            ),
            Intent = {concept_recall, Ctx_str, 0.5, 10},
            Query_ast = aarondb@rag:build_query(Intent),
            Required_caps = [{capability, read, all}],
            case aarondb@gateway:authorize_and_query(
                Db,
                Capability_token@1,
                erlang:element(3, Query_ast),
                Required_caps
            ) of
                {ok, Results} ->
                    {ok,
                        gleam@json:array(
                            erlang:element(2, Results),
                            fun row_to_json/1
                        )};

                {error, {unauthorized, E}} ->
                    {error, <<"Unauthorized: "/utf8, E/binary>>};

                {error, {transact_error, E@1}} ->
                    {error, <<"Transaction failed: "/utf8, E@1/binary>>};

                {error, {query_error, E@2}} ->
                    {error, <<"Query failed: "/utf8, E@2/binary>>}
            end;

        {error, E@3} ->
            {error,
                <<"Invalid params: "/utf8, (gleam@string:inspect(E@3))/binary>>}
    end.

-file("src/aarondb/mcp/server.gleam", 91).
-spec handle_remember(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    gleam@dynamic:dynamic_()
) -> {ok, gleam@json:json()} | {error, binary()}.
handle_remember(Db, Args) ->
    Decoder = begin
        gleam@dynamic@decode:field(
            <<"content"/utf8>>,
            {decoder, fun gleam@dynamic@decode:decode_string/1},
            fun(Content) ->
                gleam@dynamic@decode:optional_field(
                    <<"concept"/utf8>>,
                    none,
                    gleam@dynamic@decode:optional(
                        {decoder, fun gleam@dynamic@decode:decode_string/1}
                    ),
                    fun(Concept) ->
                        gleam@dynamic@decode:optional_field(
                            <<"confidence"/utf8>>,
                            none,
                            gleam@dynamic@decode:optional(
                                {decoder,
                                    fun gleam@dynamic@decode:decode_float/1}
                            ),
                            fun(Confidence) ->
                                gleam@dynamic@decode:field(
                                    <<"capability_token"/utf8>>,
                                    {decoder,
                                        fun gleam@dynamic@decode:decode_string/1},
                                    fun(Capability_token) ->
                                        gleam@dynamic@decode:success(
                                            {Content,
                                                Concept,
                                                Confidence,
                                                Capability_token}
                                        )
                                    end
                                )
                            end
                        )
                    end
                )
            end
        )
    end,
    case gleam@dynamic@decode:run(Args, Decoder) of
        {ok, {Content@1, Concept@1, Confidence@1, Capability_token@1}} ->
            Id = erlang:phash2(Content@1),
            Concept_str = gleam@option:unwrap(
                Concept@1,
                <<"unclassified"/utf8>>
            ),
            Conf_val = gleam@option:unwrap(Confidence@1, 1.0),
            Facts = [{aarondb@fact:uid(Id),
                    <<"engram/content"/utf8>>,
                    {str, Content@1}},
                {aarondb@fact:uid(Id),
                    <<"engram/concept"/utf8>>,
                    {str, Concept_str}},
                {aarondb@fact:uid(Id),
                    <<"engram/context"/utf8>>,
                    {str, Concept_str}},
                {aarondb@fact:uid(Id),
                    <<"engram/relevance"/utf8>>,
                    {float, Conf_val}}],
            Required_caps = [{capability, write, all}],
            case aarondb@gateway:authorize_and_transact(
                Db,
                Capability_token@1,
                Facts,
                Required_caps
            ) of
                {ok, _} ->
                    {ok,
                        gleam@json:object([{<<"id"/utf8>>, gleam@json:int(Id)}])};

                {error, {unauthorized, E}} ->
                    {error, <<"Unauthorized: "/utf8, E/binary>>};

                {error, {transact_error, E@1}} ->
                    {error, <<"Transaction failed: "/utf8, E@1/binary>>};

                {error, {query_error, E@2}} ->
                    {error, <<"Query failed: "/utf8, E@2/binary>>}
            end;

        {error, E@3} ->
            {error,
                <<"Invalid params: "/utf8, (gleam@string:inspect(E@3))/binary>>}
    end.

-file("src/aarondb/mcp/server.gleam", 78).
-spec execute_tool(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    binary(),
    gleam@dynamic:dynamic_()
) -> {ok, gleam@json:json()} | {error, binary()}.
execute_tool(Db, Name, Args) ->
    case Name of
        <<"muninn_remember"/utf8>> ->
            handle_remember(Db, Args);

        <<"muninn_recall"/utf8>> ->
            handle_recall(Db, Args);

        <<"muninn_read"/utf8>> ->
            handle_read(Db, Args);

        _ ->
            {error, <<"Unsupported MCP tool in AaronDB: "/utf8, Name/binary>>}
    end.

-file("src/aarondb/mcp/server.gleam", 221).
-spec handle_method(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    json_rpc_request()
) -> json_rpc_response().
handle_method(Db, Req) ->
    case erlang:element(4, Req) of
        <<"initialize"/utf8>> ->
            {json_rpc_response,
                <<"2.0"/utf8>>,
                erlang:element(3, Req),
                {some,
                    gleam@json:object(
                        [{<<"protocolVersion"/utf8>>,
                                gleam@json:string(<<"2024-11-05"/utf8>>)},
                            {<<"capabilities"/utf8>>,
                                gleam@json:object(
                                    [{<<"tools"/utf8>>, gleam@json:object([])}]
                                )},
                            {<<"serverInfo"/utf8>>,
                                gleam@json:object(
                                    [{<<"name"/utf8>>,
                                            gleam@json:string(
                                                <<"aarondb"/utf8>>
                                            )},
                                        {<<"version"/utf8>>,
                                            gleam@json:string(<<"3.0.0"/utf8>>)}]
                                )}]
                    )},
                none};

        <<"notifications/initialized"/utf8>> ->
            {json_rpc_response,
                <<"2.0"/utf8>>,
                erlang:element(3, Req),
                {some, gleam@json:object([])},
                none};

        <<"tools/list"/utf8>> ->
            Result = gleam@json:object(
                [{<<"tools"/utf8>>,
                        aarondb@mcp@tools:precompiled_array(
                            gleam@list:map(
                                aarondb@mcp@tools:all_tools(),
                                fun(T) ->
                                    gleam@json:object(
                                        [{<<"name"/utf8>>,
                                                gleam@json:string(
                                                    erlang:element(2, T)
                                                )},
                                            {<<"description"/utf8>>,
                                                gleam@json:string(
                                                    erlang:element(3, T)
                                                )},
                                            {<<"inputSchema"/utf8>>,
                                                erlang:element(4, T)}]
                                    )
                                end
                            )
                        )}]
            ),
            {json_rpc_response,
                <<"2.0"/utf8>>,
                erlang:element(3, Req),
                {some, Result},
                none};

        <<"tools/call"/utf8>> ->
            case erlang:element(5, Req) of
                {some, Params} ->
                    Call_decoder = begin
                        gleam@dynamic@decode:field(
                            <<"name"/utf8>>,
                            {decoder, fun gleam@dynamic@decode:decode_string/1},
                            fun(Name) ->
                                gleam@dynamic@decode:field(
                                    <<"arguments"/utf8>>,
                                    {decoder,
                                        fun gleam@dynamic@decode:decode_dynamic/1},
                                    fun(Arguments) ->
                                        gleam@dynamic@decode:success(
                                            {Name, Arguments}
                                        )
                                    end
                                )
                            end
                        )
                    end,
                    case gleam@dynamic@decode:run(Params, Call_decoder) of
                        {ok, {Name@1, Args}} ->
                            case execute_tool(Db, Name@1, Args) of
                                {ok, Res} ->
                                    {json_rpc_response,
                                        <<"2.0"/utf8>>,
                                        erlang:element(3, Req),
                                        {some, Res},
                                        none};

                                {error, E} ->
                                    {json_rpc_response,
                                        <<"2.0"/utf8>>,
                                        erlang:element(3, Req),
                                        none,
                                        {some,
                                            {json_rpc_error, -32000, E, none}}}
                            end;

                        {error, _} ->
                            {json_rpc_response,
                                <<"2.0"/utf8>>,
                                erlang:element(3, Req),
                                none,
                                {some,
                                    {json_rpc_error,
                                        -32602,
                                        <<"Invalid tool call params"/utf8>>,
                                        none}}}
                    end;

                none ->
                    {json_rpc_response,
                        <<"2.0"/utf8>>,
                        erlang:element(3, Req),
                        none,
                        {some,
                            {json_rpc_error,
                                -32602,
                                <<"Missing params"/utf8>>,
                                none}}}
            end;

        _ ->
            {json_rpc_response,
                <<"2.0"/utf8>>,
                erlang:element(3, Req),
                none,
                {some,
                    {json_rpc_error, -32601, <<"Method not found"/utf8>>, none}}}
    end.

-file("src/aarondb/mcp/server.gleam", 208).
-spec handle_request(
    gleam@erlang@process:subject(aarondb@transactor:message()),
    json_rpc_request()
) -> json_rpc_response().
handle_request(Db, Req) ->
    case erlang:element(2, Req) /= <<"2.0"/utf8>> of
        true ->
            {json_rpc_response,
                <<"2.0"/utf8>>,
                erlang:element(3, Req),
                none,
                {some,
                    {json_rpc_error,
                        -32600,
                        <<"jsonrpc must be 2.0"/utf8>>,
                        none}}};

        false ->
            handle_method(Db, Req)
    end.

-file("src/aarondb/mcp/server.gleam", 369).
?DOC(" Start the MCP request actor and return its typed message subject.\n").
-spec start(gleam@erlang@process:subject(aarondb@transactor:message())) -> {ok,
        gleam@erlang@process:subject(server_message())} |
    {error, gleam@otp@actor:start_error()}.
start(Db) ->
    _pipe = gleam@otp@actor:new(Db),
    _pipe@1 = gleam@otp@actor:on_message(
        _pipe,
        fun(Current_db, Message) -> case Message of
                {request, Request, Reply} ->
                    gleam@erlang@process:send(
                        Reply,
                        handle_request(Current_db, Request)
                    ),
                    gleam@otp@actor:continue(Current_db);

                stop ->
                    gleam@otp@actor:stop()
            end end
    ),
    _pipe@2 = gleam@otp@actor:start(_pipe@1),
    gleam@result:map(_pipe@2, fun(Started) -> erlang:element(3, Started) end).
