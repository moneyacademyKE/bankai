%% Workspace-local capability signing key management.
%%
%% The key is created atomically with mode 0600. Gleam receives the bytes but
%% no public API exposes them; only signed attenuated capabilities cross the
%% Bankai socket protocol.
-module(bankai_service_auth_ffi).
-export([ensure_secret/1, reset_secret/1]).

ensure_secret(Path) ->
    case file:read_file(Path) of
        {ok, Secret} when byte_size(Secret) =:= 32 -> {ok, Secret};
        {ok, _} -> {error, <<"service auth secret has invalid length">>};
        {error, enoent} -> create_secret(Path);
        {error, Reason} -> {error, format_error("read service auth secret", Reason)}
    end.

create_secret(Path) ->
    ok = filelib:ensure_dir(Path),
    Secret = crypto:strong_rand_bytes(32),
    case file:open(Path, [write, binary, raw, exclusive]) of
        {ok, File} ->
            Write = file:write(File, Secret),
            Close = file:close(File),
            _ = file:change_mode(Path, 8#600),
            case {Write, Close} of
                {ok, ok} -> {ok, Secret};
                {{error, Reason}, _} -> {error, format_error("write service auth secret", Reason)};
                {_, {error, Reason}} -> {error, format_error("close service auth secret", Reason)}
            end;
        {error, eexist} -> ensure_secret(Path);
        {error, Reason} -> {error, format_error("create service auth secret", Reason)}
    end.

reset_secret(Path) ->
    _ = file:delete(Path),
    nil.

format_error(Context, Reason) ->
    iolist_to_binary(io_lib:format("~s: ~p", [Context, Reason])).
