-module(erlmcp_example_simple_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([start_stop/1, echo_tool/1, add_tool/1, read_resource/1, get_prompt/1]).

all() ->
    [start_stop, echo_tool, add_tool, read_resource, get_prompt].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"simple-test">>, version => <<"1.0">>
    }),
    simple_server:register_all(Srv),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"simple-test">>, version => <<"1.0">>
    }),
    initialize(Session),
    [{server, Session}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

start_stop(Config) ->
    ?assert(is_process_alive(?config(server, Config))),
    _ = Config.

echo_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{<<"text">> => <<"hello">>}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"hello">>, maps:get(<<"text">>, Content)).

add_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(3, <<"tools/call">>, #{
        <<"name">> => <<"add">>,
        <<"arguments">> => #{<<"a">> => 3, <<"b">> => 4}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"7">>, maps:get(<<"text">>, Content)).

read_resource(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(4, <<"resources/read">>, #{
        <<"uri">> => <<"file://example.txt">>
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"contents">>, Result),
    ?assertEqual(<<"Hello from erlmcp!">>, maps:get(<<"text">>, Content)).

get_prompt(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(5, <<"prompts/get">>, #{
        <<"name">> => <<"greet">>,
        <<"arguments">> => #{<<"name">> => <<"World">>}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Msg] = maps:get(<<"messages">>, Result),
    ?assertEqual(<<"user">>, maps:get(<<"role">>, Msg)).

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

decode(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.
