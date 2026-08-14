-module(bankai_argv_ffi).
-export([get_args/0, to_utf8/1]).

%% init:get_plain_arguments/0 returns charlists; Gleam strings are UTF-8
%% binaries, so convert each argument before handing them over. Codepoints
%% above 255 (em-dash, accents, CJK) are NOT bytes — list_to_binary crashes
%% with badarg on them — so unicode:characters_to_binary/1 encodes the
%% codepoint list as UTF-8, exactly Gleam's string representation. (bk-cb86)
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
    [to_utf8(A) || A <- Args].

to_utf8(Chars) ->
    unicode:characters_to_binary(Chars).
