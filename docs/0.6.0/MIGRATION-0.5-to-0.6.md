# Migration Guide: erlmcp 0.5.x to 0.6.0

erlmcp 0.6.0 is an intentional clean break from 0.5.x. The 0.5.x API is not
preserved — this is a full re-core, not an incremental upgrade.

## Removed Modules

| Module | Replacement |
|--------|-------------|
| `erlmcp_server` | `erlmcp_server_session` (gen_statem) |
| `erlmcp_stdio_server` | `erlmcp_transport_stdio` + `erlmcp_server_session` |
| `erlmcp_client` | `erlmcp_client_session` (gen_statem) |
| `erlmcp_server_new` | Deleted (was a parallel fork) |
| `erlmcp_transport_stdio_new` | Deleted (was a parallel fork) |

## API Mapping

| 0.5.x | 0.6.0 |
|-------|-------|
| `erlmcp_server:start_link/2` | `erlmcp:start_server/2` |
| `erlmcp_server:add_tool/3` | `erlmcp:add_tool(Session, ToolSpec)` |
| `erlmcp_client:start_link/2` | `erlmcp_client_session:start_link(Opts)` |
| `erlmcp_client:initialize/3` | `erlmcp_client_session:initialize(Session, Params)` |
| `erlmcp_client:list_tools/1` | `erlmcp_client_session:list_tools(Session)` |
| `erlmcp_client:call_tool/3` | `erlmcp_client_session:call_tool(Session, Name, Args)` |
| `erlmcp_stdio_server:start_link/1` | `erlmcp:start_stdio_setup(Id, Config)` |

## Tool Registration

**0.5.x:**
```erlang
erlmcp_server:add_tool(Server, <<"name">>, fun handler/2).
```

**0.6.0:**
```erlang
erlmcp:add_tool(Server, #{
    name => <<"name">>,
    description => <<"What it does">>,
    input_schema => erlmcp_schema:object([
        erlmcp_schema:field(<<"arg">>, erlmcp_schema:string(), [required])
    ]),
    handler => fun(Args, Ctx) -> {ok, erlmcp:text(<<"result">>)} end
}).
```

Or via a handler behaviour module:
```erlang
-behaviour(erlmcp_server_handler).
-export([tools/0, handle_tool/3]).
tools() -> [#{name => ..., input_schema => ...}].
handle_tool(<<"name">>, Args, Ctx) -> {ok, erlmcp:text(<<"result">>)}.
```

## Key Architecture Changes

1. **Sessions are `gen_statem`** — explicit state machine with lifecycle
   states (`uninitialized → operational → shutting_down`)

2. **Per-request worker isolation** — every tool call/resource read runs in
   a monitored worker process; crashes become JSON-RPC errors

3. **Cancellation is process termination** — no tokens, no cooperative
   checks; `notifications/cancelled` kills the worker

4. **Transport behaviour** — stdio, TCP, HTTP, streamable HTTP all implement
   `erlmcp_transport`; the session is transport-agnostic

5. **Validate at the edge** — input validated via `jesse` against
   `input_schema` before dispatch; handlers can assume valid data

6. **Registry off the hot path** — discovery and binding only; sessions talk
   to transports directly

7. **JSON via `erlmcp_codec` only** — no `jsx:` calls outside the codec

## Porting a 0.5 Server

1. Replace `erlmcp_server:start_link` with `erlmcp:start_server`
2. Replace `add_tool/3` calls with `add_tool/2` using the data-driven map
3. Add `input_schema` to each tool (use `erlmcp_schema` builder)
4. Update handlers to return `{ok, erlmcp:text(Result)}` content items
5. Replace stdio server with `erlmcp:start_stdio_setup/2`

## Porting a 0.5 Client

1. Replace `erlmcp_client:start_link` with `erlmcp_client_session:start_link`
2. Replace `initialize/3` with `initialize/2`
3. Use the new API: `list_tools/1`, `call_tool/3`, `list_resources/1`, etc.
4. Register callback handlers before `initialize` for sampling/roots/elicitation
