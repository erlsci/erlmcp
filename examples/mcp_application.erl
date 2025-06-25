-module(mcp_application).
-behaviour(application).
-behaviour(supervisor).

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% Supervisor callbacks
-export([init/1]).

%% API for running examples
-export([
    run_weather_demo/0,
    run_calculator_demo/0,
    run_integration_test/0
]).

-define(APP, erlmcp_examples).

%%====================================================================
%% Application Management
%%====================================================================

start() ->
    application:ensure_all_started(?APP).

start(_StartType, _StartArgs) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    ok.

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    
    %% Define child specs for our example servers
    Children = [
        #{
            id => weather_server,
            start => {weather_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [weather_server]
        },
        #{
            id => calculator_client_sup,
            start => {calculator_client_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [calculator_client_sup]
        }
    ],
    
    {ok, {SupFlags, Children}}.

%%====================================================================
%% Demo Functions
%%====================================================================

run_weather_demo() ->
    logger:info("Starting Weather Server Demo..."),
    
    %% The weather server is already started by the supervisor
    %% Let's interact with it
    
    %% Update some temperatures
    weather_server:update_temperature(<<"new_york">>, 25.5),
    weather_server:update_temperature(<<"london">>, 15.8),
    
    %% Set up an alert
    weather_server:add_alert_subscriber(
        <<"admin@example.com">>, 
        #{temperature_max => 30.0, temperature_min => 0.0}
    ),
    
    %% Simulate a client connecting via MCP
    spawn(fun() -> weather_client_demo() end),
    
    ok.

run_calculator_demo() ->
    logger:info("Starting Calculator Client Demo..."),
    
    %% Start a calculator client
    {ok, Client} = calculator_client_sup:start_calculator(),
    
    %% Connect to a calculator server (assuming one is running)
    ServerAddress = #{type => stdio},  % or {tcp, "localhost", 8080}
    ok = calculator_client:connect(Client, ServerAddress),
    
    %% Perform some calculations
    timer:sleep(1000),  % Wait for connection
    
    Expressions = [
        <<"2 + 2">>,
        <<"10 * 5">>,
        <<"sqrt(16)">>,
        <<"pi * r^2 where r = 5">>
    ],
    
    lists:foreach(fun(Expr) ->
        case calculator_client:calculate(Client, Expr) of
            {ok, Result} ->
                logger:info("Calculated: ~s = ~p", [Expr, Result]);
            {error, Reason} ->
                logger:error("Failed to calculate ~s: ~p", [Expr, Reason])
        end
    end, Expressions),
    
    %% Get calculation history
    {ok, History} = calculator_client:get_history(Client),
    logger:info("Calculation history: ~p", [History]),
    
    ok.

run_integration_test() ->
    logger:info("Starting Integration Test..."),
    
    %% Start both server and client components
    %% This demonstrates a full MCP ecosystem
    
    %% Create a test supervisor for the integration
    TestSup = spawn_link(fun() -> integration_test_supervisor() end),
    
    %% Run test scenarios
    timer:sleep(2000),
    
    %% Scenario 1: Weather monitoring with multiple clients
    spawn(fun() -> weather_monitoring_scenario() end),
    
    %% Scenario 2: Distributed calculation
    spawn(fun() -> distributed_calculation_scenario() end),
    
    %% Scenario 3: Resource subscription test
    spawn(fun() -> resource_subscription_scenario() end),
    
    %% Let scenarios run
    timer:sleep(10000),
    
    %% Cleanup
    exit(TestSup, normal),
    
    logger:info("Integration test completed"),
    ok.

%%====================================================================
%% Internal Functions - Demo Helpers
%%====================================================================

