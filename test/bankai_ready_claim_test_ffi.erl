-module(bankai_ready_claim_test_ffi).
-export([race/1]).
race(Workspace) ->
    Parent = self(),
    Pids = [spawn(fun() -> receive go ->
        Parent ! {self(), 'bankai@daemon_store':claim_next_ready(Workspace, [<<"worker">>])}
    end end) || _ <- lists:seq(1, 12)],
    [P ! go || P <- Pids],
    Results = [receive {P, R} -> R after 30000 -> timeout end || P <- Pids],
    length([ok || {ok, _} <- Results]).
