-module(erlmcp_example_weather_smoke_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([start_stop/1, get_weather_tool/1, read_resource/1,
         read_template/1, get_prompt/1]).

all() ->
    [start_stop, get_weather_tool, read_resource, read_template, get_prompt].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"weather-smoke">>, version => <<"1.0">>
    }),
    weather_server:register_all(Srv),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"weather-smoke">>, version => <<"1.0">>
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

get_weather_tool(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"get_weather">>,
        <<"arguments">> => #{<<"city">> => <<"london">>}
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assert(is_binary(maps:get(<<"text">>, Content))).

read_resource(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(3, <<"resources/read">>, #{
        <<"uri">> => <<"weather://current/london">>
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    ?assert(is_list(maps:get(<<"contents">>, Result))).

read_template(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(4, <<"resources/read">>, #{
        <<"uri">> => <<"weather://current/paris">>
    }),
    erlmcp_server_session:send_message(Server, Req),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"contents">>, Result),
    ?assert(binary:match(maps:get(<<"text">>, Content), <<"paris">>) =/= nomatch).

get_prompt(Config) ->
    Server = ?config(server, Config),
    Req = erlmcp_json_rpc:encode_request(5, <<"prompts/get">>, #{
        <<"name">> => <<"weather_report">>,
        <<"arguments">> => #{<<"city">> => <<"tokyo">>}
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