weather_client_demo() ->
    %% Simulate an MCP client connecting to the weather server
    {ok, Client} = erlmcp_client:start_link({stdio, []}, #{strict_mode => false}),
    
    %% Initialize connection
    Capabilities = #mcp_client_capabilities{
        roots = #mcp_capability{enabled = true}
    },
    
    {ok, _} = erlmcp_client:initialize(Client, Capabilities),
    
    %% List available resources
    {ok, #{<<"resources">> := Resources}} = erlmcp_client:list_resources(Client),
    logger:info("Available weather resources: ~p", [Resources]),
    
    %% Read weather data
    {ok, #{<<"contents">> := [Content]}} = 
        erlmcp_client:read_resource(Client, <<"weather://new_york">>),
    logger:info("New York weather: ~p", [Content]),
    
    %% Subscribe to updates
    ok = erlmcp_client:subscribe_to_resource(Client, <<"weather://london">>),
    
    %% Use weather query tool
    {ok, Result} = erlmcp_client:call_tool(
        Client, 
        <<"query_weather">>, 
        #{<<"city">> => <<"tokyo">>, <<"metric">> => <<"temperature">>}
    ),
    logger:info("Tokyo temperature query result: ~p", [Result]),
    
    %% Get a weather report using prompt
    {ok, Report} = erlmcp_client:get_prompt(
        Client,
        <<"weather_report">>,
        #{<<"city">> => <<"sydney">>, <<"format">> => <<"detailed">>}
    ),
    logger:info("Sydney weather report: ~p", [Report]),
    
    %% Keep client running to receive notifications
    timer:sleep(60000),
    
    erlmcp_client:stop(Client).

integration_test_supervisor() ->
    process_flag(trap_exit, true),
    
    %% Start multiple MCP servers and clients
    Servers = [
        start_test_server(<<"server1">>, 9001),
        start_test_server(<<"server2">>, 9002),
        start_test_server(<<"server3">>, 9003)
    ],
    
    Clients = [
        start_test_client(<<"client1">>),
        start_test_client(<<"client2">>)
    ],
    
    %% Monitor all processes
    monitor_processes(Servers ++ Clients).

start_test_server(Name, Port) ->
    logger:info("Starting test server ~s on port ~p", [Name, Port]),
    
    Capabilities = #mcp_server_capabilities{
        resources = #mcp_capability{enabled = true},
        tools = #mcp_capability{enabled = true}
    },
    
    {ok, Server} = erlmcp_server:start_link({tcp, Port}, Capabilities),
    
    %% Add some test resources
    erlmcp_server:add_resource(
        Server, 
        <<Name/binary, "://status">>,
        fun(_) -> <<"Server ", Name/binary, " is running">> end
    ),
    
    %% Add a test tool
    erlmcp_server:add_tool(
        Server,
        <<"echo">>,
        fun(#{<<"message">> := Msg}) ->
            #mcp_content{
                type = <<"text">>,
                text = <<"Echo from ", Name/binary, ": ", Msg/binary>>
            }
        end
    ),
    
    Server.

start_test_client(Name) ->
    logger:info("Starting test client ~s", [Name]),
    
    {ok, Client} = erlmcp_client:start_link({stdio, []}, #{strict_mode => false}),
    
    %% Set up notification handler
    erlmcp_client:set_notification_handler(
        Client,
        <<"test/notification">>,
        fun(Method, Params) ->
            logger:info("Client ~s received notification ~s: ~p", 
                        [Name, Method, Params])
        end
    ),
    
    Client.

monitor_processes(Pids) ->
    lists:foreach(fun(Pid) -> monitor(process, Pid) end, Pids),
    monitor_loop().

monitor_loop() ->
    receive
        {'DOWN', _Ref, process, Pid, Reason} ->
            logger:warning("Process ~p died: ~p", [Pid, Reason]),
            monitor_loop();
        stop ->
            ok
    end.

weather_monitoring_scenario() ->
    logger:info("Running weather monitoring scenario..."),
    
    %% Create monitoring clients
    Monitors = [
        create_weather_monitor(<<"monitor1">>, [<<"new_york">>, <<"london">>]),
        create_weather_monitor(<<"monitor2">>, [<<"tokyo">>, <<"sydney">>])
    ],
    
    %% Simulate weather changes
    timer:sleep(2000),
    weather_server:update_temperature(<<"new_york">>, 28.0),
    timer:sleep(1000),
    weather_server:update_temperature(<<"london">>, 12.0),
    
    %% Let monitors react
    timer:sleep(5000),
    
    %% Cleanup
    lists:foreach(fun(M) -> erlmcp_client:stop(M) end, Monitors).

create_weather_monitor(Name, Cities) ->
    {ok, Client} = erlmcp_client:start_link({stdio, []}, #{strict_mode => false}),
    
    %% Initialize
    Capabilities = #mcp_client_capabilities{
        roots = #mcp_capability{enabled = true}
    },
    {ok, _} = erlmcp_client:initialize(Client, Capabilities),
    
    %% Subscribe to cities
    lists:foreach(fun(City) ->
        Uri = <<"weather://", City/binary>>,
        ok = erlmcp_client:subscribe_to_resource(Client, Uri),
        logger:info("Monitor ~s subscribed to ~s", [Name, Uri])
    end, Cities),
    
    %% Set up update handler
    erlmcp_client:set_notification_handler(
        Client,
        <<"resources/updated">>,
        fun(_Method, #{<<"uri">> := Uri} = Params) ->
            logger:info("Monitor ~s: Weather update for ~s: ~p", 
                        [Name, Uri, Params])
        end
    ),
    
    Client.

distributed_calculation_scenario() ->
    logger:info("Running distributed calculation scenario..."),
    
    %% Create multiple calculator clients
    Clients = [
        create_calculator_client(<<"calc1">>),
        create_calculator_client(<<"calc2">>),
        create_calculator_client(<<"calc3">>)
    ],
    
    %% Distribute calculations across clients
    Calculations = [
        {<<"calc1">>, <<"factorial(10)">>},
        {<<"calc2">>, <<"fibonacci(20)">>},
        {<<"calc3">>, <<"prime_factors(1000)">>},
        {<<"calc1">>, <<"gcd(48, 18)">>},
        {<<"calc2">>, <<"lcm(12, 15)">>},
        {<<"calc3">>, <<"is_prime(97)">>}
    ],
    
    %% Execute calculations in parallel
    Tasks = lists:map(fun({ClientName, Expression}) ->
        ClientIndex = case ClientName of
            <<"calc1">> -> 1;
            <<"calc2">> -> 2;
            <<"calc3">> -> 3
        end,
        Client = lists:nth(ClientIndex, Clients),
        
        spawn(fun() ->
            case calculator_client:calculate(Client, Expression) of
                {ok, Result} ->
                    logger:info("~s calculated ~s = ~p", 
                                [ClientName, Expression, Result]);
                {error, Reason} ->
                    logger:error("~s failed to calculate ~s: ~p", 
                                 [ClientName, Expression, Reason])
            end
        end)
    end, Calculations),
    
    %% Wait for all calculations to complete
    lists:foreach(fun(Task) ->
        monitor(process, Task),
        receive
            {'DOWN', _, process, Task, _} -> ok
        after 5000 ->
            logger:warning("Task ~p timed out", [Task])
        end
    end, Tasks),
    
    %% Get history from all clients
    lists:foreach(fun(Client) ->
        {ok, History} = calculator_client:get_history(Client),
        logger:info("Client history: ~p", [History])
    end, Clients),
    
    %% Cleanup
    lists:foreach(fun(C) -> calculator_client:stop(C) end, Clients).

create_calculator_client(Name) ->
    {ok, Client} = calculator_client:start_link(#{name => Name}),
    
    %% Connect to a mock calculator server
    ok = calculator_client:connect(Client, #{type => stdio}),
    timer:sleep(500),  % Wait for connection
    
    Client.

resource_subscription_scenario() ->
    logger:info("Running resource subscription scenario..."),
    
    %% Create a client that monitors resource changes
    {ok, Client} = erlmcp_client:start_link({stdio, []}, #{strict_mode => false}),
    
    %% Initialize
    Capabilities = #mcp_client_capabilities{
        roots = #mcp_capability{enabled = true}
    },
    {ok, _} = erlmcp_client:initialize(Client, Capabilities),
    
    %% Set up handlers for resource list changes
    erlmcp_client:set_notification_handler(
        Client,
        <<"resources/list_changed">>,
        fun(_Method, Params) ->
            logger:info("Resource list changed: ~p", [Params]),
            %% Re-fetch resource list
            spawn(fun() ->
                {ok, #{<<"resources">> := Resources}} = 
                    erlmcp_client:list_resources(Client),
                logger:info("Updated resource list: ~p", [Resources])
            end)
        end
    ),
    
    %% Monitor for 30 seconds
    timer:sleep(30000),
    
    erlmcp_client:stop(Client).

%%====================================================================
%% Calculator Client Supervisor
%%====================================================================

-module(calculator_client_sup).
-behaviour(supervisor).

-export([start_link/0, start_calculator/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_calculator() ->
    supervisor:start_child(?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5,
        period => 10
    },
    
    ChildSpecs = [
        #{
            id => calculator_client,
            start => {calculator_client, start_link, []},
            restart => temporary,
            shutdown => 5000,
            type => worker,
            modules => [calculator_client]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.