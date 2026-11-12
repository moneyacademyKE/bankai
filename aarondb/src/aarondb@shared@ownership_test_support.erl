-module(aarondb@shared@ownership_test_support).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/ownership_test_support.gleam").
-export([empty/3, has_no_optional_extensions/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/shared/ownership_test_support.gleam", 13).
?DOC(
    " Creates the one canonical all-empty state used by state-characterization\n"
    " tests. Production startup uses the same defaults in the transactor adapter.\n"
).
-spec empty(
    aarondb@storage:storage_adapter(),
    boolean(),
    gleam@option:option(binary())
) -> aarondb@shared@state:db_state().
empty(Store, Distributed, Ets_name) ->
    Reactive_actor@1 = case aarondb@reactive:start_link() of
        {ok, Reactive_actor} -> Reactive_actor;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"aarondb/shared/ownership_test_support"/utf8>>,
                        function => <<"empty"/utf8>>,
                        line => 18,
                        value => _assert_fail,
                        start => 507,
                        'end' => 560,
                        pattern_start => 518,
                        pattern_end => 536})
    end,
    {db_state,
        Store,
        aarondb@index:new_index(),
        aarondb@index:new_aindex(),
        aarondb@index:new_avindex(),
        0,
        [],
        maps:new(),
        maps:new(),
        [],
        Reactive_actor@1,
        [],
        Distributed,
        Ets_name,
        aarondb@vec_index:new(),
        maps:new(),
        aarondb@index@art:new(),
        maps:new(),
        maps:new(),
        maps:new(),
        [],
        maps:new(),
        maps:new(),
        {config, 1000, 1000, false, 10000},
        []}.

-file("src/aarondb/shared/ownership_test_support.gleam", 52).
-spec has_no_optional_extensions(aarondb@shared@state:db_state()) -> boolean().
has_no_optional_extensions(Db) ->
    View = aarondb@shared@ownership:view(Db),
    ((erlang:element(5, erlang:element(5, View)) =:= maps:new()) andalso (erlang:element(
        4,
        erlang:element(5, View)
    )
    =:= maps:new()))
    andalso (erlang:element(8, erlang:element(5, View)) =:= maps:new()).
