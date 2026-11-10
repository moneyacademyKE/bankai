-module(bankai_wire_ffi).
-export([partial_line/0, completed_line/0]).

%% bk-4d82 fixtures.
%%
%% recv_full_response accumulates gen_tcp {packet, line} chunks; a reply
%% longer than the recv buffer arrives as several partial lines, and the
%% buffer boundary can split a multi-byte UTF-8 codepoint. The real crash
%% (2026-11-10, `bankai list`): a multi-KB response whose boundary fell
%% inside an em-dash left the accumulated line ending in the truncated lead
%% pair <<226,128>>, and string:trim/1's backward scan (string.erl
%% bin_search_inv_n) raised badarg — killing the whole `list` verb.
%%
%% The prefix must be multi-byte-rich and ~KB-sized: trim's short-binary
%% path tolerates trailing truncation, the long multibyte path does not
%% (probed 2026-11-10: 1322-byte multibyte prefix + <<226,128>> -> crash).

partial_line() ->
    <<(prefix())/binary, 226, 128>>.

completed_line() ->
    <<"{\"result\":\"", (prefix())/binary, 226, 128, 148,
      "\", \"id\":1}">>.

prefix() ->
    %% NOTE: em-dash as explicit bytes — a codepoint >255 inside a plain
    %% binary literal is truncated to its low 8 bits (0x2014 -> 0x14, a
    %% JSON-illegal control char), so <<"...—...">> silently corrupts.
    Seg = <<"bk-6285 ", 16#E2, 16#80, 16#94,
            " delete the dead module; claim the bead; gates as filed; ">>,
    binary:copy(Seg, 20).
