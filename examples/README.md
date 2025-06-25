# Erlang MCP SDK Examples

This directory contains idiomatic Erlang examples demonstrating the Model Context Protocol (MCP) SDK usage with proper OTP design patterns.

## Examples Overview

### 1. Weather Server (`weather_server.erl`)

A complete MCP server implementation that provides weather data and monitoring capabilities.

**Features:**
- OTP gen_server with proper supervision
- Resource management with templates
- Tool schemas with JSON Schema validation  
- Subscription and notification system
- Alert management for temperature thresholds
- Automatic weather simulation

**Key Design Patterns:**
- Separation of MCP protocol handling from business logic
- State encapsulation in gen_server
- Proper error handling and logging
- Resource lifecycle management

**Usage:**
```erlang
%% Start the weather server
{ok, Server} = weather_server:start_link().

%% Update temperature
weather_server:update_temperature(<<"new_york">>, 25.5).

%% Add alert subscriber
weather_server:add_alert_subscriber(
    <<"admin@example.com">>, 
    #{temperature_max => 30.0}
).

%% MCP clients can:
%% - Read resources: weather://new_york
%% - Use tools: query_weather, compare_weather
%% - Get prompts: weather_report, travel_weather_advice
```

### 2. Calculator Client (`calculator_client.erl`)

A sophisticated MCP client using gen_statem for connection management.

**Features:**
- State machine for connection lifecycle
- Automatic reconnection with backoff
- Request queuing during connection establishment
- Multiple fallback strategies for calculations
- History tracking and management
- Graceful degradation

**Key Design Patterns:**
- gen_statem for complex state management
- Separation of connection and business logic
- Resilient error handling
- Progressive enhancement strategy

**State Machine:**
```
disconnected -> connecting -> connected -> ready
     ^              |            |           |
     |              v            v           |
     +<-------------+<-----------+-----------+
         (on error/disconnect)
```

**Usage:**
```erlang
%% Start calculator client
{ok, Client} = calculator_client:start_link().

%% Connect to server
calculator_client:connect(Client, #{type => tcp, host => "localhost", port => 8080}).

%% Perform calculations
{ok, Result} = calculator_client:calculate(Client, <<"2 + 2">>).

%% Get history
{ok, History} = calculator_client:get_history(Client).
```

### 3. MCP Application (`mcp_application.erl`)

A complete OTP application demonstrating proper supervision and integration.

**Features:**
- OTP application behavior
- Supervision tree with restart strategies
- Integration test scenarios
- Demo runners for all components
- Process monitoring and management

**Architecture:**
```
mcp_application (supervisor)
    ├── weather_server
    └── calculator_client_sup
            └── calculator_client (dynamic)
```

**Usage:**
```erlang
%% Start the application
mcp_application:start().

%% Run demos
mcp_application:run_weather_demo().
mcp_application:run_calculator_demo().
mcp_application:run_integration_test().
```

## Design Principles Demonstrated

### 1. **OTP Compliance**
- All servers use gen_server or gen_statem
- Proper supervision hierarchies
- Correct callback implementations
- Process linking and monitoring

### 2. **Error Handling**
- Let it crash philosophy with supervision
- Graceful degradation for client operations
- Comprehensive error logging
- Recovery strategies

### 3. **State Management**
- Immutable state updates
- Clear state transitions
- Proper state isolation
- No global state

### 4. **Protocol Abstraction**
- Clean separation of MCP protocol from business logic
- Handler functions for resources, tools, and prompts
- Type specifications for all public APIs
- Clear module boundaries

### 5. **Scalability Patterns**
- Supervision for fault tolerance
- Process-based concurrency
- Message passing for communication
- No shared state between processes

## Running the Examples

### Prerequisites
```bash
# Compile the project
rebar3 compile

# Start an Erlang shell
rebar3 shell
```

### Weather Server Example
```erlang
%% Start weather server (standalone)
{ok, Server} = weather_server:start_link().

%% The server listens on stdio by default
%% Use an MCP client to connect and interact
```

### Calculator Client Example
```erlang
%% Start calculator client
{ok, Client} = calculator_client:start_link().

%% Connect to a calculator server
calculator_client:connect(Client, #{type => stdio}).

%% Perform calculations
{ok, Result} = calculator_client:calculate(Client, <<"sqrt(16)">>).
```

### Full Application Example
```erlang
%% Start the entire application
application:start(erlmcp_examples).

%% Or use the convenience function
mcp_application:start().

%% Run integrated demos
mcp_application:run_weather_demo().
```

## Testing Patterns

### Unit Testing
```erlang
%% Test individual components
weather_server_tests:test().
calculator_client_tests:test().
```

### Integration Testing
```erlang
%% Run full integration test
mcp_application:run_integration_test().
```

### Property-Based Testing
```erlang
%% Using PropEr for property tests
proper:quickcheck(weather_server_prop:prop_temperature_bounds()).
```

## Best Practices Illustrated

1. **Process Design**
   - One process per connection
   - Supervised processes for reliability
   - Clear process responsibilities
   - Proper cleanup in terminate callbacks

2. **Resource Management**
   - Dynamic resource creation with templates
   - Subscription lifecycle management
   - Proper cleanup of resources
   - Efficient data structures (sets for subscriptions)

3. **Communication Patterns**
   - Asynchronous message passing
   - Synchronous calls with timeouts
   - Event-driven notifications
   - Batch request handling

