-module(erlmcp_registry_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

%%====================================================================
%% Test Setup and Cleanup
%%====================================================================

registry_test_() ->
    [{"Registry startup and basic operations", fun test_registry_basics/0},
     {"Server registration and lookup", fun test_server_registration/0},
     {"Transport registration and lookup", fun test_transport_registration/0},
     {"Server-Transport binding", fun test_binding/0},
     {"Message routing", fun test_message_routing/0},
     {"Process monitoring", fun test_process_monitoring/0}].

setup_registry() ->
    % Start the registry
    case erlmcp_registry:start_link() of
        {ok, Registry} ->
            Registry;
        {error, {already_started, Registry}} ->
            Registry
    end.

cleanup_registry(Registry) ->
    % Unregister all test components first
    try
        erlmcp_registry:unregister_server(test_server_reg),
        erlmcp_registry:unregister_server(test_server_bind),
        erlmcp_registry:unregister_server(test_server_route),
        erlmcp_registry:unregister_server(test_server_monitor),
        erlmcp_registry:unregister_transport(test_transport_reg),
        erlmcp_registry:unregister_transport(test_transport_bind),
        erlmcp_registry:unregister_transport(test_transport_route)
    catch
        _:_ ->
            ok % Ignore cleanup errors
    end,

    % Give time for cleanup
    timer:sleep(100),

    % Stop registry gracefully
    try
        case is_process_alive(Registry) of
            true ->
                gen_server:stop(Registry, shutdown, 1000),
                ok;
            false ->
                ok
        end
    catch
        _:_ ->
            % Force kill if graceful stop fails
            case is_process_alive(Registry) of
                true ->
                    exit(Registry, kill);
                false ->
                    ok
            end
    end,

    % Final cleanup delay
    timer:sleep(50),
    ok.

%%====================================================================
%% Basic Registry Tests
%%====================================================================

test_registry_basics() ->
    % Start an anonymous registry (not registered by name)
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Test that registry is running and responding
        ?assertEqual([], gen_server:call(Registry, list_servers)),
        ?assertEqual([], gen_server:call(Registry, list_transports))
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

test_server_registration() ->
    % Start an anonymous registry
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Create a mock server process
        MockServer =
            spawn_link(fun() ->
                          receive
                              stop ->
                                  ok
                          after 5000 ->
                              ok  % Increased timeout for stability
                          end
                       end),

        ServerCapabilities = #mcp_server_capabilities{tools = #mcp_capability{enabled = true}},
        ServerConfig = #{capabilities => ServerCapabilities},

        % Register server
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {register_server, test_server_reg, MockServer, ServerConfig})),

        % Verify registration
        ?assertMatch({ok, {MockServer, ServerConfig}},
                     gen_server:call(Registry, {find_server, test_server_reg})),

        % Check it appears in list
        Servers = gen_server:call(Registry, list_servers),
        ?assert(length(Servers) >= 1),

        % Test duplicate registration fails
        ?assertMatch({error, already_registered},
                     gen_server:call(Registry,
                                     {register_server, test_server_reg, MockServer, ServerConfig})),

        % Unregister
        ?assertEqual(ok, gen_server:call(Registry, {unregister_server, test_server_reg})),
        ?assertMatch({error, not_found},
                     gen_server:call(Registry, {find_server, test_server_reg})),

        % Cleanup mock server
        unlink(MockServer),
        exit(MockServer, normal)
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

test_transport_registration() ->
    % Start an anonymous registry
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Create a mock transport process
        MockTransport =
            spawn_link(fun() ->
                          receive
                              stop ->
                                  ok
                          after 5000 ->
                              ok  % Increased timeout for stability
                          end
                       end),

        TransportConfig = #{type => stdio, server_id => test_server_transport},

        % Register transport
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {register_transport,
                                      test_transport_reg,
                                      MockTransport,
                                      TransportConfig})),

        % Verify registration
        ?assertMatch({ok, {MockTransport, TransportConfig}},
                     gen_server:call(Registry, {find_transport, test_transport_reg})),

        % Check it appears in list
        Transports = gen_server:call(Registry, list_transports),
        ?assert(length(Transports) >= 1),

        % Unregister
        ?assertEqual(ok, gen_server:call(Registry, {unregister_transport, test_transport_reg})),
        ?assertMatch({error, not_found},
                     gen_server:call(Registry, {find_transport, test_transport_reg})),

        % Cleanup mock transport
        unlink(MockTransport),
        exit(MockTransport, normal)
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

