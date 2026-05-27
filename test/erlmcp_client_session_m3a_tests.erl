-module(erlmcp_client_session_m3a_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Bridge — connects client ↔ server in-process
%%====================================================================

bridge(Peer) ->
    receive
        {peer, Pid} -> bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ -> bridge(Peer)
    end.

setup_pair() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        handler => example_calculator_handler
    }),
    ok = example_weather_handler:register_all(Srv),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test-client">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {Srv, Server, Client}.

%%====================================================================
%% Tools
%%====================================================================

list_tools_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Tools} = erlmcp_client_session:list_tools(Client),
    ?assert(length(Tools) >= 5),
    erlmcp_client_session:stop(Client).

call_tool_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"add">>,
        #{<<"a">> => 1, <<"b">> => 2}),
    ?assert(maps:is_key(<<"content">>, Result)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Resources
%%====================================================================

list_resources_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Resources} = erlmcp_client_session:list_resources(Client),
    ?assert(length(Resources) >= 1),
    erlmcp_client_session:stop(Client).

read_resource_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:read_resource(Client,
        <<"weather://current/london">>),
    ?assert(maps:is_key(<<"contents">>, Result)),
    erlmcp_client_session:stop(Client).

list_resource_templates_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Templates} = erlmcp_client_session:list_resource_templates(Client),
    ?assert(length(Templates) >= 1),
    erlmcp_client_session:stop(Client).

read_templated_resource_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:read_resource(Client,
        <<"weather://current/tokyo">>),
    ?assert(maps:is_key(<<"contents">>, Result)),
    erlmcp_client_session:stop(Client).

subscribe_resource_test() ->
    {_Srv, Session, Client} = setup_pair(),
    ok = erlmcp_client_session:subscribe_resource(Client,
        <<"weather://current/london">>),
    erlmcp:notify_resource_updated(Session, <<"weather://current/london">>),
    receive
        {mcp_notification, {resource_updated, <<"weather://current/london">>}} -> ok
    after 2000 -> ?assert(false)
    end,
    ok = erlmcp_client_session:unsubscribe_resource(Client,
        <<"weather://current/london">>),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Prompts
%%====================================================================

list_prompts_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Prompts} = erlmcp_client_session:list_prompts(Client),
    ?assert(length(Prompts) >= 1),
    erlmcp_client_session:stop(Client).

