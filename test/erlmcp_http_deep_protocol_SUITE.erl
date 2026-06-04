-module(erlmcp_http_deep_protocol_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([progress_over_sse/1,
         sampling_round_trip/1,
         fanout_post_without_sse_stream/1,
         session_survives_dropped_sse/1,
         idle_gc_terminates_session/1,
         get_sse_unknown_session/1,
         get_sse_with_last_event_id/1,
         get_sse_session_death/1]).

all() ->
    [progress_over_sse,
     sampling_round_trip,
     fanout_post_without_sse_stream,
     session_survives_dropped_sse,
     idle_gc_terminates_session,
     get_sse_unknown_session,
     get_sse_with_last_event_id,
     get_sse_session_death].

init_per_suite(Config) ->
    application:ensure_all_started(cowboy),
    application:ensure_all_started(gun),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(idle_gc_terminates_session, Config) ->
    EchoTool = make_echo_tool(),
    start_server(Config, #{tools => [EchoTool], idle_timeout => 500});
init_per_testcase(_TestCase, Config) ->
    SlowTool = #{
        name => <<"slow_compute">>,
        description => <<"Emits progress then completes">>,
        handler => fun(Args, Ctx) ->
            Steps = maps:get(<<"steps">>, Args, 3),
            lists:foreach(fun(I) ->
                Frac = I / Steps,
                Msg = iolist_to_binary(
                    io_lib:format("Step ~p/~p", [I, Steps])),
                erlmcp_ctx:report_progress(Ctx, Frac, Msg),
                timer:sleep(50)
            end, lists:seq(1, Steps)),
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"done">>}]}
        end
    },
    SamplingTool = #{
        name => <<"ask_peer">>,
        description => <<"Sends a sampling/createMessage to the client">>,
        handler => fun(_Args, Ctx) ->
            Params = #{
                <<"messages">> => [
                    #{<<"role">> => <<"user">>,
                      <<"content">> => #{<<"type">> => <<"text">>,
                                         <<"text">> => <<"What is 2+2?">>}}
                ],
                <<"maxTokens">> => 100
            },
            case erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>, Params) of
                {ok, Result} ->
                    Content = maps:get(<<"content">>, Result, #{}),
                    Text = maps:get(<<"text">>, Content, <<"(no response)">>),
                    {ok, [#{<<"type">> => <<"text">>, <<"text">> => Text}]};
                {error, Reason} ->
                    Msg = iolist_to_binary(io_lib:format("~p", [Reason])),
                    {error, -32603, <<"Sampling failed: ", Msg/binary>>}
            end
        end
    },
    EchoTool = make_echo_tool(),
    start_server(Config, #{tools => [SlowTool, SamplingTool, EchoTool]}).

end_per_testcase(_TestCase, Config) ->
    Sup = proplists:get_value(sup, Config),
    Mgr = proplists:get_value(mgr, Config),
    case is_pid(Mgr) andalso is_process_alive(Mgr) of
        true ->
            case erlmcp_http_session_mgr:listener_ref(Mgr) of
                undefined -> ok;
                Ref -> cowboy:stop_listener(Ref)
            end;
        false -> ok
    end,
    case is_pid(Sup) andalso is_process_alive(Sup) of
        true ->
            unlink(Sup),
            exit(Sup, shutdown),
            timer:sleep(50);
        false -> ok
    end,
    ok.

%%====================================================================
%% Tests
%%====================================================================

progress_over_sse(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _SseHeaders} = gun:await(SseConn, SseRef, 5000),

    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"steps">> => 3},
        <<"_meta">> => #{<<"progressToken">> => <<"tok1">>}
    }),
    {200, _, CallBody} = post_json(Port, SessionId, CallReq),
    CallResult = decode_result(CallBody),
    [Content] = maps:get(<<"content">>, CallResult),
    ?assertEqual(<<"done">>, maps:get(<<"text">>, Content)),

    ProgressEvents = collect_sse_events(SseConn, SseRef, 2000),
    ?assert(length(ProgressEvents) >= 1),
    gun:close(SseConn).

