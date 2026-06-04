-module(erlmcp_http_sse_tests).

-include_lib("eunit/include/eunit.hrl").

new_buffer_default_test() ->
    Buf = erlmcp_http_sse:new_buffer(),
    ?assertEqual(0, erlmcp_http_sse:next_id(Buf)),
    ?assertEqual(0, erlmcp_http_sse:size(Buf)).

new_buffer_custom_size_test() ->
    Buf = erlmcp_http_sse:new_buffer(10),
    ?assertEqual(0, erlmcp_http_sse:next_id(Buf)),
    ?assertEqual(0, erlmcp_http_sse:size(Buf)).

format_event_test() ->
    Formatted = erlmcp_http_sse:format_event(42, <<"hello">>),
    Bin = iolist_to_binary(Formatted),
    ?assertEqual(<<"id: 42\ndata: hello\n\n">>, Bin).

push_event_assigns_monotonic_ids_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(),
    {0, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    {1, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    {2, _, _Buf3} = erlmcp_http_sse:push_event(Buf2, <<"c">>),
    ok.

push_event_returns_formatted_sse_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(),
    {0, Formatted, _} = erlmcp_http_sse:push_event(Buf0, <<"data">>),
    ?assertEqual(<<"id: 0\ndata: data\n\n">>, iolist_to_binary(Formatted)).

push_event_increments_size_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(),
    {_, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    ?assertEqual(1, erlmcp_http_sse:size(Buf1)),
    {_, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    ?assertEqual(2, erlmcp_http_sse:size(Buf2)).

buffer_eviction_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(3),
    {0, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    {1, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    {2, _, Buf3} = erlmcp_http_sse:push_event(Buf2, <<"c">>),
    ?assertEqual(3, erlmcp_http_sse:size(Buf3)),
    {3, _, Buf4} = erlmcp_http_sse:push_event(Buf3, <<"d">>),
    ?assertEqual(3, erlmcp_http_sse:size(Buf4)),
    Replayed = erlmcp_http_sse:replay_from(Buf4, 0),
    ?assertEqual(3, length(Replayed)),
    [E1 | _] = Replayed,
    ?assertMatch(<<"id: 1", _/binary>>, iolist_to_binary(E1)).

replay_from_mid_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(),
    {0, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    {1, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    {2, _, Buf3} = erlmcp_http_sse:push_event(Buf2, <<"c">>),
    {3, _, Buf4} = erlmcp_http_sse:push_event(Buf3, <<"d">>),
    {4, _, Buf5} = erlmcp_http_sse:push_event(Buf4, <<"e">>),
    Replayed = erlmcp_http_sse:replay_from(Buf5, 2),
    ?assertEqual(2, length(Replayed)),
    [R1, R2] = Replayed,
    ?assertMatch(<<"id: 3", _/binary>>, iolist_to_binary(R1)),
    ?assertMatch(<<"id: 4", _/binary>>, iolist_to_binary(R2)).

replay_from_stale_id_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(3),
    {_, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    {_, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    {_, _, Buf3} = erlmcp_http_sse:push_event(Buf2, <<"c">>),
    {_, _, Buf4} = erlmcp_http_sse:push_event(Buf3, <<"d">>),
    {_, _, Buf5} = erlmcp_http_sse:push_event(Buf4, <<"e">>),
    Replayed = erlmcp_http_sse:replay_from(Buf5, 0),
    ?assertEqual(3, length(Replayed)).

replay_from_future_id_test() ->
    Buf0 = erlmcp_http_sse:new_buffer(),
    {_, _, Buf1} = erlmcp_http_sse:push_event(Buf0, <<"a">>),
    {_, _, Buf2} = erlmcp_http_sse:push_event(Buf1, <<"b">>),
    Replayed = erlmcp_http_sse:replay_from(Buf2, 999),
    ?assertEqual([], Replayed).

replay_from_empty_buffer_test() ->
    Buf = erlmcp_http_sse:new_buffer(),
    Replayed = erlmcp_http_sse:replay_from(Buf, 0),
    ?assertEqual([], Replayed).
