-module(bankai_argv_ffi).
-export([get_args/0]).

%% init:get_plain_arguments/0 returns charlists; Gleam strings are UTF-8
%% binaries, so convert each argument before handing them over.
get_args() ->
    lists:map(fun erlang:list_to_binary/1, init:get_plain_arguments()).
