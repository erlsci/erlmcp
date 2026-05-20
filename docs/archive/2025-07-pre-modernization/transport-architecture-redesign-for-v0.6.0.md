# erlmcp Transport Architecture Design (Post-OTP Redesign)

## Overview

This document outlines the design for completing the OTP supervision architecture by standardizing and improving the transport layer. With Phase 2 complete (registry-based message routing and server decoupling), Phase 3 focuses on creating a robust, standardized transport system that integrates seamlessly with the OTP supervision tree.

## Current State After OTP Redesign

### What We Have Now (Post-Phase 2)

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

### Legacy Components to Remove

```
erlmcp_stdio_server ❌ (duplicated protocol logic)
erlmcp_stdio ❌ (wrapper, inconsistent API)
erlmcp_transport_stdio ❌ (old, not registry-integrated)
```

### Problems Remaining from Pre-OTP Architecture

1. **Inconsistent Transport Interfaces**: Different APIs and patterns across transports
2. **Legacy Code Duplication**: `erlmcp_stdio_server` still duplicates MCP protocol logic
3. **Non-Standard Integration**: Some transports don't integrate properly with registry
4. **Missing Supervision**: Not all transports are properly supervised
5. **Inconsistent Error Handling**: Different failure modes and recovery strategies

## Phase 3 Goals: Transport Standardization

Building on the OTP supervision foundation from Phase 2, Phase 3 aims to:

1. **Standardize Transport Behavior**: Common interface for all transports
2. **Complete OTP Integration**: All transports as supervised gen_servers
3. **Registry Integration**: All transports route through `erlmcp_registry`
4. **Eliminate Legacy Components**: Remove duplicated protocol implementations
5. **Consistent Error Handling**: Standard failure and recovery patterns

## Standardized Transport Architecture

### 1. Transport Behavior Interface

```erlang
%% Enhanced erlmcp_transport.erl
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

### 2. Standard Transport Gen_Server Pattern

All transports follow this pattern:

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

%% Standard gen_server callbacks
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
    %% Route to server via registry
    case State#state.server_id of
        undefined ->
            logger:warning("Transport ~p received data but no server bound", 
                          [State#state.transport_id]);
        ServerId ->
            erlmcp_registry:route_to_server(ServerId, State#state.transport_id, Data)
    end,
    {noreply, State}.

%% Standard helper functions
notify_error(Type, Reason, State) ->
    logger:error("Transport ~p error ~p: ~p", [State#state.transport_id, Type, Reason]),
    %% Could also notify registry/server of error
    ok.
```

### 3. Registry Integration

All transports integrate consistently with the registry:

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

## Specific Transport Implementations

### 1. erlmcp_transport_stdio_new → erlmcp_transport_stdio

**Status**: Nearly complete, needs final standardization

**Key Features**:
- Registry-integrated ✅
- Gen_server architecture ✅  
- Stdin reader process management ✅
- Needs: Standard behavior interface conformance

**Improvements Needed**:
```erlang
%% Add standard transport behavior implementation
-behaviour(erlmcp_transport).

%% Standardize init/2 callback
init(TransportId, Config) ->
    % Current implementation already close to standard
    
%% Add get_info/1 callback
get_info(State) ->
    #{
        type => stdio,
        status => connected,
        peer => standard_io
    }.
```

### 2. erlmcp_transport_tcp → Needs Major Refactoring

**Current Issues**:
- Not registry-integrated ❌
- Inconsistent error handling ❌
- Manual process management ❌

**Required Changes**:
```erlang
%% Refactor to standard pattern
-module(erlmcp_transport_tcp).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

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

%% Standard init with registry integration
init([TransportId, Config]) ->
    process_flag(trap_exit, true),
    
    Host = maps:get(host, Config),
    Port = maps:get(port, Config),
    ServerId = maps:get(server_id, Config, undefined),
    
    State = #state{
        transport_id = TransportId,
        server_id = ServerId,
        config = Config,
        host = Host,
        port = Port
    },
    
    %% Register with registry first
    TransportConfig = Config#{type => tcp},
    ok = erlmcp_registry:register_transport(TransportId, self(), TransportConfig),
    
    %% Then attempt connection
    self() ! connect,
    {ok, State}.
```