sampling_round_trip(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    %% 1. Open a GET SSE stream for server→client push traffic
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),

    %% 2. POST tools/call for the sampling tool (async — it will block
    %%    waiting for the peer response)
    Parent = self(),
    CallerId = spawn_link(fun() ->
        CallReq = erlmcp_json_rpc:encode_request(10, <<"tools/call">>, #{
            <<"name">> => <<"ask_peer">>,
            <<"arguments">> => #{}
        }),
        Result = post_json(Port, SessionId, CallReq),
        Parent ! {tool_result, Result}
    end),

    %% 3. On the GET SSE stream, receive the sampling/createMessage request
    SamplingReq = receive_sse_json(SseConn, SseRef, 5000),
    ?assertEqual(<<"sampling/createMessage">>, maps:get(<<"method">>, SamplingReq)),
    PeerReqId = maps:get(<<"id">>, SamplingReq),
    ?assert(is_integer(PeerReqId)),

    %% 4. POST back the sampling response correlated by id
    PeerResp = erlmcp_json_rpc:encode_response(PeerReqId, #{
        <<"role">> => <<"assistant">>,
        <<"model">> => <<"test-model">>,
        <<"content">> => #{<<"type">> => <<"text">>,
                           <<"text">> => <<"The answer is 4">>}
    }),
    {202, _, _} = post_json(Port, SessionId, PeerResp),

    %% Wait — the response is a JSON-RPC response (has "id" but also "result"),
    %% not a notification. The is_notification check will see the "id" field and
    %% treat it as a request, entering the cowboy_loop. But it's actually a
    %% response to the session's outbound request. The session handles it via
    %% handle_operational_message({response, Id, Result}, ...).
    %% We need to send it as a message with an id field — but the session's
    %% decode_and_classify_any will classify it as a response.

    %% 5. Assert the originating tools/call response arrives
    receive
        {tool_result, {200, _, Body}} ->
            ToolResult = decode_result(Body),
            [Content] = maps:get(<<"content">>, ToolResult),
            ?assertEqual(<<"The answer is 4">>, maps:get(<<"text">>, Content))
    after 10000 ->
        exit(CallerId, kill),
        ct:fail(sampling_round_trip_timeout)
    end,

    gun:close(SseConn).

fanout_post_without_sse_stream(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    %% POST a sampling tool call WITHOUT an open GET SSE stream.
    %% The push relay has no target, so the sampling/createMessage
    %% request from the session is dropped. The tool handler's
    %% request_peer call times out cleanly.
    Parent = self(),
    spawn_link(fun() ->
        CallReq = erlmcp_json_rpc:encode_request(10, <<"tools/call">>, #{
            <<"name">> => <<"ask_peer">>,
            <<"arguments">> => #{}
        }),
        Result = post_json_long(Port, SessionId, CallReq),
        Parent ! {fanout_result, Result}
    end),

    receive
        {fanout_result, {200, _, Body}} ->
            {ok, Decoded} = erlmcp_codec:decode(Body),
            case maps:find(<<"error">>, Decoded) of
                {ok, ErrObj} ->
                    ?assertMatch(#{<<"message">> := _}, ErrObj);
                error ->
                    ct:fail({expected_error_response, Decoded})
            end
    after 35000 ->
        ct:fail(fanout_timeout)
    end.

session_survives_dropped_sse(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),

    gun:close(SseConn),
    timer:sleep(100),

    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {200, _, PingBody} = post_json(Port, SessionId, PingReq),
    PingResult = decode_result(PingBody),
    ?assertEqual(#{}, PingResult).

idle_gc_terminates_session(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {200, _, _} = post_json(Port, SessionId, PingReq),

    timer:sleep(1000),

    PingReq2 = erlmcp_json_rpc:encode_request(3, <<"ping">>, #{}),
    {404, _, _} = post_json(Port, SessionId, PingReq2).

get_sse_session_death(Config) ->
    Port = proplists:get_value(port, Config),
    Mgr = proplists:get_value(mgr, Config),
    SessionId = initialize_session(Port),
    {ok, SessionPid} = erlmcp_http_session_mgr:lookup(Mgr, SessionId),

    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),
    timer:sleep(50),

    exit(SessionPid, kill),
    timer:sleep(200),
    gun:close(SseConn).

get_sse_unknown_session(Config) ->
    Port = proplists:get_value(port, Config),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:get(ConnPid, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, <<"nonexistent_session">>}
    ]),
    {response, nofin, 404, _} = gun:await(ConnPid, StreamRef, 5000),
    gun:close(ConnPid).

get_sse_with_last_event_id(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId},
        {<<"last-event-id">>, <<"5">>}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),

    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"steps">> => 1},
        <<"_meta">> => #{<<"progressToken">> => <<"tok2">>}
    }),
    {200, _, _} = post_json(Port, SessionId, CallReq),

    Events = collect_sse_events(SseConn, SseRef, 1000),
    ?assert(length(Events) >= 1),
    gun:close(SseConn).

