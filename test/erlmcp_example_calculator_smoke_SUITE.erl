-module(erlmcp_example_calculator_smoke_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([start_stop/1, add_tool/1, divide_by_zero/1,
         directory_tool/1, task_tool/1]).

all() ->
    [start_stop, add_tool, divide_by_zero, directory_tool, task_tool].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"calc-smoke">>,
        version => <<"1.0">>,
        handler => calculator_server
    }),
    ok = erlmcp:add_tool(Srv, erlmcp:make_directory_tool()),
    ok = erlmcp:add_tool(Srv, calculator_server:slow_tool_spec()),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"calc-smoke">>, version => <<"1.0">>
    }),
    _ = drain_notifications(),
    initialize(Session),
    [{server, Session}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

start_stop(Config) ->
    ?assert(is_process_alive(?config(server, Config))),
    _ = Config.

add_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"add">>,
        <<"arguments">> => #{<<"a">> => 10, <<"b">> => 20}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    Structured = maps:get(<<"structuredContent">>, Result),
    ?assertEqual(30, maps:get(<<"result">>, Structured)).

divide_by_zero(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(3, <<"tools/call">>, #{
        <<"name">> => <<"divide">>,
        <<"arguments">> => #{<<"a">> => 1, <<"b">> => 0}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    ?assert(maps:is_key(<<"error">>, Resp)).

directory_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(4, <<"tools/call">>, #{
        <<"name">> => <<"directory">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"text">>, maps:get(<<"type">>, Content)).

task_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(5, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"steps">> => 2}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assert(binary:match(maps:get(<<"text">>, Content), <<"Completed">>) =/= nomatch).

%%====================================================================
%% Helpers
%%====================================================================

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

drain_notifications() ->
    receive {send, _} -> drain_notifications()
    after 100 -> ok
    end.

decode(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.
