# Phase 3: Transport Standardization Implementation Plan

## Context and Background

This is Phase 3 of the erlmcp OTP supervision architecture redesign. **Phase 2 is complete** - we now have:
- ✅ `erlmcp_registry` for message routing
- ✅ OTP supervision tree structure
- ✅ Registry-based server-transport communication
- ✅ `erlmcp_server` decoupled from transport management

**Current supervision tree state:**
```
erlmcp_sup (application supervisor - one_for_all)
    ├── erlmcp_registry (gen_server) ✅
    ├── erlmcp_server_sup (simple_one_for_one) ✅
    │   └── [erlmcp_server instances...] ✅
    └── erlmcp_transport_sup (one_for_one) ✅
        ├── erlmcp_transport_stdio_new (gen_server) ⚠️ (needs standardization)
        ├── erlmcp_transport_tcp (gen_server) ⚠️ (needs refactoring)  
        └── erlmcp_transport_http (gen_server) ⚠️ (needs refactoring)
```

## Phase 3 Goals

**Primary Objective:** Standardize all transports to follow consistent OTP patterns and integrate properly with the registry-based architecture.

**Specific Goals:**
1. **Standardize Transport Behavior Interface** - Common API across all transports
2. **Complete OTP Integration** - All transports as supervised gen_servers
3. **Registry Integration** - All transports route through `erlmcp_registry`
4. **Eliminate Legacy Components** - Remove duplicated protocol implementations
5. **Consistent Error Handling** - Standard failure and recovery patterns

## Current Problems to Solve

### Legacy Components (to be removed in Phase 5)
- `erlmcp_stdio_server` ❌ - Duplicates MCP protocol logic
- `erlmcp_stdio` ❌ - Wrapper around deprecated stdio_server
- `erlmcp_transport_stdio` ❌ - Old version, not registry-integrated

### Transport Issues
1. **erlmcp_transport_stdio_new**: Nearly complete, needs final standardization
2. **erlmcp_transport_tcp**: Not registry-integrated, inconsistent error handling
3. **erlmcp_transport_http**: Overcomplicated, not registry-integrated

## Standard Transport Architecture

### 1. Transport Behavior Interface

All transports must implement this behavior:

```erlang
%% erlmcp_transport.erl (enhanced)
-module(erlmcp_transport).

%% Core transport behavior
-callback init(TransportId :: atom(), Config :: map()) -> 
    {ok, State :: term()} | {error, Reason :: term()}.

-callback send(State :: term(), Data :: iodata()) -> 
    ok | {error, Reason :: term()}.

-callback close(State :: term()) -> ok.

%% Optional callbacks for advanced features
-callback get_info(State :: term()) -> 
    #{type => atom(), status => atom(), peer => term()}.

-callback handle_transport_call(Request :: term(), State :: term()) -> 
    {reply, Reply :: term(), NewState :: term()} | 
    {error, Reason :: term()}.

-optional_callbacks([get_info/1, handle_transport_call/2]).

%% Standard message format all transports send to registry
-type transport_message() :: 
    {transport_data, Data :: binary()} |
    {transport_connected, Info :: map()} |
    {transport_disconnected, Reason :: term()} |
    {transport_error, Type :: atom(), Reason :: term()}.
```

### 2. Standard Gen_Server Pattern

All transports must follow this pattern:

