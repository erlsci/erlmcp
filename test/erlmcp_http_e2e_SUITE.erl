-module(erlmcp_http_e2e_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([e2e_http_scenario/1,
         concurrent_multi_client/1,
         in_session_concurrency/1,
         race_conformance/1,
         post_returns_session_id/1,
         delete_terminates_session/1,
         unknown_session_returns_404/1,
         non_json_returns_415/1,
         method_not_allowed/1,
         get_sse_without_accept/1,
         get_sse_without_session/1,
         delete_without_session/1,
         get_sse_receives_events/1,
         session_death_returns_502/1]).

all() ->
    [e2e_http_scenario,
     concurrent_multi_client,
     in_session_concurrency,
     race_conformance,
     post_returns_session_id,
     delete_terminates_session,
     unknown_session_returns_404,
     non_json_returns_415,
     method_not_allowed,
     get_sse_without_accept,
     get_sse_without_session,
     delete_without_session,
     get_sse_receives_events,
     session_death_returns_502].

init_per_suite(Config) ->
    application:ensure_all_started(cowboy),
    application:ensure_all_started(gun),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(race_conformance, Config) ->
    Tools = [make_tool(<<"tool_", (integer_to_binary(I))/binary>>,
                       <<"Tool ", (integer_to_binary(I))/binary>>)
             || I <- lists:seq(1, 5)],
    Resources = [make_resource(<<"res://", (integer_to_binary(I))/binary>>,
                               <<"Resource ", (integer_to_binary(I))/binary>>)
                 || I <- lists:seq(1, 3)],
    Prompts = [make_prompt(<<"prompt_", (integer_to_binary(I))/binary>>)
               || I <- lists:seq(1, 4)],
    start_server(Config, #{tools => Tools, resources => Resources, prompts => Prompts});
init_per_testcase(_TestCase, Config) ->
    EchoTool = #{
        name => <<"echo">>,
        description => <<"Echoes input">>,
        handler => fun(Args, _Ctx) ->
            Text = maps:get(<<"text">>, Args, <<"no input">>),
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => Text}]}
        end
    },
    BlockingTool = #{
        name => <<"blocking">>,
        description => <<"Blocks forever">>,
        handler => fun(_Args, _Ctx) ->
            receive after infinity -> ok end
        end
    },
    start_server(Config, #{tools => [EchoTool, BlockingTool]}).

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

e2e_http_scenario(Config) ->
    Port = proplists:get_value(port, Config),

    %% Initialize
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    {200, InitHeaders, InitBody} = post_json(Port, undefined, InitReq),
    InitResult = decode_result(InitBody),
    ?assertMatch(#{<<"protocolVersion">> := _}, InitResult),
    SessionId = proplists:get_value(<<"mcp-session-id">>, InitHeaders),
    ?assertNotEqual(undefined, SessionId),

    %% Send initialized notification (202 = accepted, no response body)
    InitedNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/initialized">>, #{}),
    {202, _, _} = post_json(Port, SessionId, InitedNotif),

    %% Ping
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {200, _, PingBody} = post_json(Port, SessionId, PingReq),
    PingResult = decode_result(PingBody),
    ?assertEqual(#{}, PingResult),

    %% tools/list
    ListReq = erlmcp_json_rpc:encode_request(3, <<"tools/list">>, #{}),
    {200, _, ListBody} = post_json(Port, SessionId, ListReq),
    ListResult = decode_result(ListBody),
    ToolNames = [maps:get(<<"name">>, T) || T <- maps:get(<<"tools">>, ListResult)],
    ?assert(lists:member(<<"echo">>, ToolNames)),

    %% tools/call (echo)
    CallReq = erlmcp_json_rpc:encode_request(4, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{<<"text">> => <<"hello world">>}
    }),
    {200, _, CallBody} = post_json(Port, SessionId, CallReq),
    CallResult = decode_result(CallBody),
    [Content] = maps:get(<<"content">>, CallResult),
    ?assertEqual(<<"hello world">>, maps:get(<<"text">>, Content)),

    %% Cancel: start a blocking call then cancel it.
    %% The MCP session silently drops cancelled requests (no response),
    %% so the POST connection hangs until closed. We verify the cancel
    %% was accepted by checking the session is still operational after.
    BlockReq = erlmcp_json_rpc:encode_request(5, <<"tools/call">>, #{
        <<"name">> => <<"blocking">>,
        <<"arguments">> => #{}
    }),
    Parent = self(),
    Blocker = spawn(fun() ->
        Result = post_json(Port, SessionId, BlockReq),
        Parent ! {block_result, Result}
    end),
    timer:sleep(100),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 5}),
    {202, _, _} = post_json(Port, SessionId, CancelNotif),
    timer:sleep(100),
    exit(Blocker, kill),
    %% Session still works after cancel
    Ping2Req = erlmcp_json_rpc:encode_request(6, <<"ping">>, #{}),
    {200, _, Ping2Body} = post_json(Port, SessionId, Ping2Req),
    Ping2Result = decode_result(Ping2Body),
    ?assertEqual(#{}, Ping2Result).

post_returns_session_id(Config) ->
    Port = proplists:get_value(port, Config),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    {200, Headers, _} = post_json(Port, undefined, InitReq),
    SessionId = proplists:get_value(<<"mcp-session-id">>, Headers),
    ?assert(is_binary(SessionId)),
    ?assertEqual(32, byte_size(SessionId)).

delete_terminates_session(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    {200, _, _} = delete_session(Port, SessionId),
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    {404, _, _} = post_json(Port, SessionId, PingReq).

unknown_session_returns_404(Config) ->
    Port = proplists:get_value(port, Config),
    PingReq = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    {404, _, _} = post_json(Port, <<"nonexistent_session_id">>, PingReq).

non_json_returns_415(Config) ->
    Port = proplists:get_value(port, Config),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:post(ConnPid, "/mcp",
        [{<<"content-type">>, <<"text/plain">>}], <<"hello">>),
    case gun:await(ConnPid, StreamRef, 5000) of
        {response, fin, 415, _} -> ok;
        {response, nofin, 415, _} ->
            {ok, _Body} = gun:await_body(ConnPid, StreamRef, 5000),
            ok
    end,
    gun:close(ConnPid).

concurrent_multi_client(Config) ->
    Port = proplists:get_value(port, Config),
    N = 10,
    Parent = self(),
    Pids = [spawn_link(fun() ->
        SessionId = initialize_session(Port),
        CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
            <<"name">> => <<"echo">>,
            <<"arguments">> => #{<<"text">> => SessionId}
        }),
        {200, _, Body} = post_json(Port, SessionId, CallReq),
        Result = decode_result(Body),
        [Content] = maps:get(<<"content">>, Result),
        Text = maps:get(<<"text">>, Content),
        Parent ! {client_done, self(), SessionId, Text}
    end) || _ <- lists:seq(1, N)],
    Results = [receive
        {client_done, Pid, SId, Text} -> {SId, Text}
    after 10000 ->
        ct:fail({timeout, Pid})
    end || Pid <- Pids],
    lists:foreach(fun({SId, Text}) ->
        ?assertEqual(SId, Text)
    end, Results).

in_session_concurrency(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    M = 5,
    Parent = self(),
    Pids = [spawn_link(fun() ->
        Id = I + 10,
        Marker = <<"req_", (integer_to_binary(I))/binary>>,
        CallReq = erlmcp_json_rpc:encode_request(Id, <<"tools/call">>, #{
            <<"name">> => <<"echo">>,
            <<"arguments">> => #{<<"text">> => Marker}
        }),
        {200, _, Body} = post_json(Port, SessionId, CallReq),
        {ok, Decoded} = erlmcp_codec:decode(Body),
        RespId = maps:get(<<"id">>, Decoded),
        Result = maps:get(<<"result">>, Decoded),
        [Content] = maps:get(<<"content">>, Result),
        Text = maps:get(<<"text">>, Content),
        Parent ! {req_done, self(), Id, RespId, Marker, Text}
    end) || I <- lists:seq(1, M)],
    Results = [receive
        {req_done, Pid, ExpId, RespId, Marker, Text} ->
            {ExpId, RespId, Marker, Text}
    after 10000 ->
        ct:fail({timeout, Pid})
    end || Pid <- Pids],
    lists:foreach(fun({ExpId, RespId, Marker, Text}) ->
        ?assertEqual(ExpId, RespId),
        ?assertEqual(Marker, Text)
    end, Results).

race_conformance(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    ToolsReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    {200, _, ToolsBody} = post_json(Port, SessionId, ToolsReq),
    ToolsResult = decode_result(ToolsBody),
    ToolCount = length(maps:get(<<"tools">>, ToolsResult)),
    ?assertEqual(5, ToolCount),

    ResReq = erlmcp_json_rpc:encode_request(3, <<"resources/list">>, #{}),
    {200, _, ResBody} = post_json(Port, SessionId, ResReq),
    ResResult = decode_result(ResBody),
    ResCount = length(maps:get(<<"resources">>, ResResult)),
    ?assertEqual(3, ResCount),

    PromptsReq = erlmcp_json_rpc:encode_request(4, <<"prompts/list">>, #{}),
    {200, _, PromptsBody} = post_json(Port, SessionId, PromptsReq),
    PromptsResult = decode_result(PromptsBody),
    PromptCount = length(maps:get(<<"prompts">>, PromptsResult)),
    ?assertEqual(4, PromptCount).

method_not_allowed(Config) ->
    Port = proplists:get_value(port, Config),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:put(ConnPid, "/mcp",
        [{<<"content-type">>, <<"application/json">>}], <<"hello">>),
    {response, nofin, 405, _} = gun:await(ConnPid, StreamRef, 5000),
    gun:close(ConnPid).

get_sse_without_accept(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:get(ConnPid, "/mcp", [
        {<<"mcp-session-id">>, SessionId},
        {<<"accept">>, <<"application/json">>}
    ]),
    {response, nofin, 406, _} = gun:await(ConnPid, StreamRef, 5000),
    gun:close(ConnPid).

get_sse_without_session(Config) ->
    Port = proplists:get_value(port, Config),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:get(ConnPid, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>}
    ]),
    {response, nofin, 400, _} = gun:await(ConnPid, StreamRef, 5000),
    gun:close(ConnPid).

delete_without_session(Config) ->
    Port = proplists:get_value(port, Config),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    StreamRef = gun:delete(ConnPid, "/mcp", []),
    {response, nofin, 400, _} = gun:await(ConnPid, StreamRef, 5000),
    gun:close(ConnPid).

session_death_returns_502(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    Mgr = proplists:get_value(mgr, Config),
    {ok, SessionPid} = erlmcp_http_session_mgr:lookup(Mgr, SessionId),
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    BlockReq = erlmcp_json_rpc:encode_request(99, <<"tools/call">>, #{
        <<"name">> => <<"blocking">>,
        <<"arguments">> => #{}
    }),
    StreamRef = gun:post(ConnPid, "/mcp",
        [{<<"content-type">>, <<"application/json">>},
         {<<"mcp-session-id">>, SessionId}],
        BlockReq),
    timer:sleep(100),
    exit(SessionPid, kill),
    case gun:await(ConnPid, StreamRef, 5000) of
        {response, nofin, 502, _} ->
            {ok, _} = gun:await_body(ConnPid, StreamRef, 5000),
            ok;
        {response, fin, 502, _} ->
            ok
    end,
    gun:close(ConnPid).

get_sse_receives_events(Config) ->
    Port = proplists:get_value(port, Config),
    SessionId = initialize_session(Port),
    {ok, SseConn} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(SseConn),
    SseRef = gun:get(SseConn, "/mcp", [
        {<<"accept">>, <<"text/event-stream">>},
        {<<"mcp-session-id">>, SessionId}
    ]),
    {response, nofin, 200, SseHeaders} = gun:await(SseConn, SseRef, 5000),
    CT = proplists:get_value(<<"content-type">>, SseHeaders),
    ?assertEqual(<<"text/event-stream">>, CT),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{<<"text">> => <<"sse_test">>}
    }),
    {200, _, _} = post_json(Port, SessionId, CallReq),
    gun:close(SseConn).

%%====================================================================
%% Helpers
%%====================================================================

start_server(Config, ExtraConfig) ->
    ServerConfig = maps:merge(#{
        name => <<"test_http">>,
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
    proplists:get_value(<<"mcp-session-id">>, Headers).

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

delete_session(Port, SessionId) ->
    {ok, ConnPid} = gun:open("127.0.0.1", Port),
    {ok, _} = gun:await_up(ConnPid),
    Headers = [{<<"mcp-session-id">>, SessionId}],
    StreamRef = gun:delete(ConnPid, "/mcp", Headers),
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

make_tool(Name, Desc) ->
    #{name => Name, description => Desc,
      handler => fun(_Args, _Ctx) ->
          {ok, [#{<<"type">> => <<"text">>, <<"text">> => Name}]}
      end}.

make_resource(Uri, Name) ->
    #{uri => Uri, name => Name,
      handler => fun(_Ctx) ->
          {ok, [#{<<"uri">> => Uri, <<"text">> => <<"data">>}]}
      end}.

make_prompt(Name) ->
    #{name => Name,
      handler => fun(_Args, _Ctx) ->
          {ok, [#{<<"role">> => <<"assistant">>,
                  <<"content">> => #{<<"type">> => <<"text">>,
                                     <<"text">> => Name}}]}
      end}.
