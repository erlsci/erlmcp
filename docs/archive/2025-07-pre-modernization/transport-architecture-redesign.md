# erlmcp Transport Architecture Design

## Overview

This document outlines the design for returning to and improving the `erlmcp_server` + transports architecture, moving away from transport-specific server implementations toward a clean, pluggable transport system.

## Current Architecture Analysis

### What We Have Now

```
erlmcp_server (full-featured, transport-agnostic)
    ↓ uses
erlmcp_transport_stdio
erlmcp_transport_tcp  
erlmcp_transport_http

VS

erlmcp_stdio_server (stdio-specific, duplicated logic)
erlmcp_stdio (wrapper around erlmcp_stdio_server)
```

### Problems with Current Approach

1. **Code Duplication**: `erlmcp_stdio_server` reimplements MCP protocol logic
2. **Inconsistent APIs**: Different interfaces for different transports
3. **Maintenance Overhead**: Multiple protocol implementations to maintain
4. **Feature Divergence**: stdio-specific server lacks features of main server

## Benefits of erlmcp_server + Transports

### 1. Clean Separation of Concerns
- **Protocol Logic**: All MCP protocol handling in `erlmcp_server` 
- **Transport Logic**: Each transport handles its own communication method
- **No Duplication**: Single implementation of MCP protocol

### 2. Consistent API
- Same API regardless of transport
- Same capabilities and features across all transports
- Easier to test and maintain

### 3. Transport Pluggability
- Easy to add new transports (WebSocket, Unix sockets, etc.)
- Transport-specific optimizations possible
- Clean interface contract

## Areas for Improvement

### 1. Transport Interface Standardization

Currently the transport interface is inconsistent. Proposed enhancement:

```erlang
%% Current transport behavior (from erlmcp_transport.erl)
-callback init(Opts) -> {ok, State} | {error, Reason}.
-callback send(State, Data) -> ok | {error, Reason}.
-callback close(State) -> ok.

%% Proposed enhanced interface
-callback init(Owner, Opts) -> {ok, State} | {error, Reason}.
-callback send(State, Data) -> ok | {error, Reason}.
-callback close(State) -> ok.
-callback get_info(State) -> #{transport_type := atom(), peer := term(), ...}.

%% Optional callbacks for advanced features
-optional_callbacks([get_info/1]).
```

### 2. Better Process Architecture

Current stdio transport spawns a reader process, but architecture could be more consistent:

```erlang
%% Option A: All transports are gen_servers
erlmcp_server (gen_server)
    ↓ links to
erlmcp_transport_stdio (gen_server)
    ↓ spawns
stdin_reader_process

%% Option B: Transports are modules with supervised processes
erlmcp_server (gen_server)
    ↓ supervises
transport_sup
    ↓ supervises transport-specific processes
```

### 3. Unified Configuration

Make transport configuration more consistent:

```erlang
%% Current mixed approach
{stdio, []}
{tcp, #{host => "127.0.0.1", port => 8080}}
{http, #{url => "https://api.example.com"}}

%% Proposed unified approach
{stdio, #{}}
{tcp, #{host => "127.0.0.1", port => 8080}}
{http, #{url => "https://api.example.com"}}
%% All transports get maps, even if empty
```

### 4. Enhanced Error Handling

Better transport error reporting and recovery:

```erlang
%% Transport can report different types of issues
{transport_error, connection_lost, Reason}
{transport_error, send_failed, Reason}  
{transport_error, protocol_error, Reason}

%% Server can decide how to handle each type
%% - Retry for connection_lost
%% - Log and continue for send_failed
%% - Restart for protocol_error
```

### 5. Transport-Specific Features

Allow transports to expose their unique capabilities:

```erlang
%% HTTP transport might support
http_transport:set_headers(State, Headers)
http_transport:get_response_code(State)

%% TCP transport might support  
tcp_transport:get_peer_info(State)
tcp_transport:set_keepalive(State, Enabled)

%% stdio transport might support
stdio_transport:redirect_stderr(State, Enabled)
```

## Proposed Improvements

### 1. Enhanced Transport Behavior

```erlang
%% Enhanced erlmcp_transport.erl
-callback init(pid(), transport_opts()) -> 
    {ok, State} | {error, Reason}.

-callback send(State, iodata()) -> 
    ok | {error, Reason}.

-callback close(State) -> ok.

-callback get_info(State) -> 
    #{type => atom(), status => atom(), peer => term()}.

%% Optional advanced features
-callback handle_call(Request, State) -> 
    {reply, Reply, State} | {error, Reason}.

-optional_callbacks([handle_call/2]).
```

### 2. Improved erlmcp_server Transport Integration

```erlang
%% Better transport lifecycle management
init_transport(TransportOpts) ->
    case Transport:init(self(), Opts) of
        {ok, State} ->
            monitor_transport(Transport, State),
            {ok, Transport, State};
        Error -> Error
    end.

monitor_transport(Transport, State) ->
    %% Set up monitoring, heartbeats, etc.
    %% Transport-agnostic monitoring
    ok.
```

