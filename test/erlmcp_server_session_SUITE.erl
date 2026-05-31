-module(erlmcp_server_session_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([mfa_tool_handler/2]).
-export([
    shared_catalog_two_sessions/1,
    late_registration_visible/1,
    per_request_reply_target/1,
    push_channel_notification/1,
    resources_read_static/1,
    resources_read_template/1,
    resources_subscribe_unsubscribe/1,
    resources_templates_list/1,
    prompts_get/1,
    completion_complete_prompt/1,
    completion_complete_template/1,
    tasks_lifecycle/1,
    logging_set_level_and_emit/1,
    shutting_down_rejects/1,
    resource_updated_notification/1,
    worker_crash_returns_internal_error/1,
    generic_handler_dispatch/1,
    resource_read_uri_handler/1,
    task_not_found_errors/1,
    uninitialized_rejects_non_init/1,
    peer_request_roundtrip/1,
    tool_handler_error_return/1,
    tool_output_schema_validation/1,
    tool_single_map_result/1,
    tool_with_meta_result/1,
    tool_mfa_handler/1,
    cancel_inflight_request/1,
    batch_request/1,
    prompts_list/1,
    resources_list/1,
    resources_read_not_found/1,
    tool_progress_token/1,
    handler_module_tool_call/1,
    input_validation_rejects/1,
    tool_single_map_structured/1,
    unknown_tool_name/1,
    prompts_get_not_found/1,
    resources_read_missing_uri/1,
    tool_single_map_with_meta/1,
    tool_missing_name/1,
    prompts_get_missing_name/1,
    batch_with_outbound_response/1,
    emit_log_filtered/1,
    task_with_handler_module/1,
    info_transport_data/1,
    unknown_event_ignored/1,
    error_response_to_outbound/1,
    task_cancel_running/1,
    resource_read_list_handler/1,
    parse_error_returns_error_response/1,
    cancel_nonexistent_request_no_crash/1,
    instructions_enriched/1,
    instructions_override/1,
    protocol_features_surfaced/1
]).

all() ->
    [shared_catalog_two_sessions,
     late_registration_visible,
     per_request_reply_target,
     push_channel_notification,
     resources_read_static,
     resources_read_template,
     resources_subscribe_unsubscribe,
     resources_templates_list,
     prompts_get,
     completion_complete_prompt,
     completion_complete_template,
     tasks_lifecycle,
     logging_set_level_and_emit,
     shutting_down_rejects,
     resource_updated_notification,
     worker_crash_returns_internal_error,
     generic_handler_dispatch,
     resource_read_uri_handler,
     task_not_found_errors,
     uninitialized_rejects_non_init,
     peer_request_roundtrip,
     tool_handler_error_return,
     tool_output_schema_validation,
     tool_single_map_result,
     tool_with_meta_result,
     tool_mfa_handler,
     cancel_inflight_request,
     batch_request,
     prompts_list,
     resources_list,
     resources_read_not_found,
     tool_progress_token,
     handler_module_tool_call,
     input_validation_rejects,
     tool_single_map_structured,
     unknown_tool_name,
     prompts_get_not_found,
     resources_read_missing_uri,
     tool_single_map_with_meta,
     tool_missing_name,
     prompts_get_missing_name,
     batch_with_outbound_response,
     emit_log_filtered,
     task_with_handler_module,
     info_transport_data,
     unknown_event_ignored,
     error_response_to_outbound,
     task_cancel_running,
     resource_read_list_handler,
     parse_error_returns_error_response,
     cancel_nonexistent_request_no_crash,
     instructions_enriched,
     instructions_override,
     protocol_features_surfaced].

init_per_testcase(protocol_features_surfaced, Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"pf-srv">>, version => <<"1.0">>,
        tools => [
            #{name => <<"ask">>, description => <<"sampling tool">>,
              protocol_features => [sampling],
              handler => fun(_, _) -> {ok, []} end},
            erlmcp:make_directory_tool()
        ]
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Server, responder => Responder,
        name => <<"pf-srv">>, version => <<"1.0">>
    }),
    [{server, Server}, {session, Session}, {responder, Responder} | Config];
init_per_testcase(instructions_override, Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"override-srv">>, version => <<"1.0">>,
        instructions => <<"Custom server README for LLM consumers.">>,
        tools => [
            #{name => <<"t">>, description => <<"a tool">>,
              handler => fun(_, _) -> {ok, []} end}
        ]
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Server, responder => Responder,
        name => <<"override-srv">>, version => <<"1.0">>
    }),
    [{server, Server}, {session, Session}, {responder, Responder} | Config];