```erlang
-module(erlmcp_transport_TYPE).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

%% Standard state record for all transports
-record(state, {
    transport_id :: atom(),
    server_id :: atom() | undefined,
    config :: map(),
    %% Transport-specific fields below this line
    connection :: term(),
    buffer = <<>> :: binary()
}).

%% Standard init pattern
init([TransportId, Config]) ->
    process_flag(trap_exit, true),
    ServerId = maps:get(server_id, Config, undefined),
    
    case transport_init(Config) of
        {ok, TransportState} ->
            State = #state{
                transport_id = TransportId,
                server_id = ServerId,
                config = Config,
                connection = TransportState
            },
            
            %% Register with registry
            TransportConfig = Config#{type => ?TRANSPORT_TYPE},
            case erlmcp_registry:register_transport(TransportId, self(), TransportConfig) of
                ok -> 
                    logger:info("Transport ~p started and registered", [TransportId]),
                    {ok, State};
                {error, Reason} ->
                    logger:error("Transport registration failed: ~p", [Reason]),
                    {stop, {registration_failed, Reason}}
            end;
        {error, Reason} ->
            {stop, Reason}
    end.

%% Standard message handling from registry
handle_info({mcp_response, _ServerId, Data}, State) ->
    case send_data(Data, State) of
        {ok, NewState} -> {noreply, NewState};
        {error, Reason} -> 
            notify_error(transport_send_failed, Reason, State),
            {noreply, State}
    end;

%% Transport-specific data reception
handle_info({transport_data_received, Data}, State) ->
    case State#state.server_id of
        undefined ->
            logger:warning("Transport ~p received data but no server bound", 
                          [State#state.transport_id]);
        ServerId ->
            erlmcp_registry:route_to_server(ServerId, State#state.transport_id, Data)
    end,
    {noreply, State}.
```

### 3. Registry Integration Protocol

All transports must integrate with the registry:

```erlang
%% Registration
erlmcp_registry:register_transport(TransportId, TransportPid, Config)

%% Message routing TO server
erlmcp_registry:route_to_server(ServerId, TransportId, IncomingData)

%% Message routing FROM server (via handle_info)
Transport receives: {mcp_response, ServerId, OutgoingData}

%% Binding management  
erlmcp_registry:bind_transport_to_server(TransportId, ServerId)
```

## Configuration Standardization

### Unified Configuration Schema

```erlang
%% All transports use map-based configuration
-type transport_config() :: #{
    type := stdio | tcp | http,
    server_id => atom(),
    %% Transport-specific options
    _ => _
}.

%% stdio transport
#{
    type => stdio,
    server_id => my_server,
    test_mode => false  %% Optional stdio-specific
}

%% TCP transport  
#{
    type => tcp,
    server_id => my_server,
    host => "127.0.0.1",
    port => 8080,
    keepalive => true,
    connect_timeout => 5000,
    max_reconnect_attempts => infinity
}

%% HTTP transport
#{
    type => http,
    server_id => my_server,
    url => "https://api.example.com/mcp",
    method => post,
    headers => [{"Content-Type", "application/json"}],
    timeout => 30000
}
```

## Implementation Steps

### Step 1: Enhance Transport Behavior Interface

**Files to modify:**
- `src/erlmcp_transport.erl` (enhance existing behavior)

**Tasks:**
- [ ] Add optional callbacks (`get_info/1`, `handle_transport_call/2`)
- [ ] Define standard message format types
- [ ] Add comprehensive documentation
- [ ] Add transport validation functions

### Step 2: Standardize erlmcp_transport_stdio_new

**Files to modify:**
- `src/erlmcp_transport_stdio_new.erl`

**Tasks:**
- [ ] Ensure full compliance with transport behavior interface
- [ ] Add missing optional callbacks (`get_info/1`, etc.)
- [ ] Standardize error handling and reporting
- [ ] Ensure consistent state record format
- [ ] Add comprehensive logging

**Expected behavior:**
- Already registry-integrated ✅
- Already gen_server architecture ✅  
- Already manages stdin reader process ✅
- Needs: Standard behavior interface conformance

### Step 3: Complete Refactor of erlmcp_transport_tcp

**Files to modify:**
- `src/erlmcp_transport_tcp.erl` (major rewrite)

**Current Issues:**
- Not registry-integrated ❌
- Inconsistent error handling ❌
- Manual process management ❌

**Tasks:**
- [ ] Complete rewrite to follow standard gen_server pattern
- [ ] Implement proper registry integration
- [ ] Add reconnection logic with supervisor integration
- [ ] Add comprehensive error handling and recovery
- [ ] Implement standard behavior callbacks
- [ ] Add connection management and buffering

**Key Features to Implement:**
```erlang
-record(state, {
    transport_id :: atom(),
    server_id :: atom(),
    config :: map(),
    socket :: gen_tcp:socket() | undefined,
    host :: inet:hostname(),
    port :: inet:port_number(),
    buffer = <<>> :: binary(),
    connected = false :: boolean(),
    reconnect_timer :: reference() | undefined
}).
```

