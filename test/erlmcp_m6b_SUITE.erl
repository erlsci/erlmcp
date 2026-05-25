-module(erlmcp_m6b_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    meta_passthrough/1,
    icons_in_tools_list/1,
    batch_mixed/1,
    batch_all_notifications/1,
    batch_malformed_member/1,
    batch_response_routes_to_out_pending/1
]).

all() ->
    [meta_passthrough, icons_in_tools_list,
     batch_mixed, batch_all_notifications, batch_malformed_member,
     batch_response_routes_to_out_pending].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"m6b-test">>, version => <<"1.0">>,
        tools => [#{
            name => <<"echo_meta">>,
            description => <<"Echoes request _meta">>,
            input_schema => erlmcp_schema:object([]),
            icons => [#{<<"type">> => <<"url">>, <<"url">> => <<"https://example.com/icon.png">>}],
            handler => fun(_Args, Ctx) ->
                ReqMeta = erlmcp_ctx:meta(Ctx),
                {ok, erlmcp:text(<<"got meta">>), #{<<"echo">> => true},
                     ReqMeta}
            end
        }]
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"m6b-test">>, version => <<"1.0">>
    }),
    initialize(Session),
    [{server, Session}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

initialize(Server) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_send(),
    ok.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(timeout) end.

decode(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.

%%====================================================================
%% M6b-1: _meta passthrough
%%====================================================================

meta_passthrough(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"echo_meta">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"custom_key">> => <<"custom_value">>}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    ?assert(maps:is_key(<<"content">>, Result)),
    ResponseMeta = maps:get(<<"_meta">>, Result, #{}),
    ?assertEqual(<<"custom_value">>, maps:get(<<"custom_key">>, ResponseMeta, undefined)).

%%====================================================================
%% M6b-2: icons in tools/list
%%====================================================================

icons_in_tools_list(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    Tool = hd([T || T <- Tools, maps:get(<<"name">>, T) =:= <<"echo_meta">>]),
    Icons = maps:get(<<"icons">>, Tool),
    ?assertEqual(1, length(Icons)),
    [Icon] = Icons,
    ?assertEqual(<<"url">>, maps:get(<<"type">>, Icon)).

%%====================================================================
%% M6b-3: batch execution
%%====================================================================

batch_mixed(Config) ->
    Server = ?config(server, Config),
    Batch = jsx:encode([
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 10,
          <<"method">> => <<"ping">>},
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 11,
          <<"method">> => <<"tools/list">>},
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"method">> => <<"notifications/initialized">>}
    ]),
    erlmcp_server_session:send_message(Server, Batch),
    RespBatch = decode(wait_send()),
    ?assert(is_list(RespBatch)),
    ?assertEqual(2, length(RespBatch)),
    Ids = [maps:get(<<"id">>, R) || R <- RespBatch],
    ?assert(lists:member(10, Ids)),
    ?assert(lists:member(11, Ids)).

batch_all_notifications(Config) ->
    Server = ?config(server, Config),
    Batch = jsx:encode([
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"method">> => <<"notifications/initialized">>}
    ]),
    erlmcp_server_session:send_message(Server, Batch),
    receive {send, _} -> ct:fail(should_not_respond)
    after 200 -> ok
    end.

batch_malformed_member(Config) ->
    Server = ?config(server, Config),
    Batch = jsx:encode([
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 20,
          <<"method">> => <<"ping">>},
        #{<<"not_jsonrpc">> => true}
    ]),
    erlmcp_server_session:send_message(Server, Batch),
    RespBatch = decode(wait_send()),
    ?assert(is_list(RespBatch)),
    ?assert(length(RespBatch) >= 1),
    ?assert(is_process_alive(?config(server, Config))).

%%====================================================================
%% F-09 regression: batched response routes through out_pending
%%====================================================================

batch_response_routes_to_out_pending(Config) ->
    Server = ?config(server, Config),
    Srv = ?config(srv, Config),
    TestPid = self(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"peer_call">>,
        description => <<"Calls request_peer and returns the result">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_Args, Ctx) ->
            Result = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                         #{<<"messages">> => []}),
            TestPid ! {peer_result, Result},
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    _ = wait_send(),
    ToolReq = erlmcp_json_rpc:encode_request(50, <<"tools/call">>, #{
        <<"name">> => <<"peer_call">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, ToolReq),
    OutboundReq = decode(wait_send()),
    OutId = maps:get(<<"id">>, OutboundReq),
    PeerResult = #{<<"role">> => <<"assistant">>,
                   <<"content">> => #{<<"type">> => <<"text">>,
                                      <<"text">> => <<"hello">>}},
    BatchWithResponse = jsx:encode([
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => OutId,
          <<"result">> => PeerResult},
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 99,
          <<"method">> => <<"ping">>}
    ]),
    erlmcp_server_session:send_message(Server, BatchWithResponse),
    PingResp = decode(wait_send()),
    ?assert(is_list(PingResp)),
    ?assertEqual(1, length(PingResp)),
    receive
        {peer_result, {ok, ReceivedResult}} ->
            ?assertEqual(PeerResult, ReceivedResult)
    after 5000 ->
        ct:fail(peer_result_not_received)
    end,
    _ToolResp = wait_send(),
    ?assert(is_process_alive(Server)).
