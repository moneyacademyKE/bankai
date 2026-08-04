-module(bankai_argv_ffi).
-export([get_args/0]).

%% init:get_plain_arguments/0 returns charlists; Gleam strings are UTF-8
%% binaries, so convert each argument before handing them over.
%%
%% When bankai runs as an escript, init:get_plain_arguments/0 leads with the
%% escript's own executable path; strip it so dispatch sees only the real CLI
%% args. Under `gleam run -- args` the first element is a bare command word, so
%% we keep Plain unchanged. We strip only when the first element resolves to an
%% existing file — a command word is never mistaken for the script path.
get_args() ->
    Plain = init:get_plain_arguments(),
    Args = case Plain of
        [First | Rest] ->
            case file:read_file_info(First) of
                {ok, _} -> Rest;
                _ -> Plain
            end;
        _ -> Plain
    end,
    [erlang:list_to_binary(A) || A <- Args].