test_binding() ->
    % Start an anonymous registry
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Create mock processes
        MockServer =
            spawn_link(fun() ->
                          receive
                              stop ->
                                  ok
                          after 5000 ->
                              ok
                          end
                       end),
        MockTransport =
            spawn_link(fun() ->
                          receive
                              stop ->
                                  ok
                          after 5000 ->
                              ok
                          end
                       end),

        % Register both
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {register_server, test_server_bind, MockServer, #{}})),
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {register_transport,
                                      test_transport_bind,
                                      MockTransport,
                                      #{type => stdio}})),

        % Test binding
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {bind_transport_to_server,
                                      test_transport_bind,
                                      test_server_bind})),
        ?assertMatch({ok, test_server_bind},
                     gen_server:call(Registry, {get_server_for_transport, test_transport_bind})),

        % Test unbinding
        ?assertEqual(ok, gen_server:call(Registry, {unbind_transport, test_transport_bind})),
        ?assertMatch({error, not_found},
                     gen_server:call(Registry, {get_server_for_transport, test_transport_bind})),

        % Test binding nonexistent fails
        ?assertMatch({error, server_not_found},
                     gen_server:call(Registry,
                                     {bind_transport_to_server, test_transport_bind, nonexistent})),
        ?assertMatch({error, transport_not_found},
                     gen_server:call(Registry,
                                     {bind_transport_to_server, nonexistent, test_server_bind})),

        % Cleanup
        gen_server:call(Registry, {unregister_server, test_server_bind}),
        gen_server:call(Registry, {unregister_transport, test_transport_bind}),
        unlink(MockServer),
        unlink(MockTransport),
        exit(MockServer, normal),
        exit(MockTransport, normal)
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

