-module(bankai_metrics_ffi).
-export([snapshot/0]).

snapshot() ->
    Rows = gleamunison_metrics:list_metrics(),
    [iolist_to_binary(io_lib:format("~p", [Row])) || Row <- Rows].
