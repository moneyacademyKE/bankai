%% Workspace-local capability signing key management.
%%
%% The key is created exclusively with mode 0600 before secret bytes are
%% written. Existing keys are accepted only when they remain private. Gleam
%% receives the bytes but no public API exposes them; only signed attenuated
%% capabilities cross the Bankai socket protocol.
-module(bankai_service_auth_ffi).
-export([ensure_secret/1, reset_secret/1]).

-include_lib("kernel/include/file.hrl").

ensure_secret(Path) ->
    case read_private_secret(Path) of
        {ok, Secret} -> {ok, Secret};
        {error, enoent} -> create_secret(Path);
        {error, initializing} -> wait_for_secret(Path, 200);
        {error, Reason} when is_binary(Reason) -> {error, Reason};
        {error, Reason} -> {error, format_error("read service auth secret", Reason)}
    end.

read_private_secret(Path) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular, size = 0}} ->
            {error, initializing};
        {ok, #file_info{type = regular, mode = Mode}} when (Mode band 8#077) =:= 0 ->
            case file:read_file(Path) of
                {ok, Secret} when byte_size(Secret) =:= 32 -> {ok, Secret};
                {ok, <<>>} -> {error, initializing};
                {ok, _} -> {error, <<"service auth secret has invalid length">>};
                {error, Reason} -> {error, format_error("read service auth secret", Reason)}
            end;
        {ok, #file_info{type = regular}} ->
            {error, <<"service auth secret permissions must be 0600">>};
        {ok, _} ->
            {error, <<"service auth secret is not a regular file">>};
        {error, Reason} -> {error, Reason}
    end.

create_secret(Path) ->
    case filelib:ensure_dir(Path) of
        ok -> create_private_secret(Path);
        {error, Reason} -> {error, format_error("create service auth directory", Reason)}
    end.

create_private_secret(Path) ->
    Secret = crypto:strong_rand_bytes(32),
    case file:open(Path, [write, binary, raw, exclusive]) of
        {ok, File} ->
            case file:change_mode(Path, 8#600) of
                ok -> write_secret(Path, File, Secret);
                {error, Reason} ->
                    _ = file:close(File),
                    _ = file:delete(Path),
                    {error, format_error("secure service auth secret", Reason)}
            end;
        {error, eexist} -> wait_for_secret(Path, 200);
        {error, Reason} -> {error, format_error("create service auth secret", Reason)}
    end.

write_secret(Path, File, Secret) ->
    Write = file:write(File, Secret),
    Sync = case Write of ok -> file:sync(File); _ -> ok end,
    Close = file:close(File),
    case {Write, Sync, Close} of
        {ok, ok, ok} -> {ok, Secret};
        {{error, Reason}, _, _} -> cleanup_error(Path, "write service auth secret", Reason);
        {_, {error, Reason}, _} -> cleanup_error(Path, "sync service auth secret", Reason);
        {_, _, {error, Reason}} -> cleanup_error(Path, "close service auth secret", Reason)
    end.

wait_for_secret(Path, Attempts) when Attempts > 0 ->
    case read_private_secret(Path) of
        {error, initializing} ->
            timer:sleep(5),
            wait_for_secret(Path, Attempts - 1);
        Result -> Result
    end;
wait_for_secret(_Path, 0) ->
    {error, <<"service auth secret initialization timed out">>}.

cleanup_error(Path, Context, Reason) ->
    _ = file:delete(Path),
    {error, format_error(Context, Reason)}.

reset_secret(Path) ->
    _ = file:delete(Path),
    nil.

format_error(Context, Reason) ->
    iolist_to_binary(io_lib:format("~s: ~p", [Context, Reason])).
