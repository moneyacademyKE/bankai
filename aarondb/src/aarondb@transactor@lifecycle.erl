-module(aarondb@transactor@lifecycle).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/transactor/lifecycle.gleam").
-export([handle_tick/1]).

-file("src/aarondb/transactor/lifecycle.gleam", 11).
-spec handle_tick(aarondb@shared@state:db_state()) -> aarondb@shared@state:db_state().
handle_tick(State) ->
    Current_tx = erlang:element(6, State),
    Cut_off = Current_tx - erlang:element(3, erlang:element(24, State)),
    Disk_attrs = begin
        _pipe = maps:to_list(erlang:element(8, State)),
        _pipe@1 = gleam@list:filter(
            _pipe,
            fun(Item) ->
                {_, Config} = Item,
                erlang:element(9, Config) =:= disk
            end
        ),
        gleam@list:map(_pipe@1, fun(Item@1) -> erlang:element(1, Item@1) end)
    end,
    {New_eavt, New_aevt, New_avet} = gleam@list:fold(
        Disk_attrs,
        {erlang:element(3, State),
            erlang:element(4, State),
            erlang:element(5, State)},
        fun(Acc, Attr) ->
            {Acc_eavt, Acc_aevt, Acc_avet} = Acc,
            Cold = begin
                _pipe@2 = aarondb@index:get_cold_datoms(Acc_eavt, Cut_off),
                gleam@list:filter(
                    _pipe@2,
                    fun(D) -> erlang:element(3, D) =:= Attr end
                )
            end,
            case Cold of
                [] ->
                    Acc;

                _ ->
                    case aarondb@storage:append(erlang:element(2, State), Cold) of
                        {error, _} ->
                            Acc;

                        {ok, nil} ->
                            case erlang:element(14, State) of
                                {some, Name} ->
                                    gleam@list:each(
                                        Cold,
                                        fun(D@1) ->
                                            _ = aarondb@index@ets:insert_datom(
                                                <<Name/binary, "_eavt"/utf8>>,
                                                erlang:element(2, D@1),
                                                D@1
                                            ),
                                            _ = aarondb@index@ets:insert_datom(
                                                <<Name/binary, "_aevt"/utf8>>,
                                                erlang:element(3, D@1),
                                                D@1
                                            )
                                        end
                                    );

                                none ->
                                    nil
                            end,
                            Next_eavt = aarondb@index:evict_from_memory(
                                Acc_eavt,
                                Cold
                            ),
                            Next_aevt = gleam@list:fold(
                                Cold,
                                Acc_aevt,
                                fun(A, D@2) ->
                                    aarondb@index:delete_aevt(A, D@2)
                                end
                            ),
                            Next_avet = gleam@list:fold(
                                Cold,
                                Acc_avet,
                                fun(A@1, D@3) ->
                                    aarondb@index:delete_avet(A@1, D@3)
                                end
                            ),
                            {Next_eavt, Next_aevt, Next_avet}
                    end
            end
        end
    ),
    case erlang:element(4, erlang:element(24, State)) of
        true ->
            _ = aarondb@engine@prefetch:analyze_history(
                erlang:element(25, State)
            ),
            case erlang:element(14, State) of
                {some, _} ->
                    nil;

                none ->
                    nil
            end;

        false ->
            nil
    end,
    {db_state,
        erlang:element(2, State),
        New_eavt,
        New_aevt,
        New_avet,
        erlang:element(6, State),
        erlang:element(7, State),
        erlang:element(8, State),
        erlang:element(9, State),
        erlang:element(10, State),
        erlang:element(11, State),
        erlang:element(12, State),
        erlang:element(13, State),
        erlang:element(14, State),
        erlang:element(15, State),
        erlang:element(16, State),
        erlang:element(17, State),
        erlang:element(18, State),
        erlang:element(19, State),
        erlang:element(20, State),
        erlang:element(21, State),
        erlang:element(22, State),
        erlang:element(23, State),
        erlang:element(24, State),
        erlang:element(25, State)}.
