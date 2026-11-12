-module(aarondb@transactor@domain).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/domain.gleam").
-export([apply/2, compute_next_state/4]).
-export_type([transaction/0, outcome/0]).

-type transaction() :: {transaction,
        list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
        gleam@option:option(integer()),
        aarondb@fact:operation()}.

-type outcome() :: {outcome,
        aarondb@shared@state:db_state(),
        list(aarondb@fact:datom())}.

-file("src/aarondb/transactor/domain.gleam", 30).
-spec apply(aarondb@shared@state:db_state(), transaction()) -> {ok, outcome()} |
    {error, binary()}.
apply(Database, Transaction) ->
    {transaction, Facts, Valid_time, Operation} = Transaction,
    Tx_id = erlang:element(6, Database) + 1,
    Vt = gleam@option:unwrap(Valid_time, Tx_id),
    Resolved_facts = aarondb@transactor@apply:resolve_transaction_functions(
        Database,
        Tx_id,
        Vt,
        Facts
    ),
    Datoms_result = gleam@list:fold_until(
        Resolved_facts,
        {ok, []},
        fun(Acc_result, Fact_input) ->
            Acc@1 = case Acc_result of
                {ok, Acc} -> Acc;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"aarondb/transactor/domain"/utf8>>,
                                function => <<"apply"/utf8>>,
                                line => 42,
                                value => _assert_fail,
                                start => 1389,
                                'end' => 1420,
                                pattern_start => 1400,
                                pattern_end => 1407})
            end,
            Entity_result = case erlang:element(1, Fact_input) of
                {uid, Id} ->
                    {ok, Id};

                {lookup, Lookup} ->
                    {Attribute, Value} = Lookup,
                    case Attribute =:= <<"db/fn"/utf8>> of
                        true ->
                            {error,
                                <<"Unresolved transaction function: "/utf8,
                                    (gleam@string:inspect(Value))/binary>>};

                        false ->
                            _pipe = aarondb@index:get_entity_by_av(
                                erlang:element(5, Database),
                                Attribute,
                                Value
                            ),
                            gleam@result:replace_error(
                                _pipe,
                                <<"Lookup failed for "/utf8, Attribute/binary>>
                            )
                    end
            end,
            case Entity_result of
                {ok, Entity} ->
                    {continue,
                        {ok,
                            [{datom,
                                    Entity,
                                    erlang:element(2, Fact_input),
                                    erlang:element(3, Fact_input),
                                    Tx_id,
                                    erlang:length(Acc@1),
                                    Vt,
                                    Operation} |
                                Acc@1]}};

                {error, Error} ->
                    {stop, {error, Error}}
            end
        end
    ),
    case Datoms_result of
        {error, Error@1} ->
            {error, Error@1};

        {ok, Datoms} ->
            Datoms@1 = lists:reverse(Datoms),
            {Final_state, All_datoms, _} = gleam@list:fold(
                Datoms@1,
                {Database, [], 0},
                fun(Acc@2, Datom) ->
                    {Current_state, Collected, Next_index} = Acc@2,
                    {Next_state, Side_effect_datoms, Updated_index} = aarondb@transactor@apply:apply_datom(
                        Current_state,
                        {datom,
                            erlang:element(2, Datom),
                            erlang:element(3, Datom),
                            erlang:element(4, Datom),
                            erlang:element(5, Datom),
                            Next_index,
                            erlang:element(7, Datom),
                            erlang:element(8, Datom)},
                        Next_index
                    ),
                    {Next_state,
                        lists:append(Side_effect_datoms, Collected),
                        Updated_index}
                end
            ),
            All_datoms@1 = lists:reverse(All_datoms),
            Validation_result = gleam@list:fold_until(
                All_datoms@1,
                {ok, nil},
                fun(_, Datom@1) ->
                    case aarondb@transactor@validation:validate_datom(
                        Database,
                        All_datoms@1,
                        Datom@1
                    ) of
                        {ok, _} ->
                            {continue, {ok, nil}};

                        {error, Error@2} ->
                            {stop, {error, Error@2}}
                    end
                end
            ),
            case Validation_result of
                {ok, _} ->
                    {ok,
                        {outcome,
                            {db_state,
                                erlang:element(2, Final_state),
                                erlang:element(3, Final_state),
                                erlang:element(4, Final_state),
                                erlang:element(5, Final_state),
                                Tx_id,
                                erlang:element(7, Final_state),
                                erlang:element(8, Final_state),
                                erlang:element(9, Final_state),
                                erlang:element(10, Final_state),
                                erlang:element(11, Final_state),
                                erlang:element(12, Final_state),
                                erlang:element(13, Final_state),
                                erlang:element(14, Final_state),
                                erlang:element(15, Final_state),
                                erlang:element(16, Final_state),
                                erlang:element(17, Final_state),
                                erlang:element(18, Final_state),
                                erlang:element(19, Final_state),
                                erlang:element(20, Final_state),
                                erlang:element(21, Final_state),
                                erlang:element(22, Final_state),
                                erlang:element(23, Final_state),
                                erlang:element(24, Final_state),
                                erlang:element(25, Final_state)},
                            All_datoms@1}};

                {error, Error@3} ->
                    {error, Error@3}
            end
    end.

-file("src/aarondb/transactor/domain.gleam", 117).
-spec compute_next_state(
    aarondb@shared@state:db_state(),
    list({aarondb@fact:eid(), binary(), aarondb@fact:value()}),
    gleam@option:option(integer()),
    aarondb@fact:operation()
) -> {ok, {aarondb@shared@state:db_state(), list(aarondb@fact:datom())}} |
    {error, binary()}.
compute_next_state(Database, Facts, Valid_time, Operation) ->
    _pipe = apply(Database, {transaction, Facts, Valid_time, Operation}),
    gleam@result:map(
        _pipe,
        fun(Outcome) ->
            {outcome, Next_state, Datoms} = Outcome,
            {Next_state, Datoms}
        end
    ).