init_per_testcase(_TC, Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"ct-server">>, version => <<"1.0">>,
        tools => [
            #{name => <<"echo">>, description => <<"echo tool">>,
              handler => fun(Args, _Ctx) ->
                  {ok, [#{<<"type">> => <<"text">>,
                          <<"text">> => maps:get(<<"input">>, Args, <<>>)}]}
              end},
            #{name => <<"slow">>, description => <<"slow tool for tasks">>,
              input_schema => erlmcp_schema:object([]),
              task_support => enabled,
              handler => fun(_, _) ->
                  timer:sleep(100),
                  {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"done">>}]}
              end}
        ],
        resources => [
            #{uri => <<"test://static/1">>, name => <<"Static Resource">>,
              handler => fun(_Ctx) ->
                  {ok, #{<<"uri">> => <<"test://static/1">>,
                         <<"text">> => <<"static content">>}}
              end}
        ],
        prompts => [
            #{name => <<"greet">>, description => <<"Greeting prompt">>,
              arguments => [#{name => <<"name">>, description => <<"Name">>, required => true}],
              handler => fun(#{<<"name">> := Name}, _Ctx) ->
                  {ok, [#{<<"role">> => <<"user">>,
                          <<"content">> => #{<<"type">> => <<"text">>,
                                             <<"text">> => <<"Hello, ", Name/binary>>}}]}
              end,
              completions => #{<<"name">> => fun(Prefix) ->
                  [N || N <- [<<"Alice">>, <<"Bob">>, <<"Carol">>],
                        binary:match(N, Prefix) =/= nomatch]
              end}}
        ]
    }),
    ok = erlmcp_server:register_resource_template(Server, #{
        uri_template => <<"test://item/{id}">>,
        name => <<"Item Template">>,
        handler => fun(#{<<"id">> := Id}, _Ctx) ->
            {ok, #{<<"uri">> => <<"test://item/", Id/binary>>,
                   <<"text">> => <<"item ", Id/binary>>}}
        end,
        completions => #{<<"id">> => fun(_) -> [<<"1">>, <<"2">>, <<"3">>] end}
    }),
    [{server, Server} | Config].

end_per_testcase(TC, Config) when TC =:= instructions_override;
                                  TC =:= protocol_features_surfaced ->
    catch gen_statem:stop(?config(session, Config)),
    gen_server:stop(?config(server, Config)),
    ok;
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
    R1Tools = receive_result(),
    ok = erlmcp_server_session:send_message(S2, ListMsg),
    R2Tools = receive_result(),
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
    Result = receive_result(),
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
%% Resources
%%====================================================================

