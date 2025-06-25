# erlmcp Architecture

## Overview

The erlmcp SDK is built on Erlang/OTP principles, providing a robust and fault-tolerant implementation of the Model Context Protocol.

## System Components

```
┌─────────────────┐     ┌─────────────────┐
│   MCP Client    │     │   MCP Server    │
├─────────────────┤     ├─────────────────┤
│ erlmcp_client   │────▶│ erlmcp_server   │
│ (gen_server)    │     │ (gen_server)    │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│ Transport Layer │     │ Transport Layer │
├─────────────────┤     ├─────────────────┤
│ - stdio         │     │ - stdio         │
│ - TCP           │     │ - TCP           │
│ - HTTP          │     │ - HTTP          │
└─────────────────┘     └─────────────────┘
```

## Core Modules

### Protocol Layer
- **erlmcp_json_rpc** - JSON-RPC 2.0 message encoding/decoding
- **erlmcp.hrl** - Protocol type definitions and records

### Client Components
- **erlmcp_client** - Main client gen_server
- **erlmcp_client_sup** - Client supervisor for managing multiple connections

### Server Components
- **erlmcp_server** - Main server gen_server
- **erlmcp_server_sup** - Server supervisor

### Transport Modules
- **erlmcp_transport_stdio** - Standard I/O transport
- **erlmcp_transport_tcp** - TCP socket transport
- **erlmcp_transport_http** - HTTP transport

## Design Principles

### 1. Process Isolation
Each connection runs in its own process, ensuring:
- Fault isolation
- Independent state management
- Concurrent operation

### 2. Supervision Trees
```
erlmcp_sup
├── erlmcp_client_sup
│   └── erlmcp_client (dynamic)
└── erlmcp_server_sup
    └── erlmcp_server (dynamic)
```

### 3. Message Flow

**Client Request Flow:**
1. API call → gen_server:call
2. Encode request (JSON-RPC)
3. Send via transport
4. Await response
5. Decode response
6. Return to caller

**Server Request Flow:**
1. Receive message from transport
2. Decode request
3. Route to handler
4. Execute handler
5. Encode response
6. Send response

### 4. State Management

**Client State:**
```erlang
#state{
    transport :: module(),
    transport_state :: term(),
    capabilities :: #mcp_server_capabilities{},
    request_id :: integer(),
    pending_requests :: map(),
    subscriptions :: sets:set()
}
```

**Server State:**
```erlang
#state{
    transport :: module(),
    transport_state :: term(),
    capabilities :: #mcp_server_capabilities{},
    resources :: map(),
    tools :: map(),
    prompts :: map(),
    subscriptions :: map()
}
```

## Extension Points

### Custom Transports
Implement the transport behavior:
```erlang
-callback init(Opts :: map()) -> {ok, State} | {error, Reason}.
-callback send(State, Data :: binary()) -> ok | {error, Reason}.
-callback close(State) -> ok.
```

### Resource Handlers
```erlang
-type resource_handler() :: fun((Uri :: binary()) -> 
    binary() | #mcp_content{}).
```

### Tool Handlers
```erlang
-type tool_handler() :: fun((Args :: map()) -> 
    binary() | #mcp_content{} | [#mcp_content{}]).
```

## Performance Considerations

1. **Process Pooling** - Use poolboy for connection pooling
2. **ETS for Caching** - Cache frequently accessed resources
3. **Binary Handling** - Use binary strings for efficiency
4. **Lazy Evaluation** - Handlers are called only when needed

## Security Model

- Transport-level security (TLS for TCP/HTTP)
- Input validation via JSON Schema
- Capability-based access control
- No direct code execution