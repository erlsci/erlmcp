# erlmcp OTP Supervision Architecture Design

## Overview

This document outlines the design for restructuring erlmcp to follow proper OTP supervision patterns, moving away from ad hoc process management toward a robust, fault-tolerant supervision tree architecture.

## Current Problems with Ad Hoc Process Management

### Issues in Current Architecture

1. **Manual Process Management**: `erlmcp_server` manually spawns and links to transport processes
2. **Custom Monitoring Logic**: Non-standard process monitoring and error handling
3. **Cascading Failures**: Transport failures can bring down the entire server
4. **No Restart Strategies**: Can't configure different restart behaviors for different components
5. **Not OTP-Compliant**: Missing out on OTP's battle-tested supervision patterns
6. **Difficult Testing**: Hard to test failure scenarios and recovery

### Example of Current Problems

```erlang
%% Current problematic pattern in erlmcp_server
init_transport({stdio, _Opts}) ->
    case erlmcp_transport_stdio:start_link(self()) of
        {ok, Pid} ->
            %% Manual linking and monitoring
            monitor(process, Pid),
            {ok, erlmcp_transport_stdio, Pid};
        {error, Reason} ->
            {error, Reason}
    end.
```

## Proposed OTP Supervision Architecture

### High-Level Architecture

```
erlmcp_app
    ↓ starts
erlmcp_sup (application supervisor - one_for_all)
    ├── erlmcp_registry (gen_server)
    ├── erlmcp_server_sup (simple_one_for_one)
    │   └── [erlmcp_server instances...]
    └── erlmcp_transport_sup (one_for_one)
        ├── erlmcp_transport_stdio (gen_server)
        ├── erlmcp_transport_tcp (gen_server)
        └── erlmcp_transport_http (gen_server)
```

### Component Responsibilities

#### erlmcp_registry (gen_server)

- **Purpose**: Manages server-transport relationships and routing
- **Responsibilities**:
  - Register/unregister servers and transports
  - Route messages between servers and transports
  - Maintain capability mappings
  - Handle component discovery
- **State**: Registry tables, routing maps, capability information

#### erlmcp_server (gen_server)

- **Purpose**: Pure MCP protocol logic with no transport management
- **Responsibilities**:
  - Handle MCP protocol requests/responses
  - Manage resources, tools, and prompts
  - Validate schemas and capabilities
  - Generate protocol responses
- **State**: Protocol state, resources, tools, prompts (no transport state)

#### erlmcp_transport_* (gen_server)

- **Purpose**: Handle specific transport communication
- **Responsibilities**:
  - Manage transport-specific connections
  - Handle transport-specific errors and recovery
  - Convert transport messages to/from standard format
  - Report transport status to registry
- **State**: Transport-specific connection state

#### erlmcp_server_sup (simple_one_for_one)

- **Purpose**: Dynamically supervise multiple server instances
- **Use Cases**:
  - Multiple servers with different configurations
  - Hot swapping server configurations
  - Load balancing across server instances

#### erlmcp_transport_sup (one_for_one)

- **Purpose**: Supervise transport processes independently
- **Restart Strategy**: Transport failures don't affect other transports
- **Dynamic Management**: Add/remove transports at runtime

## Detailed Component Design

### 1. erlmcp_registry Design

```erlang
-module(erlmcp_registry).
-behaviour(gen_server).

%% API
-export([
    register_server/2,
    register_transport/2,
    route_to_server/3,
    route_to_transport/3,
    list_servers/0,
    list_transports/0,
    get_server_for_transport/1
]).

%% State
-record(registry_state, {
    servers = #{} :: #{server_id() => {pid(), server_config()}},
    transports = #{} :: #{transport_id() => {pid(), transport_config()}},
    server_transport_map = #{} :: #{transport_id() => server_id()},
    capabilities = #{} :: #{server_id() => #mcp_server_capabilities{}}
}).

%% Message routing
handle_cast({route_to_server, ServerId, Message}, State) ->
    case get_server_pid(ServerId, State) of
        {ok, ServerPid} ->
            ServerPid ! Message,
            {noreply, State};
        {error, not_found} ->
            logger:warning("Server not found: ~p", [ServerId]),
            {noreply, State}
    end.
```

### 2. erlmcp_server Design (Transport-Free)

```erlang
-module(erlmcp_server).
-behaviour(gen_server).

%% State record - NO transport state
-record(state, {
    server_id :: server_id(),
    capabilities :: #mcp_server_capabilities{},
    resources = #{} :: #{binary() => {#mcp_resource{}, resource_handler()}},
    tools = #{} :: #{binary() => {#mcp_tool{}, tool_handler(), map() | undefined}},
    prompts = #{} :: #{binary() => {#mcp_prompt{}, prompt_handler()}},
    subscriptions = #{} :: #{binary() => sets:set(pid())},
    progress_tokens = #{} :: #{binary() | integer() => #mcp_progress_notification{}},
    initialized = false :: boolean()
}).

%% No transport management - messages come via registry
handle_info({mcp_message, TransportId, Data}, State) ->
    case erlmcp_json_rpc:decode_message(Data) of
        {ok, Request} ->
            Response = handle_mcp_request(Request, State),
            erlmcp_registry:route_to_transport(TransportId, Response),
            {noreply, State};
        {error, Reason} ->
            logger:error("Failed to decode message: ~p", [Reason]),
            {noreply, State}
    end.
```