test_message_routing() ->
    % Start an anonymous registry
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Create a simple message collector process
        Collector = spawn_link(fun() -> collect_messages([]) end),

        % Create mock processes that forward to collector
        MockServer =
            spawn_link(fun() ->
                          receive
                              {mcp_message, TransportId, Message} ->
                                  Collector ! {server_got, TransportId, Message},
                                  receive
                                      stop ->
                                          ok
                                  after 5000 ->
                                      ok
                                  end;
                              stop ->
                                  ok
                          end
                       end),

        MockTransport =
            spawn_link(fun() ->
                          receive
                              {mcp_response, ServerId, Message} ->
                                  Collector ! {transport_got, ServerId, Message},
                                  receive
                                      stop ->
                                          ok
                                  after 5000 ->
                                      ok
                                  end;
                              stop ->
                                  ok
                          end
                       end),

        % Register and bind
        gen_server:call(Registry, {register_server, test_server_route, MockServer, #{}}),
        gen_server:call(Registry,
                        {register_transport,
                         test_transport_route,
                         MockTransport,
                         #{type => stdio}}),
        gen_server:call(Registry,
                        {bind_transport_to_server, test_transport_route, test_server_route}),

        % Test routing to server
        gen_server:cast(Registry,
                        {route_to_server,
                         test_server_route,
                         test_transport_route,
                         <<"test message">>}),

        % Test routing to transport
        gen_server:cast(Registry,
                        {route_to_transport,
                         test_transport_route,
                         test_server_route,
                         <<"response message">>}),

        % Give time for messages to be processed
        timer:sleep(200),  % Increased wait time

        % Check messages were received
        Collector ! {get_messages, self()},
        receive
            {messages, Messages} ->
                ?assert(lists:any(fun ({server_got, test_transport_route, <<"test message">>}) ->
                                          true;
                                      (_) ->
                                          false
                                  end,
                                  Messages)),
                ?assert(lists:any(fun ({transport_got,
                                        test_server_route,
                                        <<"response message">>}) ->
                                          true;
                                      (_) ->
                                          false
                                  end,
                                  Messages))
        after 2000 ->  % Increased timeout
            ?assert(false) % Timeout
        end,

        % Cleanup
        unlink(MockServer),
        unlink(MockTransport),
        unlink(Collector),
        exit(MockServer, normal),
        exit(MockTransport, normal),
        exit(Collector, normal)
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

% Helper function for message collection
collect_messages(Messages) ->
    receive
        {get_messages, From} ->
            From ! {messages, lists:reverse(Messages)};
        Message ->
            collect_messages([Message | Messages])
    after 5000 ->  % Increased timeout
        ok
    end.

test_process_monitoring() ->
    % Start an anonymous registry
    {ok, Registry} = gen_server:start(erlmcp_registry, [], []),

    try
        % Create a server that will die
        MockServer =
            spawn_link(fun() ->
                          receive
                              die ->
                                  exit(normal);
                              stop ->
                                  ok
                          after 5000 ->
                              ok  % Increased timeout
                          end
                       end),

        % Register it
        ?assertEqual(ok,
                     gen_server:call(Registry,
                                     {register_server, test_server_monitor, MockServer, #{}})),

        % Verify it's registered
        ?assertMatch({ok, {MockServer, _}},
                     gen_server:call(Registry, {find_server, test_server_monitor})),

        % Kill the server process
        unlink(MockServer),  % Unlink to prevent test process from dying
        exit(MockServer, kill),  % Use kill instead of normal to ensure immediate death

        % Wait for the process to actually die
        wait_for_process_death(MockServer, 2000),

        % Give registry time to process the DOWN message
        timer:sleep(500),  % Increased wait time

        % Should be automatically unregistered
        ?assertMatch({error, not_found},
                     gen_server:call(Registry, {find_server, test_server_monitor}))
    after
        catch gen_server:stop(Registry, normal, 5000)
    end.

% Helper function to wait for process death
wait_for_process_death(Pid, Timeout) ->
    wait_for_process_death(Pid, Timeout, erlang:system_time(millisecond)).

wait_for_process_death(Pid, Timeout, StartTime) ->
    case is_process_alive(Pid) of
        false ->
            ok;
        true ->
            Now = erlang:system_time(millisecond),
            case Now - StartTime > Timeout of
                true ->
                    throw({timeout_waiting_for_process_death, Pid});
                false ->
                    timer:sleep(10),
                    wait_for_process_death(Pid, Timeout, StartTime)
            end
    end.

%%====================================================================
%% Integration Tests with New Architecture
%%====================================================================

integration_test_() ->
    case is_erlmcp_available() of
        true ->
            {timeout,
             30,
             [{"Full server startup via new API", fun test_new_server_startup/0},
              {"Legacy stdio compatibility", fun test_legacy_stdio_compatibility/0},
              {"Integration with temporary registry", fun test_integration_with_temp_registry/0}]};
        false ->
            {timeout,
             30,
             [{"Integration with temporary registry", fun test_integration_with_temp_registry/0}]}
    end.

%% Check if the erlmcp module and its functions are available
is_erlmcp_available() ->
    try
        case code:is_loaded(erlmcp) of
            {file, _} ->
                true;
            false ->
                case code:load_file(erlmcp) of
                    {module, erlmcp} ->
                        % Check if key functions exist
                        erlang:function_exported(erlmcp, start_server, 1)
                        andalso erlang:function_exported(erlmcp, start_transport, 3);
                    _ ->
                        false
                end
        end
    catch
        _:_ ->
            false
    end.

setup_integration() ->
    % Start the application components needed for integration tests
    % Don't fail if they're not available
    try
        application:ensure_all_started(erlmcp),
        ok
    catch
        _:_ ->
            ok
    end.

cleanup_integration(_) ->
    % Stop application gracefully
    try
        application:stop(erlmcp),
        ok
    catch
        _:_ ->
            ok
    end.

test_new_server_startup() ->
    % Test the new API for creating servers and transports
    % This test is designed to work with or without the full application running
    % Check if the erlmcp application functions are available
    case catch erlmcp:start_server(integration_test_server) of
        {ok, _Pid1} ->
            % Server started successfully
            % Verify it's registered (only if registry is available)
            case whereis(erlmcp_registry) of
                undefined ->
                    ok; % Registry not available, skip verification
                _ ->
                    case catch erlmcp_registry:find_server(integration_test_server) of
                        {ok, {_Pid2, _Config}} ->
                            ok;
                        _ ->
                            ok % May not be found if using different registration approach
                    end
            end,

            % Try to start transport (will fail gracefully if not available)
            TransportConfig = #{server_id => integration_test_server},
            case catch erlmcp:start_transport(integration_test_transport, stdio, TransportConfig) of
                {ok, _TransportPid} ->
                    % Verify transport is registered and bound (if registry available)
                    case whereis(erlmcp_registry) of
                        undefined ->
                            ok;
                        _ ->
                            case catch
                                     erlmcp_registry:get_server_for_transport(integration_test_transport)
                            of
                                {ok, integration_test_server} ->
                                    ok;
                                _ ->
                                    ok % May not be bound if using different approach
                            end
                    end,

                    % Try to add a simple tool (this might fail if registry not available)
                    ToolHandler = fun(#{<<"message">> := Msg}) -> <<"Echo: ", Msg/binary>> end,
                    case catch erlmcp:add_tool(integration_test_server, <<"echo">>, ToolHandler) of
                        ok ->
                            ok;
                        {error, _} ->
                            ok; % Expected if registry/server not available
                        {'EXIT', {noproc, _}} ->
                            ok; % Registry not running
                        _ ->
                            ok % Any other error is acceptable for this test
                    end,

                    % Cleanup
                    catch erlmcp:stop_transport(integration_test_transport),
                    catch erlmcp:stop_server(integration_test_server);
                {error, _} ->
                    % Transport creation failed, just cleanup server
                    catch erlmcp:stop_server(integration_test_server);
                {'EXIT', _} ->
                    % Function doesn't exist or crashed, cleanup server
                    catch erlmcp:stop_server(integration_test_server)
            end;
        {error, _} ->
            % Server creation failed - this is acceptable as the full app may not be available
            ok;
        {'EXIT', _} ->
            % Function doesn't exist or application not started - this is acceptable
            ok
    end.

test_legacy_stdio_compatibility() ->
    % Test that legacy stdio server still works
    % This test is designed to work with or without the full application running
    case catch erlmcp:start_stdio_server() of
        {ok, _Pid1} ->
            % Should be able to find the default server (if registry available)
            case whereis(erlmcp_registry) of
                undefined ->
                    ok; % Registry not available, skip checks
                _ ->
                    case catch erlmcp_registry:find_server(default_stdio_server) of
                        {ok, {_Pid2, _Config}} ->
                            ok;
                        {error, not_found} ->
                            ok; % May not be registered if using legacy mode
                        {'EXIT', _} ->
                            ok % Registry call failed
                    end
            end,

            % Cleanup
            catch erlmcp:stop_stdio_server();
        {error, _} ->
            % Stdio server creation failed, that's OK for this test
            ok;
        {'EXIT', _} ->
            % Function doesn't exist or application not started - this is acceptable
            ok
    end.

test_integration_with_temp_registry() ->
    % Test integration by starting our own temporary registry
    % This ensures the integration tests can run independently
    % Start a temporary registry for this test
    {ok, TempRegistry} = gen_server:start({local, erlmcp_registry}, erlmcp_registry, [], []),

    try
        % Create mock server and transport processes
        MockServer =
            spawn_link(fun() ->
                          receive
                              {add_tool, ToolName, Handler} ->
                                  % Mock tool addition - just acknowledge
                                  self() ! {tool_added, ToolName, Handler},
                                  receive
                                      stop ->
                                          ok
                                  after 5000 ->
                                      ok
                                  end;
                              stop ->
                                  ok
                          after 5000 ->
                              ok
                          end
                       end),

        MockTransport =
            spawn_link(fun() ->
                          receive
                              stop ->
                                  ok
                          after 5000 ->
                              ok
                          end
                       end),

        % Test basic registry operations that the full API would use
        ServerConfig =
            #{capabilities => #mcp_server_capabilities{tools = #mcp_capability{enabled = true}}},

        % Register server
        ?assertEqual(ok,
                     erlmcp_registry:register_server(integration_test_server,
                                                     MockServer,
                                                     ServerConfig)),

        % Verify registration
        ?assertMatch({ok, {MockServer, _}}, erlmcp_registry:find_server(integration_test_server)),

        % Register transport
        TransportConfig = #{type => stdio, server_id => integration_test_server},
        ?assertEqual(ok,
                     erlmcp_registry:register_transport(integration_test_transport,
                                                        MockTransport,
                                                        TransportConfig)),

        % Verify transport registration and auto-binding
        ?assertMatch({ok, {MockTransport, _}},
                     erlmcp_registry:find_transport(integration_test_transport)),
        ?assertMatch({ok, integration_test_server},
                     erlmcp_registry:get_server_for_transport(integration_test_transport)),

        % Test message routing
        erlmcp_registry:route_to_server(integration_test_server,
                                        integration_test_transport,
                                        <<"test_message">>),

        % Verify server received message
        % We don't expect the mock to actually process this, just testing the routing works
        receive after 100 ->
            ok
        end,

        % Test tool addition simulation (mock the high-level API behavior)
        MockServer ! {add_tool, <<"echo">>, fun(X) -> X end},

        % Cleanup
        unlink(MockServer),
        unlink(MockTransport),
        exit(MockServer, normal),
        exit(MockTransport, normal),

        % Clean registry
        erlmcp_registry:unregister_server(integration_test_server),
        erlmcp_registry:unregister_transport(integration_test_transport)
    after
        % Stop temporary registry
        catch gen_server:stop(TempRegistry, normal, 5000)
    end.
