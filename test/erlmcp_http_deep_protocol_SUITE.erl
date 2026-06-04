-module(erlmcp_http_deep_protocol_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([progress_over_sse/1,
         session_survives_dropped_sse/1,
         idle_gc_terminates_session/1,
         get_sse_unknown_session/1,
         get_sse_with_last_event_id/1,
         get_sse_session_death/1]).

all() ->
    [progress_over_sse,
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
    EchoTool = make_echo_tool(),
    start_server(Config, #{tools => [SlowTool, EchoTool]}).

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

    %% Open a GET SSE stream for push-channel traffic
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _SseHeaders} = gun:await(SseConn, SseRef, 5000),

    %% POST a slow_compute call with a progress token
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"steps">> => 3},
        <<"_meta">> => #{<<"progressToken">> => <<"tok1">>}
    }),
    {200, _, CallBody} = post_json(Port, SessionId, CallReq),
    CallResult = decode_result(CallBody),
    [Content] = maps:get(<<"content">>, CallResult),
    ?assertEqual(<<"done">>, maps:get(<<"text">>, Content)),

    %% Collect SSE events — progress notifications should have arrived
    ProgressEvents = collect_sse_events(SseConn, SseRef, 2000),
    ?assert(length(ProgressEvents) >= 1),

    gun:close(SseConn).

session_survives_dropped_sse(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    %% Open SSE stream
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),

    %% Drop the SSE stream
    gun:close(SseConn),
    timer:sleep(100),

    %% Session is still alive — POST still works
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {200, _, PingBody} = post_json(Port, SessionId, PingReq),
    PingResult = decode_result(PingBody),
    ?assertEqual(#{}, PingResult).

idle_gc_terminates_session(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),

    %% Session is alive
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {200, _, _} = post_json(Port, SessionId, PingReq),

    %% Wait for idle timeout (500ms) + GC interval
    timer:sleep(1000),

    %% Session should be gone
    PingReq2 = erlmcp_json_rpc:encode_request(3, <<"ping">>, #{}),
    {404, _, _} = post_json(Port, SessionId, PingReq2).

get_sse_session_death(Config) ->
    Port = proplists:get_value(port, Config),
    Mgr = proplists:get_value(mgr, Config),
    SessionId = initialize_session(Port),
    {ok, SessionPid} = erlmcp_http_session_mgr:lookup(Mgr, SessionId),

    %% Open GET SSE stream
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),
    timer:sleep(50),

    %% Kill the session — the SSE handler should detect the DOWN and close
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

    %% Open SSE stream with Last-Event-ID (no events buffered yet, so replay is empty)
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId},
        {<<"last-event-id">>, <<"5">>}
    ]),
    {response, nofin, 200, _} = gun:await(SseConn, SseRef, 5000),

    %% Trigger an event via a tool call with progress
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"steps">> => 1},
        <<"_meta">> => #{<<"progressToken">> => <<"tok2">>}
    }),
    {200, _, _} = post_json(Port, SessionId, CallReq),

    %% Collect events on the SSE stream
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
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    Headers0 = [{<<"content-type">>, <<"application/json">>}],
    Headers = case SessionId of
        undefined -> Headers0;
        _ -> [{<<"mcp-session-id">>, SessionId} | Headers0]
    end,
    StreamRef = gun:post(ConnPid, "/mcp", Headers, Body),
    case gun:await(ConnPid, StreamRef, 5000) of
        {response, fin, Status, RespHeaders} ->
            gun:close(ConnPid),
            {Status, RespHeaders, <<>>};
        {response, nofin, Status, RespHeaders} ->
            {ok, RespBody} = gun:await_body(ConnPid, StreamRef, 5000),
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

make_echo_tool() ->
    #{name => <<"echo">>,
      description => <<"Echoes input">>,
      handler => fun(Args, _Ctx) ->
          Text = maps:get(<<"text">>, Args, <<"no input">>),
          {ok, [#{<<"type">> => <<"text">>, <<"text">> => Text}]}
      end}.
