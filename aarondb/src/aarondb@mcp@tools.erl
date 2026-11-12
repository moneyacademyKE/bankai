-module(aarondb@mcp@tools).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/mcp/tools.gleam").
-export([precompiled_array/1, all_tools/0]).
-export_type([tool/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # mcp/tools — MCP tool registry\n"
    "\n"
    " Tool definitions exposed to MCP clients: `all_tools/0` returns the\n"
    " registry. Pure data over `gleam/json`; no side effects.\n"
).

-type tool() :: {tool, binary(), binary(), gleam@json:json()}.

-file("src/aarondb/mcp/tools.gleam", 18).
-spec precompiled_array(list(gleam@json:json())) -> gleam@json:json().
precompiled_array(Items) ->
    gleam@json:array(Items, fun(X) -> X end).

-file("src/aarondb/mcp/tools.gleam", 44).
-spec string_property(binary()) -> gleam@json:json().
string_property(Description) ->
    gleam@json:object(
        [{<<"type"/utf8>>, gleam@json:string(<<"string"/utf8>>)},
            {<<"description"/utf8>>, gleam@json:string(Description)}]
    ).

-file("src/aarondb/mcp/tools.gleam", 33).
-spec schema(list({binary(), gleam@json:json()}), list(binary())) -> gleam@json:json().
schema(Properties, Required) ->
    gleam@json:object(
        [{<<"type"/utf8>>, gleam@json:string(<<"object"/utf8>>)},
            {<<"properties"/utf8>>, gleam@json:object(Properties)},
            {<<"required"/utf8>>,
                precompiled_array(
                    gleam@list:map(Required, fun gleam@json:string/1)
                )}]
    ).

-file("src/aarondb/mcp/tools.gleam", 94).
-spec read_tool() -> tool().
read_tool() ->
    {tool,
        <<"muninn_read"/utf8>>,
        <<"Fetch a memory by numeric ID."/utf8>>,
        schema(
            [{<<"id"/utf8>>,
                    gleam@json:object(
                        [{<<"type"/utf8>>,
                                gleam@json:string(<<"integer"/utf8>>)}]
                    )},
                {<<"capability_token"/utf8>>,
                    string_property(<<"Read capability token."/utf8>>)}],
            [<<"id"/utf8>>, <<"capability_token"/utf8>>]
        )}.

-file("src/aarondb/mcp/tools.gleam", 74).
-spec recall_tool() -> tool().
recall_tool() ->
    {tool,
        <<"muninn_recall"/utf8>>,
        <<"Search memories by concept and context."/utf8>>,
        schema(
            [{<<"context"/utf8>>,
                    gleam@json:object(
                        [{<<"type"/utf8>>, gleam@json:string(<<"array"/utf8>>)},
                            {<<"items"/utf8>>,
                                gleam@json:object(
                                    [{<<"type"/utf8>>,
                                            gleam@json:string(<<"string"/utf8>>)}]
                                )}]
                    )},
                {<<"capability_token"/utf8>>,
                    string_property(<<"Read capability token."/utf8>>)}],
            [<<"context"/utf8>>, <<"capability_token"/utf8>>]
        )}.

-file("src/aarondb/mcp/tools.gleam", 51).
-spec number_property(binary()) -> gleam@json:json().
number_property(Description) ->
    gleam@json:object(
        [{<<"type"/utf8>>, gleam@json:string(<<"number"/utf8>>)},
            {<<"description"/utf8>>, gleam@json:string(Description)}]
    ).

-file("src/aarondb/mcp/tools.gleam", 58).
-spec remember_tool() -> tool().
remember_tool() ->
    {tool,
        <<"muninn_remember"/utf8>>,
        <<"Store a memory with optional concept and confidence."/utf8>>,
        schema(
            [{<<"content"/utf8>>,
                    string_property(<<"The information to remember."/utf8>>)},
                {<<"concept"/utf8>>,
                    string_property(<<"A concept label."/utf8>>)},
                {<<"confidence"/utf8>>,
                    number_property(<<"Confidence from 0.0 to 1.0."/utf8>>)},
                {<<"capability_token"/utf8>>,
                    string_property(<<"Write capability token."/utf8>>)}],
            [<<"content"/utf8>>, <<"capability_token"/utf8>>]
        )}.

-file("src/aarondb/mcp/tools.gleam", 25).
?DOC(
    " Only the three handlers below are executable in this build. The registry also\n"
    " describes a larger Muninn-compatible surface, but advertising unsupported\n"
    " operations would make `tools/list` lie to clients.\n"
).
-spec all_tools() -> list(tool()).
all_tools() ->
    [remember_tool(), recall_tool(), read_tool()].