4. **Type Safety**
   - Comprehensive -spec annotations
   - Custom types for domain concepts
   - Dialyzer-friendly code
   - Clear API contracts

5. **Logging and Observability**
   - Structured logging with context
   - Different log levels for different scenarios
   - Performance metrics
   - Error tracking

## Common Patterns

### Handler Registration Pattern
```erlang
%% Register a handler function
setup_handler(Server) ->
    Handler = fun(Uri) ->
        %% Handler logic here
        #mcp_content{
            type = <<"text">>,
            text = process_request(Uri)
        }
    end,
    erlmcp_server:add_resource(Server, <<"resource://path">>, Handler).
```

### Notification Pattern
```erlang
%% Set up notification handling
setup_notifications(Client) ->
    erlmcp_client:set_notification_handler(
        Client,
        <<"notification/type">>,
        fun(Method, Params) ->
            handle_notification(Method, Params)
        end
    ).
```

### State Machine Pattern
```erlang
%% gen_statem for complex flows
handle_event({call, From}, Event, State, Data) ->
    case State of
        ready ->
            {Result, NewData} = process_event(Event, Data),
            {next_state, State, NewData, [{reply, From, Result}]};
        _ ->
            {keep_state_and_data, [{reply, From, {error, not_ready}}]}
    end.
```

### Supervision Pattern
```erlang
%% Supervisor child spec
child_spec(Id, Module, Args) ->
    #{
        id => Id,
        start => {Module, start_link, Args},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [Module]
    }.
```

## Performance Considerations

1. **Process Pool Pattern**
   - Use simple_one_for_one supervisors for dynamic workers
   - Pool processes for handling requests
   - Limit concurrent operations

2. **Batch Operations**
   - Group multiple requests together
   - Reduce protocol overhead
   - Improve throughput

3. **Caching Strategy**
   - Cache frequently accessed resources
   - Implement TTL for cache entries
   - Use ETS for fast lookups

4. **Message Queue Management**
   - Implement backpressure mechanisms
   - Queue limits to prevent overflow
   - Priority handling for critical messages

## Debugging Tips

### 1. Enable Debug Logging
```erlang
logger:set_handler_config(default, level, debug).
```

### 2. Use Observer
```erlang
observer:start().
%% Inspect process state, message queues, and memory usage
```

### 3. Trace Function Calls
```erlang
recon_trace:calls({weather_server, '_', '_'}, 10).
```

### 4. Monitor Process Health
```erlang
recon:proc_count(memory, 10).  % Top 10 processes by memory
recon:proc_count(message_queue_len, 10).  % Top 10 by queue length
```

## Production Deployment

### Configuration
```erlang
%% config/prod.config
[
    {erlmcp_examples, [
        {weather_server, [
            {port, 8080},
            {max_connections, 1000},
            {timeout, 30000}
        ]},
        {calculator_client, [
            {reconnect_interval, 5000},
            {max_retries, 10}
        ]}
    ]}
].
```

### Monitoring
- Set up Prometheus/Grafana for metrics
- Use distributed tracing for request flow
- Implement health checks
- Set up alerts for critical errors

### Scaling
- Horizontal scaling with distributed Erlang
- Load balancing across nodes
- Partition resources by hash
- Use pg (process groups) for distribution

## Extending the Examples

### Adding a New Resource Type
```erlang
%% In your server module
add_custom_resource(Server) ->
    erlmcp_server:add_resource(
        Server,
        <<"custom://resource">>,
        fun(Uri) ->
            %% Your resource logic
            #mcp_content{
                type = <<"application/json">>,
                text = jsx:encode(#{status => ok})
            }
        end
    ).
```

### Creating a Tool with Validation
```erlang
%% Define schema
Schema = #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"input">> => #{<<"type">> => <<"string">>}
    },
    <<"required">> => [<<"input">>]
},

%% Add tool
erlmcp_server:add_tool_with_schema(
    Server,
    <<"my_tool">>,
    fun(#{<<"input">> := Input}) ->
        process_tool_input(Input)
    end,
    Schema
).
```

### Implementing Custom Transport
```erlang
-module(my_transport).
-behaviour(erlmcp_transport).

-export([init/1, send/2, close/1]).

init(Opts) ->
    %% Initialize your transport
    {ok, State}.

send(State, Data) ->
    %% Send data through your transport
    ok.

close(State) ->
    %% Cleanup
    ok.
```

## Troubleshooting

### Common Issues

1. **Connection Failures**
   - Check transport configuration
   - Verify server is running
   - Check firewall rules
   - Review logs for errors

2. **Protocol Errors**
   - Ensure protocol version compatibility
   - Validate message format
   - Check capability negotiation
   - Review JSON-RPC formatting

3. **Performance Issues**
   - Monitor process message queues
   - Check for blocking operations
   - Review memory usage
   - Profile hot code paths

### Debug Checklist
- [ ] Are all processes running? (`observer:start()`)
- [ ] Are messages being sent/received? (trace logging)
- [ ] Is the state correct? (sys:get_state/1)
- [ ] Are there any crashes? (check logs)
- [ ] Is the protocol correct? (capture traffic)

## Contributing

When adding new examples:

1. Follow OTP design principles
2. Add comprehensive documentation
3. Include error handling
4. Add type specifications
5. Write tests
6. Update this README

## License

These examples are part of the Erlang MCP SDK and are licensed under the Apache 2.0 License.