%%====================================================================
%% Helpers
%%====================================================================

start_server(Config, ExtraConfig) ->
    ServerConfig = maps:merge(#{
        name => <<"test_deep">>,
        version => <<"0.1.0">>,
        port => 0
    }, ExtraConfig),
    {ok, Sup} = erlmcp_http_sup:start_link(ServerConfig),
    Children = supervisor:which_children(Sup),
    {session_mgr, MgrPid, _, _} = lists:keyfind(session_mgr, 1, Children),
    {ok, Port} = erlmcp_http_session_mgr:get_port(MgrPid),
    [{sup, Sup}, {port, Port}, {mgr, MgrPid} | Config].

initialize_session(Port) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    {200, Headers, _} = post_json(Port, undefined, InitReq),
    SessionId = proplists:get_value(<<"mcp-session-id">>, Headers),
    InitedNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/initialized">>, #{}),
    {202, _, _} = post_json(Port, SessionId, InitedNotif),
    SessionId.

post_json(Port, SessionId, Body) ->
    do_post_json(Port, SessionId, Body, 5000).

post_json_long(Port, SessionId, Body) ->
    do_post_json(Port, SessionId, Body, 35000).

do_post_json(Port, SessionId, Body, Timeout) ->
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    Headers0 = [{<<"content-type">>, <<"application/json">>}],
    Headers = case SessionId of
        undefined -> Headers0;
        _ -> [{<<"mcp-session-id">>, SessionId} | Headers0]
    end,
    StreamRef = gun:post(ConnPid, "/mcp", Headers, Body),
    case gun:await(ConnPid, StreamRef, Timeout) of
        {response, fin, Status, RespHeaders} ->
            gun:close(ConnPid),
            {Status, RespHeaders, <<>>};
        {response, nofin, Status, RespHeaders} ->
            {ok, RespBody} = gun:await_body(ConnPid, StreamRef, Timeout),
            gun:close(ConnPid),
            {Status, RespHeaders, RespBody}
    end.

decode_result(Body) ->
    {ok, Decoded} = erlmcp_codec:decode(Body),
    maps:get(<<"result">>, Decoded).

collect_sse_events(ConnPid, StreamRef, Timeout) ->
    collect_sse_events(ConnPid, StreamRef, Timeout, []).

collect_sse_events(ConnPid, StreamRef, Timeout, Acc) ->
    case gun:await(ConnPid, StreamRef, Timeout) of
        {data, nofin, Data} ->
            collect_sse_events(ConnPid, StreamRef, 500, [Data | Acc]);
        {data, fin, Data} ->
            lists:reverse([Data | Acc]);
        _ ->
            lists:reverse(Acc)
    end.

receive_sse_json(ConnPid, StreamRef, Timeout) ->
    Events = collect_sse_events(ConnPid, StreamRef, Timeout),
    parse_first_sse_json(Events).

parse_first_sse_json([]) ->
    ct:fail(no_sse_events_received);
parse_first_sse_json([Event | Rest]) ->
    case parse_sse_data(Event) of
        {ok, Json} -> Json;
        skip -> parse_first_sse_json(Rest)
    end.

parse_sse_data(EventBin) ->
    Lines = binary:split(EventBin, <<"\n">>, [global]),
    DataLines = [D || <<"data: ", D/binary>> <- Lines],
    case DataLines of
        [] -> skip;
        _ ->
            Combined = iolist_to_binary(lists:join(<<"\n">>, DataLines)),
            case erlmcp_codec:decode(Combined) of
                {ok, Map} -> {ok, Map};
                _ -> skip
            end
    end.

make_echo_tool() ->
    #{name => <<"echo">>,
      description => <<"Echoes input">>,
      handler => fun(Args, _Ctx) ->
          Text = maps:get(<<"text">>, Args, <<"no input">>),
          {ok, [#{<<"type">> => <<"text">>, <<"text">> => Text}]}
      end}.
