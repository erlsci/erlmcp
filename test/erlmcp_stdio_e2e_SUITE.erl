-module(erlmcp_stdio_e2e_SUITE).

%% P6M2-8: End-to-end over stdio transport:
%% initialize → ping → tools/list → tools/call → cancel

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([e2e_stdio_scenario/1]).

all() -> [e2e_stdio_scenario].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"e2e-test">>, version => <<"1.0">>,
        tools => [
            #{name => <<"echo">>, description => <<"Echo">>,
              input_schema => erlmcp_schema:object([
                  erlmcp_schema:field(<<"msg">>, erlmcp_schema:string(), [required])
              ]),
              handler => fun(#{<<"msg">> := Msg}, _) ->
                  {ok, [#{<<"type">> => <<"text">>, <<"text">> => Msg}]}
              end},
            #{name => <<"block">>, description => <<"Blocks forever">>,
              input_schema => erlmcp_schema:object([]),
              handler => fun(_, _) -> receive after infinity -> ok end end}
        ]
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{
        server => Srv, responder => R,
        name => <<"e2e-test">>, version => <<"1.0">>
    }),
    [{session, S}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(session, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

e2e_stdio_scenario(Config) ->
    S = ?config(session, Config),

    %% 1. Initialize
    send(S, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    InitResp = receive_json(),
    ?assertMatch(#{<<"result">> := #{<<"protocolVersion">> := _}}, InitResp),

    %% 2. Ping
    send(S, 2, <<"ping">>, #{}),
    PingResp = receive_json(),
    ?assertEqual(2, maps:get(<<"id">>, PingResp)),
    ?assertMatch(#{<<"result">> := #{}}, PingResp),

    %% 3. tools/list
    send(S, 3, <<"tools/list">>, #{}),
    ListResp = receive_json(),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, ListResp)),
    ?assertEqual(2, length(Tools)),

    %% 4. tools/call
    send(S, 4, <<"tools/call">>, #{
        <<"name">> => <<"echo">>, <<"arguments">> => #{<<"msg">> => <<"hi">>}}),
    CallResp = receive_json(),
    [Content] = maps:get(<<"content">>, maps:get(<<"result">>, CallResp)),
    ?assertEqual(<<"hi">>, maps:get(<<"text">>, Content)),

    %% 5. Cancel an in-flight request
    send(S, 5, <<"tools/call">>, #{
        <<"name">> => <<"block">>, <<"arguments">> => #{}}),
    timer:sleep(50),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 5}),
    erlmcp_server_session:send_message(S, CancelNotif),
    timer:sleep(100),
    ok.

send(S, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(S, Req).

receive_json() ->
    receive {send, Json} -> {ok, D} = erlmcp_codec:decode(Json), D
    after 2000 -> error(timeout) end.
