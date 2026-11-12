-module(aarondb_test_ffi).
-export([reductions/0]).

%% BEAM reductions are the runtime's own deterministic work counter:
%% a search that explores ~100 rounds of full-candidate scoring burns
%% an order of magnitude more reductions than one that stops when its
%% results stop changing. Used by the bk-86b0 termination regression.
reductions() ->
    {reductions, R} = process_info(self(), reductions),
    R.
