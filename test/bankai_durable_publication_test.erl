-module(bankai_durable_publication_test).
-include_lib("eunit/include/eunit.hrl").
-export([run/0]).

run() ->
    case eunit:test(?MODULE, [verbose]) of
        ok -> nil;
        error -> error(publication_regressions_failed)
    end.

setup(Name) ->
    W = <<"/tmp/bankai_publication_", Name/binary>>,
    ok = filelib:ensure_dir(<<W/binary, "/placeholder">>),
    {ok, nil} = bankai_mnesia_ffi:init(W),
    {ok, nil} = bankai_mnesia_ffi:reset_workspace(W),
    {ok, _} = 'bankai@daemon_store':create(W, <<"first">>, []),
    W.

publish(W, Snapshot) ->
    'bankai@durable_export':publish(W, <<W/binary, "/tasks.jsonl">>, Snapshot).

snapshot(W) -> 'bankai@mnesia_store':exportable_versions(W).

interleaved_export_test() ->
    W = setup(<<"interleave">>), Parent = self(),
    {Old, Ref} = spawn_monitor(fun() ->
        Result = publish(W, fun() ->
            S = snapshot(W), Parent ! snapshot_taken,
            receive continue -> S end
        end),
        Parent ! {old_done, Result}
    end),
    receive snapshot_taken -> ok after 2000 -> error(snapshot_timeout) end,
    {ok, Before} = bankai_changefeed_ffi:high_watermark(W),
    {ok, _} = 'bankai@daemon_store':create(W, <<"second">>, []),
    %% The older publisher must retain its pre-snapshot offset.
    Old ! continue,
    receive {old_done, {ok, nil}} -> ok after 2000 -> error(export_timeout) end,
    receive {'DOWN', Ref, process, Old, normal} -> ok end,
    ?assertEqual({ok, Before}, bankai_changefeed_ffi:exported_offset(W)),
    {ok, nil} = 'bankai@durable_export':refresh_if_stale(W),
    {ok, Tasks} = 'bankai@sync@jsonl':load(<<W/binary, "/tasks.jsonl">>),
    ?assertEqual(2, length(Tasks)).

serialized_export_test() ->
    W = setup(<<"serialized">>), Parent = self(),
    Old = spawn(fun() ->
        Parent ! {old, publish(W, fun() ->
            S = snapshot(W), Parent ! locked,
            receive continue -> S end
        end)}
    end),
    receive locked -> ok after 2000 -> error(lock_timeout) end,
    {ok, _} = 'bankai@daemon_store':create(W, <<"second">>, []),
    New = spawn(fun() ->
        Parent ! {new, publish(W, fun() -> Parent ! entered, snapshot(W) end)}
    end),
    receive entered -> error(overlapping_snapshots) after 100 -> ok end,
    Old ! continue,
    receive {old, {ok, nil}} -> ok after 2000 -> error(old_timeout) end,
    receive {new, {ok, nil}} -> ok after 3000 -> exit(New, kill), error(new_timeout) end,
    receive entered -> ok end,
    {ok, Tasks} = 'bankai@sync@jsonl':load(<<W/binary, "/tasks.jsonl">>),
    ?assertEqual(2, length(Tasks)).

failed_publication_test() ->
    W = setup(<<"failure">>),
    Path = <<W/binary, "/tasks.jsonl">>,
    file:delete(Path), ok = file:make_dir(Path),
    try
        ?assertMatch({error, _}, publish(W, fun() -> snapshot(W) end)),
        ?assertEqual({ok, -1}, bankai_changefeed_ffi:exported_offset(W))
    after file:del_dir(Path) end,
    ?assertEqual({ok, nil}, 'bankai@durable_export':refresh_if_stale(W)).

