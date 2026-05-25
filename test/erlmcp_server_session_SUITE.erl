-module(erlmcp_server_session_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    shared_catalog_two_sessions/1,
    late_registration_visible/1,
    per_request_reply_target/1,
    push_channel_notification/1
]).

all() ->
    [shared_catalog_two_sessions,
     late_registration_visible,
     per_request_reply_target,
     push_channel_notification].

init_per_testcase(_TC, Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"ct-server">>, version => <<"1.0">>,
        tools => [#{name => <<"echo">>, description => <<"echo tool">>,
                    handler => fun(Args, _Ctx) ->
                        {ok, [#{<<"type">> => <<"text">>,
                                <<"text">> => maps:get(<<"input">>, Args, <<>>)}]}
                    end}]
    }),
    [{server, Server} | Config].

end_per_testcase(_TC, Config) ->
    Server = ?config(server, Config),
    gen_server:stop(Server),
    ok.

%% P6M1-2: Two sessions of one server share one catalog
shared_catalog_two_sessions(Config) ->
    Server = ?config(server, Config),
    R1 = erlmcp_reply:new_device(self()),
    R2 = erlmcp_reply:new_device(self()),
    {ok, S1} = erlmcp_server_session:start_link(#{server => Server, responder => R1}),
    {ok, S2} = erlmcp_server_session:start_link(#{server => Server, responder => R2}),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S1, InitMsg),
    ok = erlmcp_server_session:send_message(S2, InitMsg),
    timer:sleep(50),
    flush(),
    ListMsg = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S1, ListMsg),
    R1Tools = receive_response(),
    ok = erlmcp_server_session:send_message(S2, ListMsg),
    R2Tools = receive_response(),
    ?assertMatch(#{<<"tools">> := [_|_]}, R1Tools),
    ?assertEqual(R1Tools, R2Tools),
    gen_statem:stop(S1),
    gen_statem:stop(S2).

%% P6M1-2: Registering after a session exists is visible to it
late_registration_visible(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    _ = receive_response(),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"late_tool">>, description => <<"added late">>,
        handler => fun(_, _) -> {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"hi">>}]} end
    }),
    timer:sleep(50),
    flush(),
    ListMsg = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, ListMsg),
    Result = receive_response(),
    Tools = maps:get(<<"tools">>, Result),
    Names = [maps:get(<<"name">>, T) || T <- Tools],
    ?assert(lists:member(<<"late_tool">>, Names)),
    gen_statem:stop(S).

%% P6M1-5: Two requests with distinct responders get their own response
per_request_reply_target(Config) ->
    Server = ?config(server, Config),
    Parent = self(),
    Recv1 = spawn_link(fun() -> collector(Parent, r1) end),
    Recv2 = spawn_link(fun() -> collector(Parent, r2) end),
    R1 = erlmcp_reply:new_device(Recv1),
    R2 = erlmcp_reply:new_device(Recv2),
    PushR = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => PushR}),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    timer:sleep(50),
    flush(),
    Req1 = erlmcp_json_rpc:encode_request(10, <<"tools/list">>, #{}),
    Req2 = erlmcp_json_rpc:encode_request(11, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req1, R1),
    ok = erlmcp_server_session:send_message(S, Req2, R2),
    timer:sleep(100),
    Got1 = receive {collected, r1, D1} -> D1 after 2000 -> error end,
    Got2 = receive {collected, r2, D2} -> D2 after 2000 -> error end,
    ?assertNotEqual(error, Got1),
    ?assertNotEqual(error, Got2),
    {ok, Decoded1} = erlmcp_codec:decode(Got1),
    {ok, Decoded2} = erlmcp_codec:decode(Got2),
    ?assertEqual(10, maps:get(<<"id">>, Decoded1)),
    ?assertEqual(11, maps:get(<<"id">>, Decoded2)),
    gen_statem:stop(S).

%% P6M1-5: Server-initiated notification goes to push channel
push_channel_notification(Config) ->
    Server = ?config(server, Config),
    PushRecv = spawn_link(fun() -> collector(self(), push) end),
    PushR = erlmcp_reply:new_device(PushRecv),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => PushR}),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    timer:sleep(50),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"trigger">>, description => <<"triggers notification">>,
        handler => fun(_, _) -> {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"x">>}]} end
    }),
    timer:sleep(100),
    PushRecv ! {get, self()},
    Messages = receive {messages, M} -> M after 1000 -> [] end,
    HasListChanged = lists:any(fun(Bin) ->
        case erlmcp_codec:decode(Bin) of
            {ok, #{<<"method">> := <<"notifications/tools/list_changed">>}} -> true;
            _ -> false
        end
    end, Messages),
    ?assert(HasListChanged),
    gen_statem:stop(S).

%%====================================================================
%% Helpers
%%====================================================================

receive_response() ->
    receive
        {send, Json} ->
            {ok, Decoded} = erlmcp_codec:decode(Json),
            maps:get(<<"result">>, Decoded, Decoded)
    after 2000 ->
        error(timeout)
    end.

flush() ->
    receive _ -> flush() after 0 -> ok end.

collector(Parent, Tag) ->
    collector_loop(Parent, Tag, []).

collector_loop(Parent, Tag, Acc) ->
    receive
        {send, Data} ->
            Parent ! {collected, Tag, Data},
            collector_loop(Parent, Tag, [Data | Acc]);
        {get, From} ->
            From ! {messages, lists:reverse(Acc)},
            collector_loop(Parent, Tag, Acc)
    after 5000 ->
        ok
    end.