resources_read_static(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"test://static/1">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Contents = maps:get(<<"contents">>, Result),
    ?assert(is_list(Contents)),
    [Content] = Contents,
    ?assertEqual(<<"static content">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

resources_read_template(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"test://item/42">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Contents = maps:get(<<"contents">>, Result),
    [Content] = Contents,
    ?assertEqual(<<"item 42">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

resources_subscribe_unsubscribe(Config) ->
    {S, _} = start_session(Config),
    SubReq = erlmcp_json_rpc:encode_request(2, <<"resources/subscribe">>,
        #{<<"uri">> => <<"test://static/1">>}),
    ok = erlmcp_server_session:send_message(S, SubReq),
    _ = receive_response(),
    gen_statem:cast(S, {resource_updated, <<"test://static/1">>}),
    Notif = receive_raw_decoded(),
    ?assertEqual(<<"notifications/resources/updated">>, maps:get(<<"method">>, Notif)),
    UnsubReq = erlmcp_json_rpc:encode_request(3, <<"resources/unsubscribe">>,
        #{<<"uri">> => <<"test://static/1">>}),
    ok = erlmcp_server_session:send_message(S, UnsubReq),
    _ = receive_response(),
    gen_statem:cast(S, {resource_updated, <<"test://static/1">>}),
    receive {send, _} -> ct:fail(should_not_receive) after 200 -> ok end,
    gen_statem:stop(S).

resources_templates_list(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/templates/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Templates = maps:get(<<"resourceTemplates">>, Result),
    ?assert(length(Templates) >= 1),
    gen_statem:stop(S).

%%====================================================================
%% Prompts
%%====================================================================

prompts_get(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"prompts/get">>,
        #{<<"name">> => <<"greet">>, <<"arguments">> => #{<<"name">> => <<"World">>}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Messages = maps:get(<<"messages">>, Result),
    ?assert(length(Messages) >= 1),
    [Msg | _] = Messages,
    MsgContent = maps:get(<<"content">>, Msg),
    ?assertMatch(<<"Hello, World">>, maps:get(<<"text">>, MsgContent)),
    gen_statem:stop(S).

%%====================================================================
%% Completion
%%====================================================================

completion_complete_prompt(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"greet">>},
        <<"argument">> => #{<<"name">> => <<"name">>, <<"value">> => <<"A">>}
    }),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Completion = maps:get(<<"completion">>, Result),
    Values = maps:get(<<"values">>, Completion),
    ?assert(lists:member(<<"Alice">>, Values)),
    gen_statem:stop(S).

completion_complete_template(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/resource">>, <<"uri">> => <<"test://item/{id}">>},
        <<"argument">> => #{<<"name">> => <<"id">>, <<"value">> => <<>>}
    }),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Completion = maps:get(<<"completion">>, Result),
    Values = maps:get(<<"values">>, Completion),
    ?assert(lists:member(<<"1">>, Values)),
    gen_statem:stop(S).

%%====================================================================
%% Tasks
%%====================================================================

tasks_lifecycle(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    ok = erlmcp_server_session:send_message(S, CallReq),
    CallResult = receive_result(),
    TaskId = maps:get(<<"taskId">>, CallResult),
    ?assert(is_binary(TaskId)),
    ListReq = erlmcp_json_rpc:encode_request(3, <<"tasks/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, ListReq),
    ListResult = receive_result(),
    ?assert(is_list(maps:get(<<"tasks">>, ListResult))),
    GetReq = erlmcp_json_rpc:encode_request(4, <<"tasks/get">>,
        #{<<"id">> => TaskId}),
    ok = erlmcp_server_session:send_message(S, GetReq),
    _ = receive_response(),
    timer:sleep(200),
    ResultReq = erlmcp_json_rpc:encode_request(5, <<"tasks/result">>,
        #{<<"id">> => TaskId}),
    ok = erlmcp_server_session:send_message(S, ResultReq),
    _ = receive_response(),
    CancelReq = erlmcp_json_rpc:encode_request(6, <<"tasks/cancel">>,
        #{<<"id">> => <<"nonexistent">>}),
    ok = erlmcp_server_session:send_message(S, CancelReq),
    CancelResp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, CancelResp),
    gen_statem:stop(S).

%%====================================================================
%% Logging
%%====================================================================

logging_set_level_and_emit(Config) ->
    {S, _} = start_session(Config),
    SetReq = erlmcp_json_rpc:encode_request(2, <<"logging/setLevel">>,
        #{<<"level">> => <<"info">>}),
    ok = erlmcp_server_session:send_message(S, SetReq),
    _ = receive_response(),
    erlmcp_server_session:emit_log(S, info, <<"test">>, <<"hello">>),
    Notif = receive_raw_decoded(),
    ?assertEqual(<<"notifications/message">>, maps:get(<<"method">>, Notif)),
    Params = maps:get(<<"params">>, Notif),
    ?assertEqual(<<"info">>, maps:get(<<"level">>, Params)),
    erlmcp_server_session:emit_log(S, debug, <<"test">>, <<"filtered">>),
    receive {send, _} -> ct:fail(should_be_filtered) after 200 -> ok end,
    gen_statem:stop(S).

%%====================================================================
%% Shutting down / edge cases
%%====================================================================

shutting_down_rejects(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    sys:replace_state(S, fun({_StateName, Data}) -> {shutting_down, Data} end),
    Req = erlmcp_json_rpc:encode_request(99, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    receive {send, _} -> ct:fail(should_not_respond) after 200 -> ok end,
    ?assertEqual({error, unknown_request}, gen_statem:call(S, bogus)),
    ?assertEqual(shutting_down, gen_statem:call(S, get_state)),
    gen_statem:stop(S).

resource_updated_notification(Config) ->
    {S, _} = start_session(Config),
    SubReq = erlmcp_json_rpc:encode_request(2, <<"resources/subscribe">>,
        #{<<"uri">> => <<"test://static/1">>}),
    ok = erlmcp_server_session:send_message(S, SubReq),
    _ = receive_response(),
    gen_statem:cast(S, {resource_updated, <<"test://static/1">>}),
    Notif = receive_raw_decoded(),
    ?assertEqual(<<"notifications/resources/updated">>, maps:get(<<"method">>, Notif)),
    gen_statem:cast(S, {resource_updated, <<"unsubscribed://uri">>}),
    receive {send, _} -> ct:fail(should_not_notify) after 200 -> ok end,
    gen_statem:stop(S).

%%====================================================================
%% Worker crash and generic dispatch
%%====================================================================

worker_crash_returns_internal_error(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"crasher">>, description => <<"crashes">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> error(boom) end
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"crasher">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32603}}, Resp),
    gen_statem:stop(S).

generic_handler_dispatch(_Config) ->
    HandlerFun = fun(_Params, _Ctx) ->
        {ok, #{<<"custom">> => true}}
    end,
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"handler-test">>, version => <<"1.0">>,
        handlers => #{<<"custom/method">> => HandlerFun}
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Srv, responder => R}),
    initialize_session(S),
    Req = erlmcp_json_rpc:encode_request(2, <<"custom/method">>, #{<<"x">> => 1}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    ?assertEqual(true, maps:get(<<"custom">>, Result)),
    gen_statem:stop(S),
    gen_server:stop(Srv).

resource_read_uri_handler(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_resource(Server, #{
        uri => <<"test://uri-handler">>,
        name => <<"URI Handler Resource">>,
        handler => fun(Uri, _Ctx) ->
            {ok, #{<<"uri">> => Uri, <<"text">> => <<"from uri handler">>}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"test://uri-handler">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    [Content] = maps:get(<<"contents">>, Result),
    ?assertEqual(<<"from uri handler">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

task_not_found_errors(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {S, _} = start_session(Config),
    GetReq = erlmcp_json_rpc:encode_request(2, <<"tasks/get">>,
        #{<<"id">> => <<"nonexistent">>}),
    ok = erlmcp_server_session:send_message(S, GetReq),
    Resp1 = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32002}}, Resp1),
    ResultReq = erlmcp_json_rpc:encode_request(3, <<"tasks/result">>,
        #{<<"id">> => <<"nonexistent">>}),
    ok = erlmcp_server_session:send_message(S, ResultReq),
    Resp2 = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32002}}, Resp2),
    gen_statem:stop(S).

uninitialized_rejects_non_init(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    Req = erlmcp_json_rpc:encode_request(1, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

peer_request_roundtrip(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"peer_caller">>, description => <<"calls peer">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_Args, Ctx) ->
            Result = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                #{<<"messages">> => []}),
            case Result of
                {ok, PeerResp} ->
                    {ok, [#{<<"type">> => <<"text">>,
                            <<"text">> => maps:get(<<"content">>, PeerResp, <<"none">>)}]};
                {error, _} ->
                    {error, -32603, <<"peer failed">>}
            end
        end
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    Req = erlmcp_json_rpc:encode_request(10, <<"tools/call">>,
        #{<<"name">> => <<"peer_caller">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    PeerReq = receive_response(),
    ?assertEqual(<<"sampling/createMessage">>, maps:get(<<"method">>, PeerReq)),
    PeerReqId = maps:get(<<"id">>, PeerReq),
    PeerResp = erlmcp_json_rpc:encode_response(PeerReqId, #{<<"content">> => <<"sampled">>}),
    ok = erlmcp_server_session:send_message(S, PeerResp),
    ToolResult = receive_result(),
    [Content] = maps:get(<<"content">>, ToolResult),
    ?assertEqual(<<"sampled">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

tool_handler_error_return(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"err_tool">>, description => <<"returns error">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {error, -32001, <<"custom error">>} end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"err_tool">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    Error = maps:get(<<"error">>, Resp),
    ?assertEqual(-32001, maps:get(<<"code">>, Error)),
    gen_statem:stop(S).

tool_output_schema_validation(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"validated">>, description => <<"has output schema">>,
        input_schema => erlmcp_schema:object([]),
        output_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"result">>, erlmcp_schema:string(), [required])
        ]),
        handler => fun(_, _) ->
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"ok">>}],
                 #{<<"result">> => <<"valid">>}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"validated">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    ?assert(maps:is_key(<<"structuredContent">>, Result)),
    gen_statem:stop(S).

tool_single_map_result(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"single_map">>, description => <<"returns single map">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, #{<<"type">> => <<"text">>, <<"text">> => <<"single">>}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"single_map">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"single">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

tool_with_meta_result(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"meta_tool">>, description => <<"returns meta">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"ok">>}],
                 #{<<"s">> => 1}, #{<<"requestId">> => <<"abc">>}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"meta_tool">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    ?assert(maps:is_key(<<"_meta">>, Result)),
    ?assertEqual(<<"abc">>, maps:get(<<"requestId">>, maps:get(<<"_meta">>, Result))),
    gen_statem:stop(S).

tool_mfa_handler(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"mfa_tool">>, description => <<"mfa handler">>,
        input_schema => erlmcp_schema:object([]),
        handler => {erlmcp_server_session_SUITE, mfa_tool_handler}
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"mfa_tool">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"mfa">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

cancel_inflight_request(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"block">>, description => <<"blocks forever">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> receive after infinity -> ok end end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(50, <<"tools/call">>,
        #{<<"name">> => <<"block">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    timer:sleep(50),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 50}),
    ok = erlmcp_server_session:send_message(S, CancelNotif),
    timer:sleep(50),
    receive {send, _} -> ok after 500 -> ok end,
    gen_statem:stop(S).

batch_request(Config) ->
    {S, _} = start_session(Config),
    Batch = erlmcp_json_rpc:encode_batch([
        erlmcp_json_rpc:encode_request(10, <<"ping">>, #{}),
        erlmcp_json_rpc:encode_request(11, <<"tools/list">>, #{})
    ]),
    ok = erlmcp_server_session:send_message(S, Batch),
    BatchResp = receive_response(),
    ?assert(is_list(BatchResp)),
    ?assertEqual(2, length(BatchResp)),
    gen_statem:stop(S).

prompts_list(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"prompts/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Prompts = maps:get(<<"prompts">>, Result),
    ?assert(length(Prompts) >= 1),
    [P | _] = Prompts,
    ?assertEqual(<<"greet">>, maps:get(<<"name">>, P)),
    gen_statem:stop(S).

resources_list(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Resources = maps:get(<<"resources">>, Result),
    ?assert(length(Resources) >= 1),
    gen_statem:stop(S).

resources_read_not_found(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"nonexistent://nothing">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32002}}, Resp),
    gen_statem:stop(S).

tool_progress_token(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"progress_tool">>, description => <<"reports progress">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"half">>),
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"done">>}]}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"progress_tool">>, <<"arguments">> => #{},
          <<"_meta">> => #{<<"progressToken">> => <<"tok">>}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Notif = receive_response(),
    ?assertEqual(<<"notifications/progress">>, maps:get(<<"method">>, Notif)),
    _ = receive_response(),
    gen_statem:stop(S).

handler_module_tool_call(_Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"hm-test">>, version => <<"1.0">>,
        handler => test_calc_handler
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Srv, responder => R}),
    initialize_session(S),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"add">>, <<"arguments">> => #{<<"a">> => 3, <<"b">> => 4}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"7">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S),
    gen_server:stop(Srv).

input_validation_rejects(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"strict">>, description => <<"strict schema">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"x">>, erlmcp_schema:number(), [required])
        ]),
        handler => fun(_, _) -> {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"ok">>}]} end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"strict">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

tool_single_map_structured(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"sms">>, description => <<"single map + structured">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, #{<<"type">> => <<"text">>, <<"text">> => <<"hi">>},
                 #{<<"val">> => 42}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"sms">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    ?assert(maps:is_key(<<"structuredContent">>, Result)),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"hi">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

unknown_tool_name(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"no_such_tool">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(S).

prompts_get_not_found(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"prompts/get">>,
        #{<<"name">> => <<"nonexistent">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32003}}, Resp),
    gen_statem:stop(S).

resources_read_missing_uri(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

tool_single_map_with_meta(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"smm">>, description => <<"single map + structured + meta">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, #{<<"type">> => <<"text">>, <<"text">> => <<"x">>},
                 #{<<"s">> => 1}, #{<<"rid">> => <<"r1">>}}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"name">> => <<"smm">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    ?assert(maps:is_key(<<"_meta">>, Result)),
    ?assert(maps:is_key(<<"structuredContent">>, Result)),
    gen_statem:stop(S).

tool_missing_name(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"tools/call">>,
        #{<<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

prompts_get_missing_name(Config) ->
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"prompts/get">>, #{}),
    ok = erlmcp_server_session:send_message(S, Req),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

batch_with_outbound_response(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"peer_batch">>, description => <<"peer call for batch test">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            case erlmcp_ctx:request_peer(Ctx, <<"test/method">>, #{}) of
                {ok, R} -> {ok, [#{<<"type">> => <<"text">>,
                                   <<"text">> => maps:get(<<"v">>, R, <<>>)}]};
                _ -> {error, -1, <<"fail">>}
            end
        end
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    ToolReq = erlmcp_json_rpc:encode_request(20, <<"tools/call">>,
        #{<<"name">> => <<"peer_batch">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, ToolReq),
    PeerReq = receive_response(),
    PeerReqId = maps:get(<<"id">>, PeerReq),
    Batch = erlmcp_json_rpc:encode_batch([
        erlmcp_json_rpc:encode_response(PeerReqId, #{<<"v">> => <<"batched">>})
    ]),
    ok = erlmcp_server_session:send_message(S, Batch),
    ToolResp = receive_result(),
    [Content] = maps:get(<<"content">>, ToolResp),
    ?assertEqual(<<"batched">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(S).

emit_log_filtered(Config) ->
    {S, _} = start_session(Config),
    erlmcp_server_session:emit_log(S, debug, <<"test">>, <<"should be filtered">>),
    receive {send, _} -> ct:fail(should_be_filtered) after 200 -> ok end,
    gen_statem:stop(S).

task_with_handler_module(_Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"task-hm">>, version => <<"1.0">>,
        handler => test_calc_handler
    }),
    Tab = erlmcp_server:catalog_table(Srv),
    {ok, AddSpec} = erlmcp_server:get_tool(Tab, <<"add">>),
    ok = erlmcp_server:register_tool(Srv, AddSpec#{task_support => enabled}),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Srv, responder => R}),
    initialize_session(S),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"add">>,
        <<"arguments">> => #{<<"a">> => 5, <<"b">> => 3},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    ok = erlmcp_server_session:send_message(S, CallReq),
    Result = receive_result(),
    ?assert(maps:is_key(<<"taskId">>, Result)),
    timer:sleep(200),
    gen_statem:stop(S),
    gen_server:stop(Srv).

%%====================================================================
%% Parse errors and cancel edge cases (folded from erlmcp_session_tests)
%%====================================================================

parse_error_returns_error_response(Config) ->
    {S, _} = start_session(Config),
    ok = erlmcp_server_session:send_message(S, <<"not valid json">>),
    Resp = receive_response(),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32700}}, Resp),
    gen_statem:stop(S).

cancel_nonexistent_request_no_crash(Config) ->
    {S, _} = start_session(Config),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 99999}),
    ok = erlmcp_server_session:send_message(S, CancelNotif),
    timer:sleep(50),
    ?assert(is_process_alive(S)),
    gen_statem:stop(S).

%%====================================================================
%% Additional coverage targets
%%====================================================================

task_cancel_running(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    ok = erlmcp_server_session:send_message(S, CallReq),
    CallResult = receive_result(),
    TaskId = maps:get(<<"taskId">>, CallResult),
    CancelReq = erlmcp_json_rpc:encode_request(3, <<"tasks/cancel">>,
        #{<<"id">> => TaskId}),
    ok = erlmcp_server_session:send_message(S, CancelReq),
    CancelResult = receive_result(),
    ?assertEqual(#{}, CancelResult),
    gen_statem:stop(S).

resource_read_list_handler(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_resource(Server, #{
        uri => <<"test://list-return">>,
        name => <<"List Handler">>,
        handler => fun(_Ctx) ->
            {ok, [#{<<"uri">> => <<"test://list-return">>,
                    <<"text">> => <<"item1">>},
                  #{<<"uri">> => <<"test://list-return">>,
                    <<"text">> => <<"item2">>}]}
        end
    }),
    {S, _} = start_session(Config),
    Req = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"test://list-return">>}),
    ok = erlmcp_server_session:send_message(S, Req),
    Result = receive_result(),
    Contents = maps:get(<<"contents">>, Result),
    ?assertEqual(2, length(Contents)),
    gen_statem:stop(S).

%%====================================================================
%% Info/event path tests
%%====================================================================

info_transport_data(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    S ! {transport_data, InitMsg},
    _ = receive_response(),
    PingMsg = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    S ! {transport_data, PingMsg},
    PingResp = receive_result(),
    ?assertEqual(#{}, PingResp),
    gen_statem:stop(S).

unknown_event_ignored(Config) ->
    {S, _} = start_session(Config),
    S ! some_random_message,
    S ! {catalog_changed, <<"notifications/tools/list_changed">>},
    timer:sleep(50),
    ?assert(is_process_alive(S)),
    gen_statem:stop(S).

error_response_to_outbound(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp_server:register_tool(Server, #{
        name => <<"peer_err">>, description => <<"gets error from peer">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            case erlmcp_ctx:request_peer(Ctx, <<"test/fail">>, #{}) of
                {ok, _} -> {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"ok">>}]};
                {error, ErrMap} when is_map(ErrMap) ->
                    {ok, [#{<<"type">> => <<"text">>,
                            <<"text">> => maps:get(<<"message">>, ErrMap, <<"err">>)}]};
                {error, _} ->
                    {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"error">>}]}
            end
        end
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    ToolReq = erlmcp_json_rpc:encode_request(30, <<"tools/call">>,
        #{<<"name">> => <<"peer_err">>, <<"arguments">> => #{}}),
    ok = erlmcp_server_session:send_message(S, ToolReq),
    PeerReq = receive_response(),
    PeerReqId = maps:get(<<"id">>, PeerReq),
    ErrorResp = erlmcp_json_rpc:encode_error_response(PeerReqId, -32000, <<"peer error">>),
    ok = erlmcp_server_session:send_message(S, ErrorResp),
    _ = receive_response(),
    gen_statem:stop(S).

%%====================================================================
%% MFA handler callback (used by tool_mfa_handler test)
%%====================================================================

mfa_tool_handler(_Args, _Ctx) ->
    {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"mfa">>}]}.

%%====================================================================
%% Helpers
%%====================================================================

start_session(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{server => Server, responder => R}),
    initialize_session(S),
    {S, R}.

initialize_session(S) ->
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    _ = receive_response(),
    ok.

receive_response() ->
    receive
        {send, Json} ->
            {ok, Decoded} = erlmcp_codec:decode(Json),
            Decoded
    after 2000 ->
        error(timeout)
    end.

receive_result() ->
    Decoded = receive_response(),
    maps:get(<<"result">>, Decoded).

receive_raw_decoded() ->
    receive
        {send, Json} ->
            {ok, Decoded} = erlmcp_codec:decode(Json),
            Decoded
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

instructions_enriched(Config) ->
    Server = ?config(server, Config),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{
        server => Server, responder => R,
        name => <<"ct-server">>, version => <<"1.0">>
    }),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    Resp = receive_response(),
    Result = maps:get(<<"result">>, Resp),
    Instr = maps:get(<<"instructions">>, Result),
    ?assert(is_binary(Instr)),
    ?assert(binary:match(Instr, <<"ct-server">>) =/= nomatch),
    ?assert(binary:match(Instr, <<"directory">>) =/= nomatch),
    gen_statem:stop(S).

instructions_override(Config) ->
    S = ?config(session, Config),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    Resp = receive_response(),
    Result = maps:get(<<"result">>, Resp),
    Instr = maps:get(<<"instructions">>, Result),
    ?assertEqual(<<"Custom server README for LLM consumers.">>, Instr),
    gen_statem:stop(S).

protocol_features_surfaced(Config) ->
    S = ?config(session, Config),
    InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
        #{<<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    ok = erlmcp_server_session:send_message(S, InitMsg),
    InitResp = receive_response(),
    Instr = maps:get(<<"instructions">>,
                     maps:get(<<"result">>, InitResp)),
    ?assert(binary:match(Instr, <<"sampling">>) =/= nomatch),
    InitedNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/initialized">>, #{}),
    ok = erlmcp_server_session:send_message(S, InitedNotif),
    timer:sleep(50),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    ok = erlmcp_server_session:send_message(S, ListReq),
    ListResp = receive_response(),
    Tools = maps:get(<<"tools">>,
                     maps:get(<<"result">>, ListResp)),
    AskTool = hd([T || T <- Tools,
                       maps:get(<<"name">>, T) =:= <<"ask">>]),
    Meta = maps:get(<<"_meta">>, AskTool),
    PF = maps:get(<<"io.erlmcp/protocol_features">>, Meta),
    ?assertEqual([<<"sampling">>], PF),
    gen_statem:stop(S).