### Step 4: Simplify and Refactor erlmcp_transport_http

**Files to modify:**
- `src/erlmcp_transport_http.erl` (major simplification)

**Current Issues:**
- Complex, non-standard architecture ❌
- Not registry-integrated ❌
- Overcomplicated for MCP use case ❌

**Tasks:**
- [ ] Simplify architecture for MCP request/response pattern
- [ ] Implement registry integration
- [ ] Add proper error handling and timeouts
- [ ] Focus on HTTP client functionality suitable for MCP
- [ ] Implement standard behavior callbacks
- [ ] Add proper HTTP options handling

**Simplified State:**
```erlang
-record(state, {
    transport_id :: atom(),
    server_id :: atom(),
    config :: map(),
    url :: string(),
    headers :: [{string(), string()}],
    http_options :: [term()],
    request_options :: [term()]
}).
```

### Step 5: Enhance Transport Supervisor

**Files to modify:**
- `src/erlmcp_transport_sup.erl`

**Tasks:**
- [ ] Enhance child management with better error handling
- [ ] Add transport module resolution function
- [ ] Implement proper restart strategies
- [ ] Add transport health monitoring
- [ ] Improve logging and error reporting

**Key Enhancement:**
```erlang
start_child(TransportId, Type, Config) ->
    Module = transport_module(Type),
    
    ChildSpec = #{
        id => TransportId,
        start => {Module, start_link, [TransportId, Config]},
        restart => permanent,  %% Changed from temporary
        shutdown => 5000,
        type => worker,
        modules => [Module]
    },
    
    case supervisor:start_child(?MODULE, ChildSpec) of
        {ok, TransportPid} ->
            logger:info("Started transport ~p (~p) with pid ~p", 
                       [TransportId, Type, TransportPid]),
            {ok, TransportPid};
        {error, _} = Error ->
            logger:error("Failed to start transport ~p (~p): ~p", 
                        [TransportId, Type, Error]),
            Error
    end.

transport_module(stdio) -> erlmcp_transport_stdio_new;  %% Note: still _new in Phase 3
transport_module(tcp) -> erlmcp_transport_tcp;
transport_module(http) -> erlmcp_transport_http.
```

### Step 6: Add Configuration Validation

**Files to modify:**
- `src/erlmcp.erl` (high-level API)

**Tasks:**
- [ ] Implement comprehensive config validation
- [ ] Add configuration schema documentation
- [ ] Create validation functions for each transport type
- [ ] Add helpful error messages

**Validation Functions:**
```erlang
validate_transport_config(#{type := stdio} = Config) ->
    RequiredFields = [type],
    OptionalFields = [server_id, test_mode],
    validate_fields(Config, RequiredFields, OptionalFields);

validate_transport_config(#{type := tcp} = Config) ->
    RequiredFields = [type, host, port],
    OptionalFields = [server_id, keepalive, connect_timeout, max_reconnect_attempts],
    validate_fields(Config, RequiredFields, OptionalFields);

validate_transport_config(#{type := http} = Config) ->
    RequiredFields = [type, url],
    OptionalFields = [server_id, method, headers, timeout],
    validate_fields(Config, RequiredFields, OptionalFields).
```

### Step 7: Enhance High-Level API

**Files to modify:**
- `src/erlmcp.erl`

**Tasks:**
- [ ] Add enhanced transport creation with validation
- [ ] Add new convenience functions for TCP and HTTP
- [ ] Improve error handling and reporting
- [ ] Add transport binding management functions

**Key API Enhancements:**
```erlang
%% Enhanced transport creation with validation
-spec start_transport(transport_id(), transport_type(), map()) -> 
    {ok, pid()} | {error, term()}.
start_transport(TransportId, Type, Config) ->
    case validate_transport_config(Config#{type => Type}) of
        ok ->
            case erlmcp_transport_sup:start_child(TransportId, Type, Config) of
                {ok, TransportPid} ->
                    logger:info("Started transport ~p", [TransportId]),
                    {ok, TransportPid};
                {error, _} = Error ->
                    Error
            end;
        {error, _} = ValidationError ->
            ValidationError
    end.

%% New convenience functions
start_tcp_setup(ServerId, ServerConfig, TcpConfig) -> ...
start_http_setup(ServerId, ServerConfig, HttpConfig) -> ...
```

