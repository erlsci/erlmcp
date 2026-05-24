-module(erlmcp_example_task_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([
    task_tool_in_list/1,
    task_call_returns_id/1,
    task_get_status/1,
    task_list/1,
    task_result/1,
    task_cancel/1,
    task_progress/1,
    task_capability_derived/1,
    task_result_not_ready/1
]).

all() ->
    [task_tool_in_list, task_call_returns_id, task_get_status,
     task_list, task_result, task_cancel, task_progress,
     task_capability_derived, task_result_not_ready].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Config.

end_per_suite(_Config) ->
    application:stop(erlmcp),
    ok.

init_per_testcase(_TC, Config) ->
    Transport = self(),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => Transport,
        name => <<"task-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"slow_compute">>,
        description => <<"A slow computation">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"n">>, erlmcp_schema:number(), [required])
        ]),
        task_support => optional,
        handler => fun(#{<<"n">> := N}, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
            timer:sleep(trunc(N)),
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    initialize(Server),
    [{server, Server} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(server, Config)),
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

send_req(Server, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(Server, Req),
    wait_response().

wait_response() ->
    Msg = decode(wait_send()),
    case maps:is_key(<<"method">>, Msg) of
        true -> wait_response();
        false -> Msg
    end.

%%====================================================================
%% Tests
%%====================================================================

task_tool_in_list(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/list">>, #{}),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    Tool = hd([T || T <- Tools, maps:get(<<"name">>, T) =:= <<"slow_compute">>]),
    ?assertEqual(<<"optional">>, maps:get(<<"taskSupport">>, Tool)).

task_call_returns_id(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 2000},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    Result = maps:get(<<"result">>, Resp),
    ?assert(maps:is_key(<<"taskId">>, Result)).

task_get_status(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 2000},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    TaskId = maps:get(<<"taskId">>, maps:get(<<"result">>, Resp)),
    timer:sleep(100),
    StatusResp = send_req(Server, 3, <<"tasks/get">>, #{<<"id">> => TaskId}),
    Status = maps:get(<<"result">>, StatusResp),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, Status)).

task_list(Config) ->
    Server = ?config(server, Config),
    _ = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 2000},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    timer:sleep(100),
    ListResp = send_req(Server, 3, <<"tasks/list">>, #{}),
    Tasks = maps:get(<<"tasks">>, maps:get(<<"result">>, ListResp)),
    ?assert(length(Tasks) >= 1).

task_result(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 50},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    TaskId = maps:get(<<"taskId">>, maps:get(<<"result">>, Resp)),
    timer:sleep(500),
    ResultResp = send_req(Server, 3, <<"tasks/result">>, #{<<"id">> => TaskId}),
    ?assert(maps:is_key(<<"result">>, ResultResp)).

task_cancel(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 5000},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    TaskId = maps:get(<<"taskId">>, maps:get(<<"result">>, Resp)),
    timer:sleep(100),
    CancelResp = send_req(Server, 3, <<"tasks/cancel">>, #{<<"id">> => TaskId}),
    ?assertMatch(#{<<"result">> := _}, CancelResp),
    timer:sleep(100),
    StatusResp = send_req(Server, 4, <<"tasks/get">>, #{<<"id">> => TaskId}),
    Status = maps:get(<<"result">>, StatusResp),
    ?assertEqual(<<"cancelled">>, maps:get(<<"status">>, Status)).

task_progress(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 500},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    ?assert(maps:is_key(<<"taskId">>, maps:get(<<"result">>, Resp))),
    ProgressNotif = decode(wait_send()),
    ?assertEqual(<<"notifications/progress">>, maps:get(<<"method">>, ProgressNotif)).

task_capability_derived(Config) ->
    gen_statem:stop(?config(server, Config)),
    Transport = self(),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => Transport,
        name => <<"no-task-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"no_task">>,
        description => <<"No task support">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    InitResp = decode(wait_send()),
    Caps = maps:get(<<"capabilities">>, maps:get(<<"result">>, InitResp)),
    ?assertNot(maps:is_key(<<"tasks">>, Caps)),
    gen_statem:stop(Server),
    {ok, Server2} = erlmcp_server_session:start_link(#{
        transport => Transport,
        name => <<"task-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server2, #{
        name => <<"task_tool">>,
        description => <<"With task support">>,
        input_schema => erlmcp_schema:object([]),
        task_support => optional,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    erlmcp_server_session:send_message(Server2, InitReq),
    InitResp2 = decode(wait_send()),
    Caps2 = maps:get(<<"capabilities">>, maps:get(<<"result">>, InitResp2)),
    ?assert(maps:is_key(<<"tasks">>, Caps2)),
    gen_statem:stop(Server2).

task_result_not_ready(Config) ->
    Server = ?config(server, Config),
    Resp = send_req(Server, 2, <<"tools/call">>, #{
        <<"name">> => <<"slow_compute">>,
        <<"arguments">> => #{<<"n">> => 5000},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    TaskId = maps:get(<<"taskId">>, maps:get(<<"result">>, Resp)),
    ResultResp = send_req(Server, 3, <<"tasks/result">>, #{<<"id">> => TaskId}),
    ?assertMatch(#{<<"error">> := _}, ResultResp).