### 3. Standardized Transport Messages

```erlang
%% All transports send consistent messages to server
{transport_message, Data}           %% Incoming data
{transport_connected, Info}         %% Connection established  
{transport_disconnected, Reason}    %% Connection lost
{transport_error, Type, Reason}     %% Transport-specific error
```

### 4. Configuration Schema

```erlang
%% Validation for transport options
validate_transport_opts({stdio, Opts}) ->
    validate_stdio_opts(Opts);
validate_transport_opts({tcp, Opts}) ->
    validate_tcp_opts(Opts);
validate_transport_opts({http, Opts}) ->
    validate_http_opts(Opts).
```

## Migration Benefits

### Immediate Benefits
1. **Eliminate Code Duplication** - Remove `erlmcp_stdio_server`
2. **Consistent API** - Same interface for all transports  
3. **Better Testing** - Single protocol implementation to test
4. **Cleaner Architecture** - Clear separation of concerns

### Long-term Benefits
1. **Easier Extension** - New transports are straightforward
2. **Better Performance** - Transport-specific optimizations
3. **Enhanced Features** - Transport capabilities exposed cleanly
4. **Simpler Maintenance** - One protocol implementation

## Implementation Plan

### Phase 1: Enhance Transport Interface
- [ ] Update `erlmcp_transport.erl` behavior
- [ ] Standardize transport initialization
- [ ] Implement consistent message format
- [ ] Add transport info/status reporting

### Phase 2: Improve erlmcp_server Integration  
- [ ] Enhanced transport lifecycle management
- [ ] Better error handling and recovery
- [ ] Consistent monitoring across transports
- [ ] Configuration validation

### Phase 3: Update Existing Transports
- [ ] Refactor `erlmcp_transport_stdio` 
- [ ] Enhance `erlmcp_transport_tcp`
- [ ] Improve `erlmcp_transport_http`
- [ ] Ensure consistent behavior across all transports

### Phase 4: Migrate Examples and Tests
- [ ] Update examples to use `erlmcp_server` exclusively
- [ ] Migrate tests to new architecture
- [ ] Remove `erlmcp_stdio_server` and `erlmcp_stdio`
- [ ] Update documentation

### Phase 5: Advanced Features
- [ ] Transport-specific capability exposure
- [ ] Advanced error recovery strategies
- [ ] Performance optimizations
- [ ] New transport implementations (WebSocket, etc.)

## Open Questions for Discussion

### 1. Process Architecture
Should transports be gen_servers or just modules with supervised processes?

**Options:**
- **A**: All transports as gen_servers - consistent but maybe heavyweight
- **B**: Transport modules with supervised helper processes - more flexible
- **C**: Hybrid approach - simple transports as modules, complex as gen_servers

### 2. Error Recovery
How aggressive should automatic reconnection be? Transport-specific or server-controlled?

**Considerations:**
- stdio: reconnection doesn't make sense
- TCP: aggressive reconnection often desired
- HTTP: depends on use case (polling vs persistent)

### 3. Feature Parity
Should we maintain 100% feature parity across transports or allow transport-specific features?

**Trade-offs:**
- Full parity: easier to test, consistent behavior
- Transport-specific features: better performance, more capabilities

### 4. Migration Path
Gradual migration or clean break from `erlmcp_stdio`?

**Options:**
- **Gradual**: Keep `erlmcp_stdio` as wrapper around `erlmcp_server` during transition
- **Clean Break**: Remove `erlmcp_stdio` entirely, update all examples/tests at once

### 5. Testing Strategy
How do we ensure all transports work identically for core MCP features?

**Approaches:**
- Common test suite that runs against all transports
- Transport-specific tests for unique features
- Integration tests with real MCP clients

## Success Criteria

### Technical Success
- [ ] Single MCP protocol implementation
- [ ] All transports use same server core
- [ ] No code duplication between transport implementations
- [ ] Consistent API across all transports
- [ ] Clean, documented transport interface

### Performance Success
- [ ] No performance regression on existing transports
- [ ] Improved performance where transport-specific optimizations are possible
- [ ] Efficient resource usage (memory, processes, etc.)

### Developer Experience Success
- [ ] Easy to add new transports
- [ ] Clear documentation and examples
- [ ] Consistent behavior across transports
- [ ] Good error messages and debugging support

### Migration Success
- [ ] All existing examples work with new architecture
- [ ] All tests pass
- [ ] No breaking changes to public API
- [ ] Clear migration path for users

## Conclusion

The `erlmcp_server` + transports architecture provides a cleaner, more maintainable foundation for the MCP library. By eliminating code duplication and providing consistent interfaces, we can deliver better reliability, performance, and developer experience while making the codebase easier to extend and maintain.

The proposed improvements address current architectural inconsistencies while providing a clear path forward for new transport implementations and advanced features.