### Step 8: Add Comprehensive Testing

**Files to create/modify:**
- `test/erlmcp_transport_stdio_new_SUITE.erl`
- `test/erlmcp_transport_tcp_SUITE.erl`
- `test/erlmcp_transport_http_SUITE.erl`
- `test/erlmcp_transport_behavior_SUITE.erl`

**Tasks:**
- [ ] Test all behavior callbacks for each transport
- [ ] Test registry integration for each transport
- [ ] Test error handling and recovery scenarios
- [ ] Test configuration validation
- [ ] Test supervisor integration and restart scenarios

## Success Criteria

### Technical Success
- [ ] All transports follow standard behavior interface
- [ ] All transports are supervised gen_servers
- [ ] All transports integrate with registry for message routing
- [ ] No code duplication between transport implementations
- [ ] Consistent error handling and recovery across transports

### Functional Success  
- [ ] All existing transport functionality preserved
- [ ] Transport failures don't affect other transports
- [ ] Transport failures don't bring down servers
- [ ] Automatic recovery from transport failures
- [ ] Graceful handling of all error conditions

### API Success
- [ ] Consistent API across all transport types
- [ ] Easy transport configuration and validation
- [ ] Clear error messages and debugging information
- [ ] Backward compatibility for public APIs
- [ ] Comprehensive convenience functions

### Testing Success
- [ ] >90% code coverage for all transport modules
- [ ] All behavior callbacks tested
- [ ] All failure scenarios covered
- [ ] Integration tests with registry and supervisor
- [ ] Performance regression tests pass

## Important Notes and Constraints

### What NOT to do in Phase 3
- **Do NOT remove legacy components yet** - that's Phase 5
  - Keep `erlmcp_stdio_server` - just ensure it still works
  - Keep `erlmcp_stdio` - just ensure it still works  
  - Keep `erlmcp_transport_stdio` - just ensure it still works
- **Do NOT rename modules yet** - that's Phase 6
  - Keep `erlmcp_transport_stdio_new` name for now
- **Do NOT update examples yet** - that's Phase 4

### Phase 3 Scope Boundaries
- **Focus ONLY on transport standardization**
- **Ensure all existing functionality continues to work**
- **Add new standardized interfaces without breaking old ones**
- **Comprehensive testing of all changes**

### Dependencies and Integration Points
- **Registry Integration**: All transports must work with existing `erlmcp_registry`
- **Supervisor Integration**: All transports must work with existing `erlmcp_transport_sup`
- **Server Integration**: All transports must work with existing `erlmcp_server` via registry
- **Configuration**: Must work with existing configuration patterns while adding validation

## Testing Strategy

### Unit Testing
- Test each transport behavior callback in isolation
- Mock registry and supervisor dependencies
- Test all error conditions and edge cases
- Test configuration validation thoroughly

### Integration Testing
- Test transport registration and deregistration
- Test message routing through registry
- Test supervisor restart scenarios
- Test transport failure and recovery

### System Testing
- Test complete server + transport + registry integration
- Test multiple transports simultaneously
- Test under load and stress conditions
- Test with various configuration combinations

## Deliverables

At the end of Phase 3, we should have:

1. **Enhanced Transport Behavior Interface** - `erlmcp_transport.erl`
2. **Standardized STDIO Transport** - `erlmcp_transport_stdio_new.erl`
3. **Refactored TCP Transport** - `erlmcp_transport_tcp.erl`
4. **Simplified HTTP Transport** - `erlmcp_transport_http.erl`
5. **Enhanced Transport Supervisor** - `erlmcp_transport_sup.erl`
6. **Enhanced High-Level API** - `erlmcp.erl`
7. **Comprehensive Test Suite** - All transport tests
8. **Updated Documentation** - Transport behavior and usage docs

## Next Phase Preview

**Phase 4** will focus on updating examples and documentation to use the new standardized transport architecture, making it easy for users to understand and adopt the new patterns.

This implementation plan provides everything needed to complete Phase 3 transport standardization while maintaining system stability and preparing for future phases.