killed_publisher_test() ->
    W = setup(<<"killed">>), Parent = self(),
    {ok, nil} = publish(W, fun() -> snapshot(W) end),
    Path = <<W/binary, "/tasks.jsonl">>, {ok, Original} = file:read_file(Path),
    {ok, _} = 'bankai@daemon_store':create(W, <<"second">>, []),
    {Pid, Ref} = spawn_monitor(fun() ->
        publish(W, fun() -> Parent ! locked, receive never -> snapshot(W) end end)
    end),
    receive locked -> ok after 2000 -> error(lock_timeout) end,
    exit(Pid, kill), receive {'DOWN', Ref, process, Pid, killed} -> ok end,
    ?assertEqual({ok, Original}, file:read_file(Path)),
    {ok, nil} = 'bankai@durable_export':refresh_if_stale(W),
    {ok, Tasks} = 'bankai@sync@jsonl':load(Path), ?assertEqual(2, length(Tasks)).

legacy_marker_test() ->
    W = setup(<<"legacy_marker">>),
    %% Old releases persisted an unscoped offset; it must not survive restart.
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write({bankai_change_meta_v1, {W, exported_offset_v1},
                      W, exported_offset_v1, 999})
    end),
    ?assertEqual({ok, -1}, bankai_changefeed_ffi:exported_offset(W)),
    ?assertEqual({ok, nil}, 'bankai@durable_export':refresh_if_stale(W)).

foreign_epoch_marker_test() ->
    W = setup(<<"foreign_epoch">>),
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write({bankai_change_meta_v1, {W, exported_offset_v1},
                      W, exported_offset_v1, {make_ref(), 999}})
    end),
    ?assertEqual({ok, -1}, bankai_changefeed_ffi:exported_offset(W)),
    ?assertEqual({ok, nil}, 'bankai@durable_export':refresh_if_stale(W)).

snapshot_failure_preserves_file_and_marker_test() ->
    W = setup(<<"snapshot_failure">>),
    {ok, nil} = publish(W, fun() -> snapshot(W) end),
    Path = <<W/binary, "/tasks.jsonl">>,
    Original = file:read_file(Path),
    Marker = bankai_changefeed_ffi:exported_offset(W),
    ?assertEqual({error, <<"snapshot failed">>},
                 publish(W, fun() -> {error, <<"snapshot failed">>} end)),
    ?assertEqual(Original, file:read_file(Path)),
    ?assertEqual(Marker, bankai_changefeed_ffi:exported_offset(W)).

custom_destination_does_not_mark_canonical_test() ->
    W = setup(<<"custom">>),
    {ok, _} = 'bankai@daemon_store':export_jsonl_to(W, <<W/binary, "/other.jsonl">>),
    ?assertEqual({ok, -1}, bankai_changefeed_ffi:exported_offset(W)).

compact_publishes_authoritative_history_test() ->
    W = setup(<<"compact">>),
    {ok, _} = 'bankai@daemon_store':compact(W),
    {ok, Expected} = snapshot(W),
    {ok, Actual} = 'bankai@sync@jsonl':load(<<W/binary, "/tasks.jsonl">>),
    ?assertEqual(lists:sort('bankai@storage@store':list(Expected)), lists:sort(Actual)),
    ?assertEqual(bankai_changefeed_ffi:high_watermark(W),
                 bankai_changefeed_ffi:exported_offset(W)).

explicit_export_waits_for_snapshot_test() ->
    W = setup(<<"explicit">>), Parent = self(),
    Old = spawn(fun() ->
        Parent ! {old, publish(W, fun() ->
            S = snapshot(W), Parent ! locked,
            receive continue -> S end
        end)}
    end),
    receive locked -> ok after 2000 -> error(lock_timeout) end,
    {ok, _} = 'bankai@daemon_store':create(W, <<"second">>, []),
    spawn(fun() -> Parent ! {explicit, 'bankai@daemon_store':export_jsonl(W)} end),
    receive {explicit, _} -> error(export_bypassed_lock) after 100 -> ok end,
    Old ! continue,
    receive {old, {ok, nil}} -> ok after 2000 -> error(old_timeout) end,
    receive {explicit, {ok, _}} -> ok after 3000 -> error(explicit_timeout) end,
    {ok, Tasks} = 'bankai@sync@jsonl':load(<<W/binary, "/tasks.jsonl">>),
    ?assertEqual(2, length(Tasks)).
