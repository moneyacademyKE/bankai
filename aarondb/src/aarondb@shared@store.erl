-module(aarondb@shared@store).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/store.gleam").
-export([find_datoms/2]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/aarondb/shared/store.gleam", 9).
?DOC(
    " Retrieves datoms matching a pattern from the database indices.\n"
    " Rich Hickey alignment: \"The index is an implementation detail of the fact store.\"\n"
).
-spec find_datoms(
    aarondb@shared@state:db_state(),
    {aarondb@shared@ast:part(), binary(), aarondb@shared@ast:part()}
) -> list(aarondb@fact:datom()).
find_datoms(Db_state, Pattern) ->
    case aarondb@storage:query_datoms(erlang:element(2, Db_state), Pattern) of
        {ok, Datoms} when Datoms =/= [] ->
            Datoms;

        _ ->
            {E, A, V} = Pattern,
            case {E, A, V} of
                {{uid, Eid}, Attr, {val, Val}} ->
                    aarondb@index:get_datoms_by_entity_attr_val(
                        erlang:element(3, Db_state),
                        Eid,
                        Attr,
                        Val
                    );

                {{lookup, _}, _, {val, _}} ->
                    [];

                {{uid, Eid@1}, Attr@1, {var, _}} ->
                    aarondb@index:get_datoms_by_entity_attr(
                        erlang:element(3, Db_state),
                        Eid@1,
                        Attr@1
                    );

                {{var, _}, Attr@2, {val, Val@1}} ->
                    aarondb@index:get_datoms_by_val(
                        erlang:element(4, Db_state),
                        Attr@2,
                        Val@1
                    );

                {{var, _}, Attr@3, {var, _}} ->
                    aarondb@index:filter_by_attribute(
                        erlang:element(4, Db_state),
                        Attr@3
                    );

                {{uid, Eid@2}, _, _} ->
                    aarondb@index:filter_by_entity(
                        erlang:element(3, Db_state),
                        Eid@2
                    );

                {{var, _}, _, _} ->
                    aarondb@index:get_all_datoms(erlang:element(3, Db_state));

                {_, _, _} ->
                    []
            end
    end.
