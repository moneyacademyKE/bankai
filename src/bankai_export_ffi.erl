-module(bankai_export_ffi).
-export([with_lock/2, atomic_write/2, with_staging/2]).

with_staging(Workspace, Action) ->
    Suffix = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Path = <<Workspace/binary, "/.compact-", Suffix/binary>>,
    try Action(Path) after file:delete(Path) end.

%% One local filesystem has one publisher. global monitors the owning process,
%% releasing the lock on death; no new server or durable lock recovery protocol.
%% Nested publication (compact -> export -> JSONL) must not release it early.
with_lock(Path, Action) ->
    Resource = {?MODULE, filename:absname(Path)},
    case get(Resource) of
        held -> Action();
        undefined ->
            global:trans({Resource, self()}, fun() ->
                put(Resource, held),
                try Action() after erase(Resource) end
            end, [node()])
    end.

%% Never truncate the visible snapshot. Sync and close a private sibling before
%% rename; failure at any stage returns an error and cannot acknowledge a feed
%% offset. On VM restart export markers are invalid, covering the rename/marker
%% crash window and filesystems that lose the directory entry on power failure.
atomic_write(Path, Body) ->
    with_lock(Path, fun() ->
        Suffix = integer_to_binary(erlang:unique_integer([positive, monotonic])),
        Temp = <<Path/binary, ".publish-", Suffix/binary>>,
        case file:open(Temp, [write, binary, raw, exclusive]) of
            {ok, File} ->
                try
                    Written = case file:write(File, Body) of
                        ok -> file:sync(File);
                        WriteError -> WriteError
                    end,
                    Closed = file:close(File),
                    case {Written, Closed} of
                        {ok, ok} -> result(file:rename(Temp, Path));
                        {{error, _} = Error, _} -> Error;
                        {_, {error, _} = Error} -> Error
                    end
                after
                    file:close(File),
                    file:delete(Temp)
                end;
            {error, _} = Error -> Error
        end
    end).

result(ok) -> {ok, nil};
result({error, _} = Error) -> Error.