### 3. erlmcp_transport_http → Needs Major Refactoring

**Current Issues**:
- Complex, non-standard architecture ❌
- Not registry-integrated ❌
- Overcomplicated for MCP use case ❌

**Simplified Approach**:
```erlang
%% HTTP for MCP is typically request/response, not persistent
%% Simplify to focus on MCP use cases

-module(erlmcp_transport_http).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

-record(state, {
    transport_id :: atom(),
    server_id :: atom(),
    config :: map(),
    url :: string(),
    headers :: [{string(), string()}],
    http_options :: [term()],
    request_options :: [term()]
}).

%% Simplified init for MCP use cases
init([TransportId, Config]) ->
    Url = maps:get(url, Config),
    Headers = maps:get(headers, Config, []),
    
    State = #state{
        transport_id = TransportId,
        server_id = maps:get(server_id, Config),
        config = Config,
        url = Url,
        headers = normalize_headers(Headers),
        http_options = build_http_options(Config),
        request_options = build_request_options(Config)
    },
    
    %% Register with registry
    TransportConfig = Config#{type => http},
    ok = erlmcp_registry:register_transport(TransportId, self(), TransportConfig),
    
    {ok, State}.
```

## Supervision Integration

### 1. Transport Supervisor Enhancement

```erlang
%% erlmcp_transport_sup.erl enhancements
-module(erlmcp_transport_sup).
-behaviour(supervisor).

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

transport_module(stdio) -> erlmcp_transport_stdio;
transport_module(tcp) -> erlmcp_transport_tcp;
transport_module(http) -> erlmcp_transport_http.
```

### 2. Failure Handling Strategy

```erlang
%% Transport failures are now handled by supervision tree
%% Registry cleans up on process death
%% Supervisor restarts according to strategy

%% In erlmcp_registry.erl
handle_info({'DOWN', _MonitorRef, process, Pid, Reason}, State) ->
    case maps:get(Pid, State#registry_state.monitors, undefined) of
        {TransportId, transport} ->
            logger:warning("Transport ~p (pid ~p) died: ~p", 
                          [TransportId, Pid, Reason]),
            NewState = cleanup_transport(TransportId, Pid, State),
            {noreply, NewState};
        % ... handle server deaths similarly
    end.
```

## Configuration Standardization

### 1. Unified Configuration Schema

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

### 2. Configuration Validation

```erlang
%% In erlmcp.erl high-level API
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

## Legacy Component Removal Plan

### 1. Remove erlmcp_stdio_server

**Why Remove**: Duplicates MCP protocol logic that's already in `erlmcp_server`

**Impact**: All stdio use cases now go through `erlmcp_server` + `erlmcp_transport_stdio`

**Migration**:
```erlang
%% Old approach
{ok, Pid} = erlmcp_stdio_server:start_link(Options),
erlmcp_stdio_server:add_tool(Pid, Name, Handler).

%% New approach  
{ok, ServerPid} = erlmcp:start_server(my_server, ServerConfig),
{ok, TransportPid} = erlmcp:start_transport(my_transport, stdio, TransportConfig),
ok = erlmcp:bind_transport_to_server(my_transport, my_server),
ok = erlmcp:add_tool(my_server, Name, Handler).
```

### 2. Remove erlmcp_stdio

**Why Remove**: Wrapper around deprecated `erlmcp_stdio_server`

**Impact**: All examples and tests updated to use `erlmcp` high-level API

### 3. Remove erlmcp_transport_stdio (old)

**Why Remove**: Replaced by `erlmcp_transport_stdio_new` (renamed to `erlmcp_transport_stdio`)

**Impact**: No external API changes, internal refactoring only

## High-Level API Updates

### 1. Enhanced erlmcp Module

```erlang
-module(erlmcp).

