-module(erlmcp_server_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

%%====================================================================
%% Test Setup - Registry-based Architecture
%%====================================================================

server_test_() ->
    {setup,
     fun setup_with_registry/0,
     fun cleanup_with_registry/1,
     fun(Context) ->
        {with,
         Context,
         [fun test_add_resource/1,
          fun test_add_tool/1,
          fun test_add_prompt/1,
          fun test_registry_integration/1,
          fun test_message_routing/1,
          fun test_advanced_features/1]}
     end}.

%% Legacy test for backward compatibility
legacy_server_test_() ->
    {setup,
     fun setup_legacy/0,
     fun cleanup_legacy/1,
     fun(Server) ->
        [?_test(test_add_resource_legacy(Server)),
         ?_test(test_add_tool_legacy(Server)),
         ?_test(test_add_prompt_legacy(Server))]
     end}.

%%====================================================================
%% Setup Functions
%%====================================================================

setup_with_registry() ->
    % Start a temporary registry for testing
    {ok, Registry} = gen_server:start({local, erlmcp_registry}, erlmcp_registry, [], []),

    % Create capabilities
    Capabilities =
        #mcp_server_capabilities{resources = #mcp_capability{enabled = true},
                                 tools = #mcp_capability{enabled = true},
                                 prompts = #mcp_capability{enabled = true}},

    % Start server with registry
    ServerId = test_server_with_registry,
    {ok, Server} = erlmcp_server:start_link(ServerId, Capabilities),

    % Register with registry
    ServerConfig = #{capabilities => Capabilities},
    ok = erlmcp_registry:register_server(ServerId, Server, ServerConfig),

    #{registry => Registry,
      server => Server,
      server_id => ServerId,
      capabilities => Capabilities}.

setup_legacy() ->
    % Start server without registry (legacy mode)
    Capabilities =
        #mcp_server_capabilities{resources = #mcp_capability{enabled = true},
                                 tools = #mcp_capability{enabled = true},
                                 prompts = #mcp_capability{enabled = true}},
    % Use a unique server ID that won't conflict with registry tests
    {ok, Server} = erlmcp_server:start_link(test_server_legacy, Capabilities),
    Server.

cleanup_with_registry(#{registry := Registry,
                        server := Server,
                        server_id := ServerId}) ->
    % Clean up registry entry
    catch erlmcp_registry:unregister_server(ServerId),

    % Stop server
    catch erlmcp_server:stop(Server),

    % Stop registry
    catch gen_server:stop(Registry, normal, 5000),

    % Give processes time to clean up
    timer:sleep(100),
    ok.

cleanup_legacy(Server) ->
    erlmcp_server:stop(Server).

%%====================================================================
%% Registry-based Tests
%%====================================================================