### 3. Transport Design (Standardized)

```erlang
-module(erlmcp_transport_stdio).
-behaviour(gen_server).

%% State - only transport concerns
-record(state, {
    transport_id :: transport_id(),
    server_id :: server_id(),
    reader_pid :: pid() | undefined,
    buffer = <<>> :: binary(),
    config :: transport_config()
}).

%% Standard transport message handling
handle_info({data, Data}, State) ->
    %% Route to server via registry
    erlmcp_registry:route_to_server(State#state.server_id,
                                    {mcp_message, State#state.transport_id, Data}),
    {noreply, State}.

%% Standard transport API
send_message(TransportId, Message) ->
    gen_server:cast(TransportId, {send, Message}).
```

## Supervision Strategies

### 1. Application Level (one_for_all)

- **Rationale**: If registry fails, entire system needs restart
- **Components**: registry, server_sup, transport_sup
- **Restart**: All components restart if any critical component fails

### 2. Server Supervision (simple_one_for_one)

- **Rationale**: Support multiple server instances with different configurations
- **Dynamic**: Add/remove servers at runtime
- **Isolation**: Server failure doesn't affect transports

### 3. Transport Supervision (one_for_one)

- **Rationale**: Transport failures should be isolated
- **Independence**: Each transport can fail and restart independently
- **Flexibility**: Add/remove transports dynamically

## Message Flow Architecture

### 1. Incoming Messages

```
Transport → Registry → Server
    ↓
stdio_transport receives stdin
    ↓
stdio_transport ! {data, Message}
    ↓
erlmcp_registry:route_to_server(ServerId, {mcp_message, TransportId, Message})
    ↓
Server ! {mcp_message, TransportId, Message}
    ↓
Server processes MCP protocol
```

### 2. Outgoing Messages

```
Server → Registry → Transport
    ↓
Server generates response
    ↓
erlmcp_registry:route_to_transport(TransportId, Response)
    ↓
Transport ! {send, Response}
    ↓
Transport sends via its mechanism
```

## Configuration Management

### 1. Application Configuration

```erlang
%% sys.config
{erlmcp, [
    {servers, [
        #{id => default_server,
          capabilities => #{
              resources => #{enabled => true},
              tools => #{enabled => true},
              prompts => #{enabled => true}
          }}
    ]},
    {transports, [
        #{id => stdio_transport,
          type => stdio,
          server_id => default_server,
          config => #{}},
        #{id => tcp_transport,
          type => tcp,
          server_id => default_server,
          config => #{host => "127.0.0.1", port => 8080}}
    ]}
]}.
```

### 2. Dynamic Configuration

```erlang
%% Add server at runtime
erlmcp:start_server(#{
    id => new_server,
    capabilities => Capabilities
}).

%% Add transport at runtime
erlmcp:start_transport(#{
    id => new_transport,
    type => http,
    server_id => new_server,
    config => #{url => "https://api.example.com"}
}).
```

## API Design

### 1. High-Level Application API

```erlang
-module(erlmcp).

%% Application management
-export([start_server/1, stop_server/1, list_servers/0]).
-export([start_transport/1, stop_transport/1, list_transports/0]).

%% Server operations (delegates to specific server)
-export([add_resource/3, add_tool/3, add_prompt/3]).

%% Configuration
-export([get_server_config/1, update_server_config/2]).
-export([get_transport_config/1, update_transport_config/2]).

start_server(Config = #{id := ServerId}) ->
    erlmcp_server_sup:start_child(ServerId, Config).

add_resource(ServerId, Uri, Handler) ->
    gen_server:call({via, registry, {server, ServerId}},
                    {add_resource, Uri, Handler}).
```

### 2. Registry API

```erlang
-module(erlmcp_registry).

%% Registration
-export([register_server/3, register_transport/3]).
-export([unregister_server/1, unregister_transport/1]).

%% Routing
-export([route_to_server/3, route_to_transport/3]).

%% Discovery
-export([find_server/1, find_transport/1]).
-export([list_servers/0, list_transports/0]).

%% Relationships
-export([bind_transport_to_server/2, unbind_transport/1]).
```

## Failure Handling and Recovery

### 1. Transport Failures

```erlang
%% Transport crash - server continues, transport restarts
Transport crashes →
Transport supervisor restarts transport →
Transport re-registers with registry →
Connection re-established
```

### 2. Server Failures

```erlang
%% Server crash - transports buffer/drop messages
Server crashes →
Server supervisor restarts server →
Server re-registers with registry →
Registry updates routing tables →
Transports resume message delivery
```