%% Application management API - Enhanced for Phase 3
-export([
    start_server/1, start_server/2, stop_server/1, list_servers/0,
    start_transport/3, stop_transport/1, list_transports/0,
    bind_transport_to_server/2, unbind_transport/1
]).

%% Server operations API - Unchanged
-export([
    add_resource/3, add_resource/4,
    add_tool/3, add_tool/4,
    add_prompt/3, add_prompt/4
]).

%% Configuration API - Enhanced
-export([
    get_server_config/1, update_server_config/2,
    get_transport_config/1, update_transport_config/2,
    validate_transport_config/1  %% New
]).

%% Convenience functions - Updated
-export([
    start_stdio_setup/2, start_tcp_setup/3, start_http_setup/3,  %% New http_setup
    setup_server_components/2, quick_stdio_server/3
]).

%% Enhanced transport creation with validation
-spec start_transport(transport_id(), transport_type(), map()) -> 
    {ok, pid()} | {error, term()}.
start_transport(TransportId, Type, Config) ->
    %% Validate configuration first
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
```

### 2. Convenience Functions

```erlang
%% Enhanced convenience functions for common patterns

%% Complete stdio setup (unchanged)
start_stdio_setup(ServerId, Config) ->
    case start_server(ServerId, Config) of
        {ok, ServerPid} ->
            TransportId = create_transport_id(ServerId, <<"stdio">>),
            TransportConfig = #{server_id => ServerId, type => stdio},
            case start_transport(TransportId, stdio, TransportConfig) of
                {ok, TransportPid} ->
                    ok = bind_transport_to_server(TransportId, ServerId),
                    {ok, #{server => ServerPid, transport => TransportPid}};
                {error, TransportError} ->
                    stop_server(ServerId),
                    {error, TransportError}
            end;
        {error, _} = ServerError ->
            ServerError
    end.

%% New TCP setup convenience function
start_tcp_setup(ServerId, ServerConfig, TcpConfig) ->
    case start_server(ServerId, ServerConfig) of
        {ok, ServerPid} ->
            TransportId = create_transport_id(ServerId, <<"tcp">>),
            TransportConfig = TcpConfig#{server_id => ServerId, type => tcp},
            case start_transport(TransportId, tcp, TransportConfig) of
                {ok, TransportPid} ->
                    ok = bind_transport_to_server(TransportId, ServerId),
                    {ok, #{server => ServerPid, transport => TransportPid}};
                {error, TransportError} ->
                    stop_server(ServerId),
                    {error, TransportError}
            end;
        {error, _} = ServerError ->
            ServerError
    end.

%% New HTTP setup convenience function
start_http_setup(ServerId, ServerConfig, HttpConfig) ->
    case start_server(ServerId, ServerConfig) of
        {ok, ServerPid} ->
            TransportId = create_transport_id(ServerId, <<"http">>),
            TransportConfig = HttpConfig#{server_id => ServerId, type => http},
            case start_transport(TransportId, http, TransportConfig) of
                {ok, TransportPid} ->
                    ok = bind_transport_to_server(TransportId, ServerId),
                    {ok, #{server => ServerPid, transport => TransportPid}};
                {error, TransportError} ->
                    stop_server(ServerId),
                    {error, TransportError}
            end;
        {error, _} = ServerError ->
            ServerError
    end.
```

## Phase 3 Implementation Plan

### Step 1: Standardize Transport Behavior ✅ (Partially Done)
- [x] Create enhanced `erlmcp_transport.erl` behavior interface
- [x] Define standard message formats  
- [x] Document transport gen_server patterns
- [ ] Add transport validation functions

### Step 2: Refactor erlmcp_transport_stdio_new
- [ ] Ensure full compliance with transport behavior
- [ ] Add missing optional callbacks (`get_info/1`, etc.)
- [ ] Standardize error handling and reporting
- [ ] Add comprehensive tests for all behavior callbacks

### Step 3: Refactor erlmcp_transport_tcp
- [ ] Completely rewrite to follow standard gen_server pattern
- [ ] Implement proper registry integration
- [ ] Add reconnection logic with supervisor integration
- [ ] Add comprehensive error handling and recovery

### Step 4: Refactor erlmcp_transport_http  
- [ ] Simplify architecture for MCP use cases
- [ ] Implement registry integration
- [ ] Add proper error handling and timeouts
- [ ] Focus on request/response pattern suitable for MCP

### Step 5: Update Transport Supervisor
- [ ] Enhance `erlmcp_transport_sup` with better child management
- [ ] Add transport module resolution
- [ ] Implement proper restart strategies
- [ ] Add transport health monitoring

### Step 6: Configuration and Validation
- [ ] Implement comprehensive config validation
- [ ] Add configuration schema documentation
- [ ] Create migration helpers for old configurations
- [ ] Add configuration testing utilities

### Step 7: Remove Legacy Components
- [ ] Remove `erlmcp_stdio_server.erl`
- [ ] Remove `erlmcp_stdio.erl` 
- [ ] Remove `erlmcp_transport_stdio.erl` (old version)
- [ ] Update all references and dependencies

### Step 8: Update Examples and Documentation
- [ ] Update all examples to use new transport architecture
- [ ] Revise documentation to reflect OTP supervision patterns
- [ ] Create transport development guide
- [ ] Add troubleshooting documentation

## Success Criteria

### Technical Success
- [ ] All transports follow standard behavior interface
- [ ] All transports are supervised gen_servers
- [ ] All transports integrate with registry for message routing
- [ ] No code duplication between transport implementations
- [ ] Consistent error handling and recovery across transports

### Reliability Success  
- [ ] Transport failures don't affect other transports
- [ ] Transport failures don't bring down servers
- [ ] Automatic recovery from transport failures
- [ ] Graceful handling of all error conditions
- [ ] No message loss during transport restarts

### API Success
- [ ] Consistent API across all transport types
- [ ] Easy transport configuration and validation
- [ ] Clear error messages and debugging information
- [ ] Backward compatibility for public APIs (where possible)
- [ ] Comprehensive convenience functions

### Performance Success
- [ ] No performance regression from OTP refactoring
- [ ] Efficient message routing through registry
- [ ] Low overhead from supervision and monitoring
- [ ] Transport-specific optimizations where beneficial

## Integration with Phases 4-6

### Phase 4: Examples and Documentation
With standardized transports, all examples can demonstrate:
- Consistent patterns across transport types
- Proper OTP supervision usage
- Clear error handling examples
- Transport-specific feature usage

### Phase 5: Legacy Code Removal
Phase 3 makes legacy removal clean:
- No more protocol duplication
- Clear migration path established
- All functionality preserved in new architecture

### Phase 6: Module Renaming
With legacy code removed, clean renames:
- `erlmcp_transport_stdio_new` → `erlmcp_transport_stdio`
- Clean module namespace
- Consistent naming patterns

## Long-Term Transport Extensibility

### New Transport Types
The standardized architecture makes new transports straightforward:

```erlang
%% WebSocket transport example
-module(erlmcp_transport_websocket).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

%% Standard pattern, transport-specific implementation
init([TransportId, Config]) ->
    %% WebSocket-specific initialization
    %% Registry registration  
    %% Standard state setup
    
%% Follows all standard patterns established in Phase 3
```

### Advanced Features
- Transport multiplexing (multiple connections per transport)
- Transport load balancing
- Transport-specific metrics and monitoring  
- Custom transport authentication and security

## Conclusion

Phase 3 completes the OTP supervision architecture by standardizing the transport layer. Building on Phase 2's registry-based message routing, we eliminate code duplication, create consistent interfaces, and establish robust failure handling patterns.

The result is a clean, extensible transport architecture that:
- Integrates seamlessly with OTP supervision
- Provides consistent APIs across all transport types  
- Enables easy addition of new transport types
- Maintains excellent performance and reliability
- Sets the foundation for long-term project growth

With Phase 3 complete, erlmcp will have a production-ready architecture suitable for enterprise deployment while remaining approachable for development and testing scenarios.