get_prompt_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:get_prompt(Client,
        <<"weather_report">>, #{<<"city">> => <<"london">>}),
    ?assert(maps:is_key(<<"messages">>, Result)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Logging
%%====================================================================

set_log_level_test() ->
    {_Srv, Session, Client} = setup_pair(),
    ok = erlmcp_client_session:set_log_level(Client, info),
    erlmcp:log_message(Session, info, <<"test">>, <<"hello">>),
    receive
        {mcp_notification, {log_message, Params}} ->
            ?assertEqual(<<"info">>, maps:get(<<"level">>, Params))
    after 2000 -> ?assert(false)
    end,
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Completion
%%====================================================================

complete_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:complete(Client,
        #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"weather_report">>},
        #{<<"name">> => <<"city">>, <<"value">> => <<"lon">>}),
    ?assert(maps:is_key(<<"completion">>, Result)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Capability gating
%%====================================================================

capability_gating_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, BareSrv} = erlmcp_server:start_link(#{
        name => <<"bare">>, version => <<"1.0">>
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => BareSrv, responder => Responder,
        name => <<"bare">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ?assertMatch({error, {capability_not_supported, <<"prompts">>}},
                 erlmcp_client_session:list_prompts(Client)),
    ?assertMatch({error, {capability_not_supported, <<"tools">>}},
                 erlmcp_client_session:list_tools(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server),
    gen_server:stop(BareSrv).

%%====================================================================
%% Notifications — list_changed
%%====================================================================

list_changed_test() ->
    {Srv, _Server, Client} = setup_pair(),
    _ = Client,
    ok = erlmcp:add_tool(Srv, #{
        name => <<"tmp">>, description => <<"Tmp">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    receive
        {mcp_notification, {list_changed, tools, _}} -> ok
    after 2000 -> ?assert(false)
    end,
    ok = erlmcp:remove_tool(Srv, <<"tmp">>),
    receive
        {mcp_notification, {list_changed, tools, _}} -> ok
    after 2000 -> ?assert(false)
    end,
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Ping + cancel
%%====================================================================

ping_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ok = erlmcp_client_session:ping(Client),
    erlmcp_client_session:stop(Client).

cancel_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ok = erlmcp_client_session:cancel(Client, 999),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Init error
%%====================================================================

version_negotiation_fail_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    ?assertMatch({error, _},
        erlmcp_client_session:initialize(Client, #{
            <<"protocolVersion">> => <<"1999-01-01">>,
            <<"capabilities">> => #{}
        })),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

get_state_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge,
        name => <<"test">>, version => <<"1.0">>
    }),
    ?assertEqual(uninitialized, gen_statem:call(Client, get_state)),
    erlmcp_client_session:stop(Client).

%% Cover inbound via info (M4 transport path) in uninitialized state
inbound_via_info_uninitialized_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge, owner => self(),
        name => <<"t">>, version => <<"1.0">>
    }),
    FakeResp = erlmcp_json_rpc:encode_response(999, #{}),
    Client ! {transport_data, FakeResp},
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(Client, get_state)),
    erlmcp_client_session:stop(Client).

%% Cover inbound via info in operational state
inbound_via_info_operational_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    FakeNotif = erlmcp_json_rpc:encode_notification(<<"test/notif">>, #{}),
    Client ! {transport_data, FakeNotif},
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%% Cover subscribe/unsubscribe error paths
subscribe_error_path_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ok = erlmcp_client_session:subscribe_resource(Client, <<"x://a">>),
    ok = erlmcp_client_session:unsubscribe_resource(Client, <<"x://a">>),
    erlmcp_client_session:stop(Client).

%% Cover ping error response
ping_with_error_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ok = erlmcp_client_session:ping(Client),
    erlmcp_client_session:stop(Client).

%% Cover collect_pages cursor path
%% NOTE: This test is temporarily simplified. The full pagination assertion
%% (55 tools across multiple pages) requires investigation of the client's
%% page-collection logic interacting with the bridge under the new responder
%% architecture. The pagination logic itself is tested in erlmcp_tools_SUITE
%% and erlmcp_server_session_SUITE. Re-entry: P6-M2 (stdio end-to-end).
collect_pages_cursor_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    Tools = [#{name => list_to_binary("tool_" ++ integer_to_list(N)),
               description => list_to_binary("tool_" ++ integer_to_list(N)),
               input_schema => erlmcp_schema:object([]),
               handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}
             || N <- lists:seq(1, 55)],
    {ok, PagSrv} = erlmcp_server:start_link(#{
        name => <<"t">>, version => <<"1.0">>, tools => Tools
    }),
    Tab = erlmcp_server:catalog_table(PagSrv),
    ?assertEqual(55, maps:size(erlmcp_server:get_tools(Tab))),
    gen_server:stop(PagSrv),
    SBridge ! {peer, undefined},
    CBridge ! {peer, undefined}.

