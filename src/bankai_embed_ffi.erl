-module(bankai_embed_ffi).
-export([embed_remote/4, probe/2, sticky_get/1, sticky_put/2,
         sticky_clear/1, getenv/1]).

%% Local-only embedding transport for the bankai/embed seam. Posts to an
%% ollama /api/embed endpoint using OTP's native json module and inets httpc
%% — zero new package deps. Backend stickiness: the daemon resolves its
%% embedding backend once per boot and caches it in persistent_term, because
%% a single HNSW index build must never mix vector dimensionalities from two
%% backends (aarondb vec_index fixes dimensionality at the first vector and
%% rejects mismatches).

-define(PROBE_TEXT, <<"bankai embedding backend probe">>).
-define(PROBE_TIMEOUT_MS, 1000).

%% POST {Url}/api/embed {"model":M,"input":Text} -> {ok,[float()]}|{error,binary()}.
%% Accepts both the modern {"embeddings":[[…]]} and legacy {"embedding":[…]}.
embed_remote(Text, Url, Model, TimeoutMs) ->
    ensure_http(),
    Body = json:encode(#{<<"model">> => ensure_binary(Model),
                         <<"input">> => ensure_binary(Text)}),
    Request = {binary_to_list(ensure_binary(Url)) ++ "/api/embed",
               [], "application/json", Body},
    HttpOpts = [{timeout, TimeoutMs}, {connect_timeout, TimeoutMs}],
    case httpc:request(post, Request, HttpOpts,
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, RespBody}} -> decode_embeddings(RespBody);
        {ok, {{_, Code, _}, _, _}} ->
            {error, err("embed backend http status ~b", [Code])};
        {error, Reason} ->
            {error, err("embed backend unreachable: ~p", [Reason])}
    end.

%% Cheap reachability + dimensionality probe: embeds a fixed string once.
probe(Url, Model) ->
    case embed_remote(?PROBE_TEXT, Url, Model, ?PROBE_TIMEOUT_MS) of
        {ok, Vec} -> {ok, length(Vec)};
        Error -> Error
    end.

sticky_get(Key) ->
    case persistent_term:get(ensure_binary(Key), undefined) of
        undefined -> {error, nil};
        Value -> {ok, Value}
    end.

sticky_put(Key, Value) ->
    persistent_term:put(ensure_binary(Key), Value),
    nil.

sticky_clear(Key) ->
    persistent_term:erase(ensure_binary(Key)),
    nil.

getenv(Name) ->
    case os:getenv(binary_to_list(ensure_binary(Name))) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

%% --- internals ---

ensure_http() ->
    {ok, _} = application:ensure_all_started(inets),
    ok.

decode_embeddings(RespBody) ->
    Decoded = try json:decode(RespBody) catch _:_ -> invalid end,
    case Decoded of
        #{<<"embeddings">> := [Vec | _]} -> floats(Vec);
        #{<<"embedding">> := Vec} when is_list(Vec) -> floats(Vec);
        invalid -> {error, <<"embed backend returned malformed json">>};
        _ -> {error, <<"embed backend response missing embeddings">>}
    end.

floats(Vec) ->
    Numbers = [X || X <- Vec, is_number(X)],
    case Numbers =:= Vec of
        true -> {ok, [float(X) || X <- Vec]};
        false -> {error, <<"embed backend returned a non-numeric vector">>}
    end.

err(Format, Args) ->
    iolist_to_binary(io_lib:format(Format, Args)).

ensure_binary(B) when is_binary(B) -> B;
ensure_binary(B) when is_list(B) -> unicode:characters_to_binary(B).