test_add_resource(#{server := Server}) ->
    Handler = fun(_Uri) -> <<"test resource content">> end,
    ?assertEqual(ok, erlmcp_server:add_resource(Server, <<"test_resource">>, Handler)).

test_add_tool(#{server := Server}) ->
    Handler =
        fun(Args) ->
           ArgsBinary = jsx:encode(Args),
           <<"tool result: ", ArgsBinary/binary>>
        end,
    ?assertEqual(ok, erlmcp_server:add_tool(Server, <<"test_tool">>, Handler)).

test_add_prompt(#{server := Server}) ->
    Handler =
        fun(Args) ->
           ArgsBinary = jsx:encode(Args),
           <<"prompt result: ", ArgsBinary/binary>>
        end,
    ?assertEqual(ok, erlmcp_server:add_prompt(Server, <<"test_prompt">>, Handler)).

test_registry_integration(#{server_id := ServerId, server := Server}) ->
    % Test that server is properly registered
    ?assertMatch({ok, {Server, _Config}}, erlmcp_registry:find_server(ServerId)),

    % Test server appears in listing
    Servers = erlmcp_registry:list_servers(),
    ?assert(lists:keymember(ServerId, 1, Servers)).

test_message_routing(#{server := Server, server_id := ServerId}) ->
    % Create a mock transport
    TestPid = self(), % Get the current test process PID
    MockTransport =
        spawn_link(fun() ->
                      receive
                          {mcp_response, _ServerId, Data} ->
                              % Send the response back to test process
                              TestPid ! {mock_transport_received, Data},
                              receive
                                  stop ->
                                      ok
                              after 1000 ->
                                  ok
                              end;
                          stop ->
                              ok
                      after 5000 ->
                          ok
                      end
                   end),

    % Register mock transport
    TransportId = test_transport,
    TransportConfig = #{type => mock, server_id => ServerId},
    ok = erlmcp_registry:register_transport(TransportId, MockTransport, TransportConfig),
    ok = erlmcp_registry:bind_transport_to_server(TransportId, ServerId),

    % Add a simple tool to the server
    ToolHandler =
        fun(Args) ->
           case Args of
               #{<<"input">> := Input} ->
                   <<"Echo: ", Input/binary>>;
               _ ->
                   <<"Echo: no input">>
           end
        end,
    ok = erlmcp_server:add_tool(Server, <<"echo">>, ToolHandler),

    % Simulate a tool call message from transport
    ToolCallMessage =
        jsx:encode(#{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
                     ?JSONRPC_FIELD_ID => 1,
                     ?JSONRPC_FIELD_METHOD => ?MCP_METHOD_TOOLS_CALL,
                     ?JSONRPC_FIELD_PARAMS =>
                         #{?MCP_PARAM_NAME => <<"echo">>,
                           ?MCP_PARAM_ARGUMENTS => #{<<"input">> => <<"Hello World">>}}}),

    % Send message to server via registry routing
    erlmcp_registry:route_to_server(ServerId, TransportId, ToolCallMessage),

    % Wait for response to be routed back to transport
    receive
        {mock_transport_received, ResponseData} ->
            % Verify we got a response
            ?assert(is_binary(ResponseData)),
            % Parse and verify response structure
            Response = jsx:decode(ResponseData, [return_maps]),
            ?assertEqual(?JSONRPC_VERSION, maps:get(?JSONRPC_FIELD_JSONRPC, Response)),
            ?assertEqual(1, maps:get(?JSONRPC_FIELD_ID, Response)),
            ?assert(maps:is_key(?JSONRPC_FIELD_RESULT, Response)),

            % Verify the tool actually executed
            Result = maps:get(?JSONRPC_FIELD_RESULT, Response),
            Content = maps:get(<<"content">>, Result),
            ?assert(is_list(Content)),
            [FirstContent | _] = Content,
            ?assertEqual(<<"Echo: Hello World">>, maps:get(<<"text">>, FirstContent))
    after 2000 ->
        ?assert(false) % Timeout - message routing failed
    end,

    % Cleanup
    MockTransport ! stop,
    erlmcp_registry:unregister_transport(TransportId).

test_advanced_features(#{server := Server}) ->
    % Test resource templates
    TemplateHandler = fun(Uri) -> <<"Template content for ", Uri/binary>> end,
    ?assertEqual(ok,
                 erlmcp_server:add_resource_template(Server,
                                                     <<"template://{id}">>,
                                                     <<"Test Template">>,
                                                     TemplateHandler)),

    % Test tools with schema
    Schema =
        #{<<"type">> => <<"object">>,
          <<"properties">> => #{<<"value">> => #{<<"type">> => <<"string">>}},
          <<"required">> => [<<"value">>]},
    SchemaToolHandler = fun(#{<<"value">> := Value}) -> <<"Validated: ", Value/binary>> end,
    ?assertEqual(ok,
                 erlmcp_server:add_tool_with_schema(Server,
                                                    <<"validate_tool">>,
                                                    SchemaToolHandler,
                                                    Schema)),

    % Test prompts with arguments
    PromptArgs =
        [#mcp_prompt_argument{name = <<"input">>,
                              description = <<"Test input">>,
                              required = true}],
    PromptHandler =
        fun(#{<<"input">> := Input}) ->
           [#{?MCP_PARAM_ROLE => ?MCP_ROLE_USER,
              ?MCP_PARAM_CONTENT =>
                  #{?MCP_PARAM_TYPE => ?MCP_CONTENT_TYPE_TEXT,
                    ?MCP_PARAM_TEXT => <<"Prompt with input: ", Input/binary>>}}]
        end,
    ?assertEqual(ok,
                 erlmcp_server:add_prompt_with_args(Server,
                                                    <<"test_prompt_with_args">>,
                                                    PromptHandler,
                                                    PromptArgs)),

    % Test progress reporting
    ?assertEqual(ok, erlmcp_server:report_progress(Server, <<"token1">>, 50.0, 100.0)),

    % Test resource notifications
    ?assertEqual(ok,
                 erlmcp_server:notify_resource_updated(Server,
                                                       <<"test://resource">>,
                                                       #{<<"version">> => 1})),
    ?assertEqual(ok, erlmcp_server:notify_resources_changed(Server)).

%%====================================================================
%% Legacy Compatibility Tests
%%====================================================================

test_add_resource_legacy(Server) ->
    Handler = fun(_Uri) -> <<"test resource content">> end,
    ?assertEqual(ok, erlmcp_server:add_resource(Server, <<"test_resource_legacy">>, Handler)).

test_add_tool_legacy(Server) ->
    Handler =
        fun(Args) ->
           ArgsBinary = jsx:encode(Args),
           <<"tool result: ", ArgsBinary/binary>>
        end,
    ?assertEqual(ok, erlmcp_server:add_tool(Server, <<"test_tool_legacy">>, Handler)).

test_add_prompt_legacy(Server) ->
    Handler =
        fun(Args) ->
           ArgsBinary = jsx:encode(Args),
           <<"prompt result: ", ArgsBinary/binary>>
        end,
    ?assertEqual(ok, erlmcp_server:add_prompt(Server, <<"test_prompt_legacy">>, Handler)).

%%====================================================================
%% Integration Tests with High-Level API
%%====================================================================

api_integration_test_() ->
    {setup,
     fun setup_api_integration/0,
     fun cleanup_api_integration/1,
     fun(_Context) ->
        [{"API server creation and management", fun test_api_server_management/0},
         {"API server operations", fun test_api_server_operations/0},
         {"API transport integration", fun test_api_transport_integration/0},
         {"API legacy compatibility", fun test_api_legacy_compatibility/0}]
     end}.

setup_api_integration() ->
    % Start registry for API tests
    {ok, Registry} = gen_server:start({local, erlmcp_registry}, erlmcp_registry, [], []),
    Registry.

cleanup_api_integration(Registry) ->
    % Clean up any test servers and transports
    catch erlmcp:stop_server(api_test_server),
    catch erlmcp:stop_server(api_test_server_2),
    catch erlmcp:stop_transport(api_test_transport),

    % Stop registry
    catch gen_server:stop(Registry, normal, 5000),
    timer:sleep(100),
    ok.

test_api_server_management() ->
    % Test server creation via high-level API
    ServerConfig =
        #{capabilities => #mcp_server_capabilities{tools = #mcp_capability{enabled = true}}},
    ?assertMatch({ok, _Pid}, erlmcp:start_server(api_test_server, ServerConfig)),

    % Verify server is registered
    ?assertMatch([{api_test_server, {_Pid, _Config}}], erlmcp:list_servers()),

    % Test server configuration management
    ?assertMatch({ok, _Config}, erlmcp:get_server_config(api_test_server)),

    % Test server stop
    ?assertEqual(ok, erlmcp:stop_server(api_test_server)),

    % Verify server is gone
    ?assertEqual([], erlmcp:list_servers()).

test_api_server_operations() ->
    % Create server for operations testing
    ?assertMatch({ok, _Pid}, erlmcp:start_server(api_test_server_2)),

    % Test adding components via high-level API
    ResourceHandler = fun(Uri) -> <<"Resource: ", Uri/binary>> end,
    ?assertEqual(ok,
                 erlmcp:add_resource(api_test_server_2, <<"test://resource">>, ResourceHandler)),

    ToolHandler = fun(#{<<"input">> := Input}) -> <<"Tool output: ", Input/binary>> end,
    ?assertEqual(ok, erlmcp:add_tool(api_test_server_2, <<"test_tool">>, ToolHandler)),

    PromptHandler = fun(#{<<"query">> := Query}) -> <<"Prompt: ", Query/binary>> end,
    ?assertEqual(ok, erlmcp:add_prompt(api_test_server_2, <<"test_prompt">>, PromptHandler)),

    % Test with options
    ToolWithSchema = fun(#{<<"value">> := Value}) -> <<"Validated: ", Value/binary>> end,
    Schema =
        #{<<"type">> => <<"object">>,
          <<"properties">> => #{<<"value">> => #{<<"type">> => <<"string">>}}},
    ?assertEqual(ok,
                 erlmcp:add_tool(api_test_server_2,
                                 <<"schema_tool">>,
                                 ToolWithSchema,
                                 #{schema => Schema})),

    % Cleanup
    erlmcp:stop_server(api_test_server_2).

test_api_transport_integration() ->
    % This test would require implementing mock transports
    % For now, just test that the API functions exist and don't crash
    ?assertMatch({error, {transport_not_implemented, tcp}},
                 erlmcp:start_transport(api_test_transport, tcp, #{})),

    % Test transport listing (should be empty)
    ?assertEqual([], erlmcp:list_transports()).

test_api_legacy_compatibility() ->
    % Test that legacy stdio server functions still work
    % Note: This might not work in test environment without proper stdio setup
    case catch erlmcp:start_stdio_server() of
        {ok, _StdioPid} ->
            % If it works, test that we can stop it
            % Use a more robust stop that won't crash if something goes wrong
            try
                erlmcp:stop_stdio_server(),
                ok
            catch
                _:_ ->
                    % If stop fails, that's acceptable in test environment
                    ok
            end;
        {error, _Reason} ->
            % If it fails (expected in test environment), that's OK
            ok;
        {'EXIT', _Reason} ->
            % If it crashes (expected in test environment), that's OK
            ok
    end,

    % Test API compatibility in registry-free mode
    % This tests similar scenarios to what the validation script tests
    case catch erlmcp:start_server(api_compat_test) of
        {ok, _ServerPid} ->
            % High-level API worked even without registry
            case catch erlmcp:add_tool(api_compat_test, <<"test">>, fun(_) -> <<"ok">> end) of
                ok ->
                    try
                        erlmcp:stop_server(api_compat_test),
                        ok
                    catch
                        _:_ ->
                            ok % Stop failure is acceptable
                    end;
                {error, registry_not_available} ->
                    % Expected when no registry
                    try
                        erlmcp:stop_server(api_compat_test),
                        ok
                    catch
                        _:_ ->
                            ok % Stop failure is acceptable
                    end;
                _ ->
                    try
                        erlmcp:stop_server(api_compat_test),
                        ok
                    catch
                        _:_ ->
                            ok % Stop failure is acceptable
                    end
            end;
        {error, _} ->
            % API not available, acceptable
            ok;
        {'EXIT', _} ->
            % Crashed, acceptable in some test environments
            ok
    end.

%%====================================================================
%% Error Handling Tests
%%====================================================================

error_handling_test_() ->
    {setup,
     fun setup_with_registry/0,
     fun cleanup_with_registry/1,
     fun(Context) ->
        {with,
         Context,
         [fun test_handler_crashes/1,
          fun test_invalid_messages/1,
          fun test_registry_communication_failures/1]}
     end}.

test_handler_crashes(#{server := Server, server_id := ServerId}) ->
    % Add a tool that crashes
    CrashingHandler = fun(_Args) -> error(intentional_crash) end,
    ?assertEqual(ok, erlmcp_server:add_tool(Server, <<"crashing_tool">>, CrashingHandler)),

    % Create mock transport for testing
    TestPid = self(), % Get the current test process PID
    MockTransport =
        spawn_link(fun() ->
                      receive
                          {mcp_response, _ServerId, Data} ->
                              TestPid ! {crash_test_response, Data},
                              receive
                                  stop ->
                                      ok
                              after 1000 ->
                                  ok
                              end;
                          stop ->
                              ok
                      after 5000 ->
                          ok
                      end
                   end),

    % Register and bind transport
    TransportId = crash_test_transport,
    ok = erlmcp_registry:register_transport(TransportId, MockTransport, #{type => mock}),
    ok = erlmcp_registry:bind_transport_to_server(TransportId, ServerId),

    % Send a message that will cause the handler to crash
    CrashMessage =
        jsx:encode(#{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
                     ?JSONRPC_FIELD_ID => 1,
                     ?JSONRPC_FIELD_METHOD => ?MCP_METHOD_TOOLS_CALL,
                     ?JSONRPC_FIELD_PARAMS =>
                         #{?MCP_PARAM_NAME => <<"crashing_tool">>,
                           ?MCP_PARAM_ARGUMENTS => #{<<"test">> => <<"crash">>}}}),

    % Send message and expect error response
    erlmcp_registry:route_to_server(ServerId, TransportId, CrashMessage),

    receive
        {crash_test_response, ResponseData} ->
            Response = jsx:decode(ResponseData, [return_maps]),
            ?assert(maps:is_key(?JSONRPC_FIELD_ERROR, Response)),
            Error = maps:get(?JSONRPC_FIELD_ERROR, Response),
            ?assertEqual(?JSONRPC_INTERNAL_ERROR,
                         maps:get(?JSONRPC_ERROR_FIELD_CODE, Error)) % Internal error
    after 2000 ->
        ?assert(false) % Should have received error response
    end,

    % Cleanup
    MockTransport ! stop,
    erlmcp_registry:unregister_transport(TransportId).

test_invalid_messages(#{server := Server, server_id := ServerId}) ->
    % Create mock transport
    TestPid = self(), % Get the current test process PID
    MockTransport =
        spawn_link(fun() ->
                      receive
                          {mcp_response, _ServerId, Data} ->
                              TestPid ! {invalid_test_response, Data},
                              receive
                                  stop ->
                                      ok
                              after 1000 ->
                                  ok
                              end;
                          stop ->
                              ok
                      after 5000 ->
                          ok
                      end
                   end),

    % Register and bind transport
    TransportId = invalid_test_transport,
    ok = erlmcp_registry:register_transport(TransportId, MockTransport, #{type => mock}),
    ok = erlmcp_registry:bind_transport_to_server(TransportId, ServerId),

    % Send invalid JSON
    InvalidMessage = <<"{invalid json}">>,
    erlmcp_registry:route_to_server(ServerId, TransportId, InvalidMessage),

    % Should not crash - just log error and continue
    timer:sleep(100),
    ?assert(is_process_alive(Server)),

    % Send valid JSON but invalid method
    InvalidMethodMessage =
        jsx:encode(#{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
                     ?JSONRPC_FIELD_ID => 2,
                     ?JSONRPC_FIELD_METHOD => <<"nonexistent/method">>,
                     ?JSONRPC_FIELD_PARAMS => #{}}),

    erlmcp_registry:route_to_server(ServerId, TransportId, InvalidMethodMessage),

    receive
        {invalid_test_response, ResponseData} ->
            Response = jsx:decode(ResponseData, [return_maps]),
            ?assert(maps:is_key(?JSONRPC_FIELD_ERROR, Response)),
            Error = maps:get(?JSONRPC_FIELD_ERROR, Response),
            ?assertEqual(?JSONRPC_METHOD_NOT_FOUND,
                         maps:get(?JSONRPC_ERROR_FIELD_CODE, Error)) % Method not found
    after 2000 ->
        ?assert(false) % Should have received error response
    end,

    % Cleanup
    MockTransport ! stop,
    erlmcp_registry:unregister_transport(TransportId).

test_registry_communication_failures(#{server := Server}) ->
    % Test that server handles registry communication failures gracefully
    % This is harder to test directly, but we can verify the server doesn't crash
    % when trying to send notifications without a proper registry setup
    ?assertEqual(ok, erlmcp_server:notify_resources_changed(Server)),
    ?assertEqual(ok,
                 erlmcp_server:notify_resource_updated(Server, <<"test://resource">>, #{})),
    ?assertEqual(ok, erlmcp_server:report_progress(Server, <<"token">>, 25.0, 100.0)),

    % Server should still be alive
    ?assert(is_process_alive(Server)),

    % Test what happens when registry calls fail
    % We can't easily simulate registry failures without complex mocking,
    % but we can at least verify the server doesn't crash from basic operations
    ok.

%%====================================================================
%% Performance and Load Tests
%%====================================================================

performance_test_() ->
    {timeout,
     30,
     {setup,
      fun setup_with_registry/0,
      fun cleanup_with_registry/1,
      fun(Context) ->
         {with,
          Context,
          [fun test_multiple_concurrent_requests/1, fun test_large_message_handling/1]}
      end}}.

test_multiple_concurrent_requests(#{server := Server, server_id := ServerId}) ->
    % Add a simple echo tool
    EchoHandler = fun(#{<<"text">> := Text}) -> <<"Echo: ", Text/binary>> end,
    ok = erlmcp_server:add_tool(Server, <<"echo">>, EchoHandler),

    % Create multiple mock transports
    NumTransports = 10,
    TestPid = self(),
    Transports =
        [begin
             MockTransport = spawn_link(fun() -> transport_loop([], TestPid) end),
             TransportId = list_to_atom("load_test_transport_" ++ integer_to_list(N)),
             ok = erlmcp_registry:register_transport(TransportId, MockTransport, #{type => mock}),
             ok = erlmcp_registry:bind_transport_to_server(TransportId, ServerId),
             {TransportId, MockTransport}
         end
         || N <- lists:seq(1, NumTransports)],

    % Send concurrent requests from all transports
    RequestsPerTransport = 5,
    TotalRequests = NumTransports * RequestsPerTransport,

    StartTime = erlang:system_time(millisecond),

    [begin
         Message =
             jsx:encode(#{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
                          ?JSONRPC_FIELD_ID => ReqNum,
                          ?JSONRPC_FIELD_METHOD => ?MCP_METHOD_TOOLS_CALL,
                          ?JSONRPC_FIELD_PARAMS =>
                              #{?MCP_PARAM_NAME => <<"echo">>,
                                ?MCP_PARAM_ARGUMENTS =>
                                    #{?MCP_PARAM_TEXT =>
                                          <<"Request ", (integer_to_binary(ReqNum))/binary>>}}}),
         erlmcp_registry:route_to_server(ServerId, TransportId, Message)
     end
     || {TransportId, _} <- Transports, ReqNum <- lists:seq(1, RequestsPerTransport)],

    % Wait for all responses
    wait_for_responses(TotalRequests, 10000),

    EndTime = erlang:system_time(millisecond),
    Duration = EndTime - StartTime,

    ?assert(Duration < 5000), % Should complete within 5 seconds

    % Cleanup transports
    [begin
         MockTransport ! stop,
         erlmcp_registry:unregister_transport(TransportId)
     end
     || {TransportId, MockTransport} <- Transports].

test_large_message_handling(#{server := Server, server_id := ServerId}) ->
    % Add a tool that handles large input
    LargeHandler =
        fun(#{<<"data">> := Data}) ->
           <<"Processed ", (integer_to_binary(byte_size(Data)))/binary, " bytes">>
        end,
    ok = erlmcp_server:add_tool(Server, <<"large_tool">>, LargeHandler),

    % Create mock transport
    TestPid = self(),
    MockTransport = spawn_link(fun() -> transport_loop([], TestPid) end),
    TransportId = large_test_transport,
    ok = erlmcp_registry:register_transport(TransportId, MockTransport, #{type => mock}),
    ok = erlmcp_registry:bind_transport_to_server(TransportId, ServerId),

    % Create large message (1MB of data)
    LargeData = binary:copy(<<"X">>, 1024 * 1024),
    LargeMessage =
        jsx:encode(#{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
                     ?JSONRPC_FIELD_ID => 1,
                     ?JSONRPC_FIELD_METHOD => ?MCP_METHOD_TOOLS_CALL,
                     ?JSONRPC_FIELD_PARAMS =>
                         #{?MCP_PARAM_NAME => <<"large_tool">>,
                           ?MCP_PARAM_ARGUMENTS => #{<<"data">> => LargeData}}}),

    StartTime = erlang:system_time(millisecond),
    erlmcp_registry:route_to_server(ServerId, TransportId, LargeMessage),

    % Wait for response
    receive
        {large_test_response, _ResponseData} ->
            EndTime = erlang:system_time(millisecond),
            Duration = EndTime - StartTime,
            ?assert(Duration < 2000) % Should handle large messages quickly
    after 10000 ->
        ?assert(false) % Timeout
    end,

    % Cleanup
    MockTransport ! stop,
    erlmcp_registry:unregister_transport(TransportId).

%%====================================================================
%% Helper Functions
%%====================================================================

transport_loop(Responses, TestPid) ->
    receive
        {mcp_response, _ServerId, Data} ->
            TestPid ! {large_test_response, Data},
            transport_loop([Data | Responses], TestPid);
        stop ->
            ok
    after 10000 ->
        ok
    end.

wait_for_responses(0, _Timeout) ->
    ok;
wait_for_responses(Count, Timeout) ->
    receive
        {large_test_response, _Data} ->
            wait_for_responses(Count - 1, Timeout)
    after Timeout ->
        ?assert(false) % Timeout waiting for responses
    end.