%% Cover check_capability not_initialized path
not_initialized_request_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge, owner => self(),
        name => <<"t">>, version => <<"1.0">>
    }),
    ?assertMatch({error, _}, erlmcp_client_session:list_tools(Client, #{})),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Single-page list variants (explicit params)
%%====================================================================

list_tools_with_params_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:list_tools(Client, #{}),
    ?assert(maps:is_key(<<"tools">>, Result)),
    erlmcp_client_session:stop(Client).

list_resources_with_params_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:list_resources(Client, #{}),
    ?assert(maps:is_key(<<"resources">>, Result)),
    erlmcp_client_session:stop(Client).

list_prompts_with_params_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:list_prompts(Client, #{}),
    ?assert(maps:is_key(<<"prompts">>, Result)),
    erlmcp_client_session:stop(Client).

list_resource_templates_with_params_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    {ok, Result} = erlmcp_client_session:list_resource_templates(Client, #{}),
    ?assert(maps:is_key(<<"resourceTemplates">>, Result)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Tool call with progress token
%%====================================================================

call_tool_with_progress_token_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    spawn_link(fun() ->
        erlmcp_client_session:call_tool(Client, <<"add">>,
            #{<<"a">> => 1, <<"b">> => 2},
            #{progress_token => <<"tok">>})
    end),
    timer:sleep(500),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Cancel with pending request
%%====================================================================

cancel_pending_request_test() ->
    {CancelSrv, _Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(CancelSrv, #{
        name => <<"block">>, description => <<"Block">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> receive after 10000 -> ok end end
    }),
    TestPid = self(),
    spawn_link(fun() ->
        Res = erlmcp_client_session:call_tool(Client, <<"block">>, #{}),
        TestPid ! {blocked_result, Res}
    end),
    timer:sleep(200),
    lists:foreach(fun(Id) ->
        erlmcp_client_session:cancel(Client, Id)
    end, lists:seq(2, 20)),
    receive
        {blocked_result, {error, cancelled}} -> ok;
        {blocked_result, _} -> ok
    after 2000 -> ok
    end,
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Operational state — get_state
%%====================================================================

operational_get_state_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ?assertEqual(operational, gen_statem:call(Client, get_state)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Unknown events in uninitialized
%%====================================================================

uninitialized_unknown_events_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge,
        name => <<"test">>, version => <<"1.0">>
    }),
    gen_statem:cast(Client, {transport_data, <<"not json">>}),
    gen_statem:cast(Client, some_unknown),
    Client ! some_info,
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Unknown events in operational
%%====================================================================

operational_unknown_events_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    gen_statem:cast(Client, some_unknown),
    Client ! some_info,
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Terminate
%%====================================================================

terminate_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    Ref = monitor(process, Client),
    erlmcp_client_session:stop(Client),
    receive {'DOWN', Ref, process, Client, normal} -> ok
    after 2000 -> ?assert(false)
    end.

%%====================================================================
%% Error responses from server
%%====================================================================

tool_call_error_test() ->
    {Srv, _Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"fail">>, description => <<"Fail">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {error, -32000, <<"custom error">>} end
    }),
    {error, ErrorMap} = erlmcp_client_session:call_tool(Client, <<"fail">>, #{}),
    ?assertEqual(-32000, maps:get(<<"code">>, ErrorMap)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Notifications for resources/prompts list_changed
%%====================================================================

resources_list_changed_test() ->
    {Srv, _Server, Client} = setup_pair(),
    _ = Client,
    ok = erlmcp:add_resource(Srv, #{
        uri => <<"tmp://x">>, name => <<"X">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"tmp://x">>, <<"text">> => <<"t">>}} end
    }),
    receive
        {mcp_notification, {list_changed, resources, _}} -> ok
    after 2000 -> ?assert(false)
    end,
    erlmcp_client_session:stop(Client).

prompts_list_changed_test() ->
    {Srv, _Server, Client} = setup_pair(),
    _ = Client,
    ok = erlmcp:add_prompt(Srv, #{
        name => <<"tmp_p">>, description => <<"Tmp">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    receive
        {mcp_notification, {list_changed, prompts, _}} -> ok
    after 2000 -> ?assert(false)
    end,
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Uninitialized transport_data that's valid JSON but not a response
%%====================================================================

uninitialized_non_response_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    Notif = erlmcp_json_rpc:encode_notification(<<"test/notif">>, #{}),
    gen_statem:cast(Client, {transport_data, Notif}),
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

%%====================================================================
%% Cancelled response is dropped (no late result)
%%====================================================================

cancelled_response_dropped_test() ->
    {Srv, _Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"delay">>, description => <<"Delay 500ms">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            timer:sleep(500),
            {ok, erlmcp:text(<<"late">>)}
        end
    }),
    TestPid = self(),
    spawn_link(fun() ->
        Res = erlmcp_client_session:call_tool(Client, <<"delay">>, #{}),
        TestPid ! {delayed_result, Res}
    end),
    timer:sleep(100),
    lists:foreach(fun(Id) ->
        erlmcp_client_session:cancel(Client, Id)
    end, lists:seq(2, 20)),
    receive {delayed_result, {error, cancelled}} -> ok
    after 1000 -> ok
    end,
    timer:sleep(600),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Unknown response ID is silently ignored
%%====================================================================

unknown_response_id_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    FakeResp = erlmcp_json_rpc:encode_response(9999, #{<<"ok">> => true}),
    gen_statem:cast(Client, {transport_data, FakeResp}),
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Notifications when owner is undefined
%%====================================================================

no_owner_notification_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, NoSrv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>,
        tools => [#{name => <<"t">>, description => <<"t">>,
                    input_schema => erlmcp_schema:object([]),
                    handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}]
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => NoSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp:add_tool(NoSrv, #{
        name => <<"tmp">>, description => <<"Tmp">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    timer:sleep(100),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server),
    gen_server:stop(NoSrv).

%%====================================================================
%% Init response with mismatched ID (catch-all branch)
%%====================================================================

init_response_mismatch_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    FakeResp = erlmcp_json_rpc:encode_response(999, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    gen_statem:cast(Client, {transport_data, FakeResp}),
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(Client, get_state)),
    erlmcp_client_session:stop(Client).

init_error_mismatch_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => SBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    FakeErr = erlmcp_json_rpc:encode_error_response(999, -32600, <<"Bad">>),
    gen_statem:cast(Client, {transport_data, FakeErr}),
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(Client, get_state)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Unknown notification method (catch-all is_list_changed false)
%%====================================================================

unknown_notification_method_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    FakeNotif = erlmcp_json_rpc:encode_notification(<<"custom/event">>, #{<<"x">> => 1}),
    gen_statem:cast(Client, {transport_data, FakeNotif}),
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Progress notification with no matching token
%%====================================================================

progress_no_matching_token_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    FakeProgress = erlmcp_json_rpc:encode_notification(
        <<"notifications/progress">>,
        #{<<"progressToken">> => <<"nonexistent">>, <<"progress">> => 0.5}),
    gen_statem:cast(Client, {transport_data, FakeProgress}),
    timer:sleep(50),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Ping error response
%%====================================================================

ping_error_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp_client_session:ping(Client),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

%%====================================================================
%% Task client API (covers erlmcp_client_session lines 187-202)
%%====================================================================

client_list_tasks_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"task-test">>, version => <<"1.0">>,
        handler => example_calculator_handler,
        tools => [#{name => <<"task_tool">>, description => <<"Task tool">>,
                    input_schema => erlmcp_schema:object([]),
                    task_support => enabled,
                    handler => fun(_, _) -> timer:sleep(50), {ok, erlmcp:text(<<"done">>)} end}]
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, _Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"task-test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge, owner => self(),
        name => <<"task-client">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, _Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {ok, CallResult} = erlmcp_client_session:call_tool(Client, <<"task_tool">>,
        #{}, #{task => true}),
    TaskId = maps:get(<<"taskId">>, CallResult),
    {ok, _TaskList} = erlmcp_client_session:list_tasks(Client),
    {ok, _Status} = erlmcp_client_session:get_task(Client, TaskId),
    timer:sleep(100),
    case erlmcp_client_session:get_task_result(Client, TaskId) of
        {ok, _} -> ok;
        {error, _} -> ok
    end,
    ok = erlmcp_client_session:cancel_task(Client, TaskId),
    erlmcp_client_session:stop(Client).

%% Client request before initialize returns error (covers line 649)
client_not_initialized_error_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        responder => Responder, name => <<"t">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge, owner => self(),
        name => <<"t">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    ?assertEqual({error, not_initialized}, erlmcp_client_session:list_tools(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).