### 3. Registry Failures

```erlang
%% Registry crash - full system restart (one_for_all)
Registry crashes →
Application supervisor restarts all components →
All components re-register →
System fully operational
```

## Implementation Phases

### Phase 1: Core Infrastructure - 0.4.0

- [ ] Design and implement `erlmcp_registry`
- [ ] Create supervision tree structure
- [ ] Implement basic message routing
- [ ] Add component registration/discovery

### Phase 2: Server Refactoring  - 0.5.0

- [ ] Remove transport management from `erlmcp_server`
- [ ] Implement message-based server communication
- [ ] Add server configuration management
- [ ] Update server API to work with registry

### Phase 3: Transport Standardization - 0.6.0

- [ ] Standardize transport behavior interface
- [ ] Implement transports as supervised gen_servers
- [ ] Add transport registration and routing
- [ ] Implement transport failure recovery
- [ ] Ensure all needed functionality is in erlmcp_transport_stdio_new

### Phase 4: Update Examples, Documentation - 0.7.0

- [ ] Simple
- [ ] Calculator
- [ ] Weather
- [ ] README
- [ ] applicable files in ./docs/*.md
- [ ] Tests updates

### Phase 5: Remove Old Code - 0.8.0

- [ ] Remove erlmcp_stdio
- [ ] Remove erlmcp_stdio_server
- [ ] Remove erlmcp_transport_stdio

### Phase 6: Rename 'new' modules - 0.9.0

- [ ] Rename erlmcp_transport_stdio_new -> erlmcp_transport_stdio
- [ ] Rename erlmcp_stdio_server_new -> erlmcp_stdio_server

### Phase 7: Release 1.0.0

### Phase 8: Dynamic Management - future/backlog

- [ ] Add runtime server/transport management
- [ ] Implement configuration updates
- [ ] Add monitoring and health checking
- [ ] Create management API

### Phase 9: Advanced Features - future/backlog

- [ ] Multiple server instances
- [ ] Load balancing and routing strategies
- [ ] Hot code updates
- [ ] Metrics and observability

## Testing Strategy

### 1. Unit Testing

- Test each component in isolation
- Mock dependencies (registry, transports, etc.)
- Test failure scenarios extensively

### 2. Integration Testing

- Test message routing between components
- Test supervision restart scenarios
- Test dynamic configuration changes

### 3. Property-Based Testing

- Test supervision tree stability
- Test message delivery guarantees
- Test system recovery properties

### 4. Chaos Testing

- Random component failures
- Network partitions (for distributed transports)
- Resource exhaustion scenarios

## Benefits of This Architecture

### 1. Fault Tolerance

- Component failures are isolated and recoverable
- Standard OTP supervision patterns provide battle-tested reliability
- Clear failure boundaries and recovery strategies

### 2. Scalability

- Multiple server instances for different use cases
- Independent transport scaling
- Dynamic component management

### 3. Maintainability

- Clear separation of concerns
- Standard OTP patterns familiar to Erlang developers
- Easier testing and debugging

### 4. Flexibility

- Easy to add new transport types
- Configurable restart and failure strategies
- Runtime reconfiguration capabilities

### 5. Observability

- Clear component boundaries for monitoring
- Standard OTP telemetry integration
- Structured logging and metrics

## Migration Strategy

### 1. Backward Compatibility

- Keep existing APIs during transition
- Implement adapter layers for old interfaces
- Gradual migration of examples and tests

### 2. Phased Rollout

- Start with new supervision structure
- Migrate one transport at a time
- Update examples incrementally

### 3. Testing During Migration

- Comprehensive test coverage before changes
- Parallel testing of old and new architectures
- Performance benchmarking throughout migration

## Success Criteria

### Technical Success

- [ ] All components properly supervised
- [ ] No ad hoc process management
- [ ] Standard OTP patterns throughout
- [ ] Configurable restart strategies
- [ ] Clean component interfaces

### Reliability Success

- [ ] Transport failures don't affect server
- [ ] Server failures don't lose transport connections
- [ ] Predictable recovery from all failure scenarios
- [ ] No message loss during component restarts

### Developer Experience Success

- [ ] Clear component responsibilities
- [ ] Easy to add new servers/transports
- [ ] Excellent debugging and monitoring
- [ ] Familiar OTP patterns

### Performance Success

- [ ] No performance regression
- [ ] Efficient message routing
- [ ] Low overhead supervision
- [ ] Fast failure detection and recovery

## Conclusion

This OTP supervision architecture transforms erlmcp from an ad hoc process management system into a robust, fault-tolerant, and scalable OTP application. By leveraging proven supervision patterns and clear component separation, we create a foundation that can grow with the project while maintaining reliability and maintainability.

The registry-based message routing provides flexibility while maintaining performance, and the dynamic component management enables runtime reconfiguration without system restarts. This architecture positions erlmcp as a production-ready, enterprise-grade MCP implementation.
