-module(aarondb@command).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/command.gleam").
-export([new/0, apply/3, replay_hash/1, read/3, last_applied/1]).
-export_type([consistency/0, command/0, command_request/0, command_result/0, command_error/0, value/0, applied/0, state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " # command — deterministic replicated command-state-machine reference\n"
    "\n"
    " This module deliberately has no transport, leader election, or local DB\n"
    " integration. A future consensus runtime supplies the committed index; this\n"
    " module deterministically applies the same command on every member.\n"
).

-type consistency() :: local | lease_read | linearizable.

-type command() :: {put, binary(), binary()} |
    {compare_and_set, binary(), gleam@option:option(binary()), binary()} |
    {issue_fence, binary()}.

-type command_request() :: {command_request, binary(), command()}.

-type command_result() :: {written, binary(), binary()} |
    {cas_applied, binary(), gleam@option:option(binary()), binary()} |
    {cas_rejected, binary(), gleam@option:option(binary())} |
    {fence_issued, binary(), integer()}.

-type command_error() :: {idempotency_payload_mismatch, binary()} |
    {invalid_committed_index, integer(), integer()}.

-type value() :: {value, binary(), binary()}.

-type applied() :: {applied, binary(), binary(), command_result()}.

-type state() :: {state,
        list(value()),
        list({binary(), integer()}),
        list(applied()),
        integer()}.

-file("src/aarondb/command.gleam", 56).
-spec new() -> state().
new() ->
    {state, [], [], [], -1}.

-file("src/aarondb/command.gleam", 286).
-spec int_string(integer()) -> binary().
int_string(Value) ->
    gleam@string:inspect(Value).

-file("src/aarondb/command.gleam", 167).
-spec frame(binary()) -> binary().
frame(Value) ->
    <<<<(int_string(string:length(Value)))/binary, ":"/utf8>>/binary,
        Value/binary>>.

-file("src/aarondb/command.gleam", 171).
-spec option_fingerprint(gleam@option:option(binary())) -> binary().
option_fingerprint(Value) ->
    case Value of
        none ->
            <<"none"/utf8>>;

        {some, Content} ->
            <<"some:"/utf8, (frame(Content))/binary>>
    end.

-file("src/aarondb/command.gleam", 158).
-spec fingerprint(command()) -> binary().
fingerprint(Command) ->
    case Command of
        {put, Key, Value} ->
            <<<<"put:"/utf8, (frame(Key))/binary>>/binary,
                (frame(Value))/binary>>;

        {compare_and_set, Key@1, Expected, Replacement} ->
            <<<<<<"cas:"/utf8, (frame(Key@1))/binary>>/binary,
                    (option_fingerprint(Expected))/binary>>/binary,
                (frame(Replacement))/binary>>;

        {issue_fence, Resource} ->
            <<"fence:"/utf8, (frame(Resource))/binary>>
    end.

-file("src/aarondb/command.gleam", 226).
-spec put_fence(list({binary(), integer()}), binary(), integer()) -> list({binary(),
    integer()}).
put_fence(Fences, Resource, Token) ->
    case Fences of
        [] ->
            [{Resource, Token}];

        [{Saved_resource, Saved_token} | Rest] ->
            case Saved_resource =:= Resource of
                true ->
                    [{Resource, Token} | Rest];

                false ->
                    [{Saved_resource, Saved_token} |
                        put_fence(Rest, Resource, Token)]
            end
    end.

-file("src/aarondb/command.gleam", 215).
-spec fence_for(list({binary(), integer()}), binary()) -> integer().
fence_for(Fences, Resource) ->
    case Fences of
        [] ->
            0;

        [{Saved_resource, Token} | Rest] ->
            case Saved_resource =:= Resource of
                true ->
                    Token;

                false ->
                    fence_for(Rest, Resource)
            end
    end.

-file("src/aarondb/command.gleam", 189).
-spec put_value(list(value()), binary(), binary()) -> list(value()).
put_value(Values, Wanted, Replacement) ->
    case Values of
        [] ->
            [{value, Wanted, Replacement}];

        [{value, Key, Value} | Rest] ->
            case Key =:= Wanted of
                true ->
                    [{value, Wanted, Replacement} | Rest];

                false ->
                    [{value, Key, Value} | put_value(Rest, Wanted, Replacement)]
            end
    end.

-file("src/aarondb/command.gleam", 178).
-spec get_value(list(value()), binary()) -> gleam@option:option(binary()).
get_value(Values, Wanted) ->
    case Values of
        [] ->
            none;

        [{value, Key, Value} | Rest] ->
            case Key =:= Wanted of
                true ->
                    {some, Value};

                false ->
                    get_value(Rest, Wanted)
            end
    end.

-file("src/aarondb/command.gleam", 125).
-spec execute(command(), list(value()), list({binary(), integer()})) -> {list(value()),
    list({binary(), integer()}),
    command_result()}.
execute(Command, Values, Fences) ->
    case Command of
        {put, Key, Value} ->
            {put_value(Values, Key, Value), Fences, {written, Key, Value}};

        {compare_and_set, Key@1, Expected, Replacement} ->
            Actual = get_value(Values, Key@1),
            case Actual =:= Expected of
                true ->
                    {put_value(Values, Key@1, Replacement),
                        Fences,
                        {cas_applied, Key@1, Actual, Replacement}};

                false ->
                    {Values, Fences, {cas_rejected, Key@1, Actual}}
            end;

        {issue_fence, Resource} ->
            Token = fence_for(Fences, Resource) + 1,
            {Values,
                put_fence(Fences, Resource, Token),
                {fence_issued, Resource, Token}}
    end.

-file("src/aarondb/command.gleam", 106).
-spec apply_new(integer(), command_request(), state()) -> {ok,
        {state(), command_result()}} |
    {error, command_error()}.
apply_new(Index, Request, State) ->
    {Values, Fences, Result} = execute(
        erlang:element(3, Request),
        erlang:element(2, State),
        erlang:element(3, State)
    ),
    Updated = {state,
        Values,
        Fences,
        lists:append(
            erlang:element(4, State),
            [{applied,
                    erlang:element(2, Request),
                    fingerprint(erlang:element(3, Request)),
                    Result}]
        ),
        Index},
    {ok, {Updated, Result}}.

-file("src/aarondb/command.gleam", 204).
-spec find_applied(list(applied()), binary()) -> gleam@option:option(applied()).
find_applied(Applied, Key) ->
    case Applied of
        [] ->
            none;

        [{applied, Saved_key, Saved_fingerprint, Saved_result} | Rest] ->
            case Saved_key =:= Key of
                true ->
                    {some,
                        {applied, Saved_key, Saved_fingerprint, Saved_result}};

                false ->
                    find_applied(Rest, Key)
            end
    end.

-file("src/aarondb/command.gleam", 62).
?DOC(
    " The committed index must advance exactly once. Retried idempotency requests\n"
    " return their original result without applying another mutation.\n"
).
-spec apply(integer(), command_request(), state()) -> {ok,
        {state(), command_result()}} |
    {error, command_error()}.
apply(Index, Request, State) ->
    case find_applied(erlang:element(4, State), erlang:element(2, Request)) of
        {some, {applied, _, Saved_fingerprint, Result}} ->
            case Saved_fingerprint =:= fingerprint(erlang:element(3, Request)) of
                true ->
                    {ok, {State, Result}};

                false ->
                    {error,
                        {idempotency_payload_mismatch,
                            erlang:element(2, Request)}}
            end;

        none ->
            case Index =:= (erlang:element(5, State) + 1) of
                false ->
                    {error,
                        {invalid_committed_index,
                            Index,
                            erlang:element(5, State)}};

                true ->
                    apply_new(Index, Request, State)
            end
    end.

-file("src/aarondb/command.gleam", 271).
-spec result_fingerprint(command_result()) -> binary().
result_fingerprint(Result) ->
    case Result of
        {written, Key, Value} ->
            <<<<"written"/utf8, (frame(Key))/binary>>/binary,
                (frame(Value))/binary>>;

        {cas_applied, Key@1, Previous, Value@1} ->
            <<<<<<"cas-applied"/utf8, (frame(Key@1))/binary>>/binary,
                    (option_fingerprint(Previous))/binary>>/binary,
                (frame(Value@1))/binary>>;

        {cas_rejected, Key@2, Actual} ->
            <<<<"cas-rejected"/utf8, (frame(Key@2))/binary>>/binary,
                (option_fingerprint(Actual))/binary>>;

        {fence_issued, Resource, Token} ->
            <<<<"fence"/utf8, (frame(Resource))/binary>>/binary,
                (int_string(Token))/binary>>
    end.

-file("src/aarondb/command.gleam", 260).
-spec applied_fingerprint(list(applied())) -> binary().
applied_fingerprint(Applied) ->
    case Applied of
        [] ->
            <<""/utf8>>;

        [{applied, Key, Hash, Result} | Rest] ->
            <<<<<<(frame(Key))/binary, (frame(Hash))/binary>>/binary,
                    (result_fingerprint(Result))/binary>>/binary,
                (applied_fingerprint(Rest))/binary>>
    end.

-file("src/aarondb/command.gleam", 252).
-spec fences_fingerprint(list({binary(), integer()})) -> binary().
fences_fingerprint(Fences) ->
    case Fences of
        [] ->
            <<""/utf8>>;

        [{Resource, Token} | Rest] ->
            <<<<(frame(Resource))/binary, (int_string(Token))/binary>>/binary,
                (fences_fingerprint(Rest))/binary>>
    end.

-file("src/aarondb/command.gleam", 244).
-spec values_fingerprint(list(value())) -> binary().
values_fingerprint(Values) ->
    case Values of
        [] ->
            <<""/utf8>>;

        [{value, Key, Value} | Rest] ->
            <<<<(frame(Key))/binary, (frame(Value))/binary>>/binary,
                (values_fingerprint(Rest))/binary>>
    end.

-file("src/aarondb/command.gleam", 83).
?DOC(
    " The hash is intentionally constructed from closed, ordered data. It is an\n"
    " audit/replay fingerprint, not a cryptographic signature.\n"
).
-spec replay_hash(state()) -> binary().
replay_hash(State) ->
    <<<<<<<<<<<<<<"state|"/utf8, (int_string(erlang:element(5, State)))/binary>>/binary,
                            "|values|"/utf8>>/binary,
                        (values_fingerprint(erlang:element(2, State)))/binary>>/binary,
                    "|fences|"/utf8>>/binary,
                (fences_fingerprint(erlang:element(3, State)))/binary>>/binary,
            "|applied|"/utf8>>/binary,
        (applied_fingerprint(erlang:element(4, State)))/binary>>.

-file("src/aarondb/command.gleam", 94).
-spec read(state(), binary(), consistency()) -> {consistency(),
    gleam@option:option(binary())}.
read(State, Key, Mode) ->
    {Mode, get_value(erlang:element(2, State), Key)}.

-file("src/aarondb/command.gleam", 102).
-spec last_applied(state()) -> integer().
last_applied(State) ->
    erlang:element(5, State).
