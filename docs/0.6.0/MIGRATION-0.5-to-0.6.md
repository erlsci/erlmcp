# Migration Guide: erlmcp 0.5.x to 0.6.0

erlmcp 0.6.0 is an intentional clean break from 0.5.x. The 0.5.x API is **not**
preserved — this is a full re-core, not an incremental upgrade.

> **tl;dr for experienced Erlang developers:** `erlmcp_server` is now a pure
> catalog (ETS-backed, no gen_statem); the session (`erlmcp_server_session`) owns
> the conversation state; the `erlmcp` facade module is the primary registration
> API; tool/resource/prompt specs are data maps, not callbacks passed to `add_tool/3`.

---

## Removed modules

| 0.5.x module | Why removed | 0.6.0 replacement |
|---|---|---|
| `erlmcp_server` (old) | Fused catalog+session — wrong for HTTP | `erlmcp_server` (new, catalog only) + `erlmcp_server_session` |
| `erlmcp_stdio_server` | Transport-specific start API | `erlmcp:start_stdio_setup/2` or `erlmcp_stdio_sup:start_link/1` |
| `erlmcp_client` | Flat API, no gen_statem lifecycle | `erlmcp_client_session` |
| `erlmcp_server_new` | Parallel fork — deleted | The main `erlmcp_server` |
| `erlmcp_transport_stdio_new` | Parallel fork — deleted | `erlmcp_transport_stdio` |

---

## Starting a server

### 0.5.x

```erlang
{ok, Server} = erlmcp_server:start_link(ServerOpts, TransportOpts).
```

A single call that fused catalog and session startup.

### 0.6.0 — one-liner (recommended)

```erlang
%% From an OTP application start/2:
Config = #{
    name    => <<"my_server">>,
    version => <<"0.1.0">>,
    purpose => <<"What this server does.">>,
    tools   => my_server:tools()
},
{ok, Sup} = erlmcp_stdio_sup:start_link(Config),
register(my_server_sup, Sup).

%% In start_phase(serve, ...):
ok = erlmcp_stdio_sup:serve(whereis(my_server_sup)).
```

Or using the convenience facade (outside an OTP application):

```erlang
{ok, _Sup} = erlmcp:start_stdio_setup(my_server, #{
    name  => <<"my_server">>,
    tools => [...]
}).
```

The `start_phases` pattern in `*.app.src` is required for stdio:

```erlang
%% src/my_server.app.src
{application, my_server, [
    ...
    {start_phases, [{serve, []}]},
    ...
]}.
```

This ensures `erlmcp_stdio_sup:serve/1` is called (beginning stdin reads) only
after the full supervision tree is up — the fix for the startup race that caused
"no tools available" in 0.5.x.

---

## Registering tools

### 0.5.x

```erlang
erlmcp_server:add_tool(Server, <<"name">>, fun handler/2).
```

A positional three-argument call with no schema.

### 0.6.0

```erlang
erlmcp:add_tool(Server, #{
    name         => <<"name">>,
    description  => <<"What this tool does.">>,
    input_schema => erlmcp_schema:object([
        erlmcp_schema:field(<<"arg">>, erlmcp_schema:string(), [required])
    ]),
    handler => fun(#{<<"arg">> := Arg}, _Ctx) ->
        {ok, erlmcp:text(Arg)}
    end
}).
```

Or, more commonly in 0.6.0, config-driven through the server's start config:

```erlang
Config = #{
    tools => [
        #{
            name         => <<"name">>,
            description  => <<"What this tool does.">>,
            input_schema => erlmcp_schema:object([...]),
            handler      => fun(Args, Ctx) -> ... end
        }
    ]
}.
```

**Key difference:** tool specs are data maps. `input_schema` is required for
validation to fire. The handler signature is `fun(Args :: map(), Ctx :: map()) ->
{ok, content()} | {error, Code :: integer(), Message :: binary()}`.

### Using the handler behaviour (optional, for large handler sets)

```erlang
-module(my_handler).
-behaviour(erlmcp_server_handler).
-export([tools/0, handle_tool/3]).

tools() ->
    [#{name => <<"name">>, input_schema => ..., description => ...}].

handle_tool(<<"name">>, Args, Ctx) ->
    {ok, erlmcp:text(<<"result">>)}.
```

Register via the `handler` key in the server config:

```erlang
Config = #{handler => my_handler}.
```

---

## Registering resources

### 0.5.x

```erlang
erlmcp_server:add_resource(Server, <<"uri">>, fun handler/1).
```

### 0.6.0

```erlang
erlmcp:add_resource(Server, #{
    uri         => <<"file://example.txt">>,
    name        => <<"example">>,
    description => <<"An example resource.">>,
    mime_type   => <<"text/plain">>,
    handler     => fun(_Ctx) -> {ok, erlmcp:text(<<"content">>)} end
}).
```

Or via the server config:

```erlang
Config = #{
    resources => [
        #{uri => <<"file://example.txt">>, name => <<"example">>,
          mime_type => <<"text/plain">>,
          handler => fun(_Ctx) -> {ok, erlmcp:text(<<"content">>)} end}
    ]
}.
```

Resource templates (RFC 6570 level-1 URI templates with completion):

```erlang
erlmcp:add_resource_template(Server, #{
    uri_template => <<"weather://{city}/current">>,
    name         => <<"city_weather">>,
    description  => <<"Current weather for a city.">>,
    mime_type    => <<"application/json">>,
    completions  => #{<<"city">> => fun(Prefix) ->
        Cities = [<<"london">>, <<"paris">>, <<"tokyo">>],
        {ok, [C || C <- Cities, binary:match(C, Prefix) =/= nomatch]}
    end},
    handler => fun(#{<<"city">> := City}, _Ctx) ->
        {ok, erlmcp:text(City)}
    end
}).
```

---

## Registering prompts

### 0.5.x

No explicit prompt API in 0.5.x.

### 0.6.0

```erlang
erlmcp:add_prompt(Server, #{
    name        => <<"greet">>,
    description => <<"Generate a greeting.">>,
    arguments   => [#{name => <<"person">>, required => true,
                      description => <<"Who to greet">>}],
    handler     => fun(#{<<"person">> := Person}, _Ctx) ->
        Msg = <<"Please greet ", Person/binary, " warmly.">>,
        {ok, [erlmcp:user_message(erlmcp:text(Msg))]}
    end
}).
```

---

## Starting a client

### 0.5.x

```erlang
{ok, Client} = erlmcp_client:start_link(TransportOpts, ClientOpts).
erlmcp_client:initialize(Client, ServerName, ServerVersion).
{ok, Tools} = erlmcp_client:list_tools(Client).
{ok, Result} = erlmcp_client:call_tool(Client, <<"name">>, Args).
```

### 0.6.0

```erlang
{ok, Session} = erlmcp_client_session:start_link(#{
    transport  => erlmcp_transport_stdio,
    transport_config => #{...}
}).
{ok, _} = erlmcp_client_session:initialize(Session, #{}).
{ok, #{<<"tools">> := Tools}} = erlmcp_client_session:list_tools(Session).
{ok, Result} = erlmcp_client_session:call_tool(Session, <<"name">>, #{}).
```

For server-initiated features (sampling, roots, elicitation), register callback
handlers **before** calling `initialize/2`:

```erlang
ok = erlmcp_client_session:set_sampling_handler(Session, fun(Req, Ctx) ->
    {ok, erlmcp:assistant_message(erlmcp:text(<<"response">>))}
end).
```

---

## Key architecture changes

### 1. Sessions are `gen_statem`

`erlmcp_server_session` has three explicit states: `uninitialized`, `operational`,
`shutting_down`. Requests received before `initialize` are rejected with `-32600`.
This is correct per the spec and was not enforced in 0.5.x.

### 2. Per-request worker isolation

Every `tools/call`, `resources/read`, and `prompts/get` runs in its own monitored
`erlmcp_server_handler` worker process. A crashing handler returns `-32603` to the
client; the session survives. No head-of-line blocking.

### 3. Cancellation is process termination

When a `notifications/cancelled` arrives, the worker process for the cancelled
request is killed. No cooperative polling loops, no token bookkeeping. The worker
either finishes before the kill or it doesn't — there is no late result.

### 4. Transport behaviour

All transports implement `erlmcp_transport`. `erlmcp_transport_stdio`, the new
Cowboy-based `erlmcp_transport_http` (Streamable HTTP), `erlmcp_transport_tcp`,
and `erlmcp_transport_http` (HTTP+SSE client transport) all implement the same
`deliver/2` and `send/2` contract. The session is transport-agnostic.

### 5. Validate at the edge

Inbound payloads are validated against the MCP 2025-11-25 JSON Schema at the
session boundary using `jesse`. Handlers receive validated parameters. See
`docs/creating-an-mcp-server.md` §8 for the full validation seam description.

### 6. Registry is off the hot path

`erlmcp_registry` is a discovery and binding directory, not a message router.
Sessions and transports communicate directly after binding.

### 7. JSON via `erlmcp_codec` only

There are no `jsx:` calls outside `erlmcp_codec`. All encode/decode goes through
`erlmcp_codec:encode/1` and `erlmcp_codec:decode/1`.

---

## Content helpers

| 0.5.x | 0.6.0 |
|-------|-------|
| `{text, <<"content">>}` | `erlmcp:text(<<"content">>)` |
| `{image, Data, <<"image/png">>}` | `erlmcp:image(Data, <<"image/png">>)` |
| — (no structured output) | `erlmcp:structured(#{<<"key">> => Val})` |
| `{role, user, {text, ...}}` | `erlmcp:user_message(erlmcp:text(...))` |

---

## Schema builders

`erlmcp_schema` builds JSON Schema objects for `input_schema` and `output_schema`
declarations:

```erlang
erlmcp_schema:object([
    erlmcp_schema:field(<<"name">>, erlmcp_schema:string(), [required]),
    erlmcp_schema:field(<<"count">>, erlmcp_schema:integer([{min, 0}]), [])
])
```

There is no equivalent in 0.5.x — tools had no input schema.

---

## Porting checklist

1. **Replace `erlmcp_server:start_link/2`** with `erlmcp_stdio_sup:start_link/1`
   in your OTP application's `start/2`, and add `start_phase(serve, ...)` to call
   `erlmcp_stdio_sup:serve/1`. Add `{start_phases, [{serve, []}]}` to your `.app.src`.

2. **Replace `add_tool/3` calls** with `add_tool/2` using the map-based spec. Add
   `input_schema` to each tool (use `erlmcp_schema` — a bare `#{}` schema accepts
   anything but loses validation).

3. **Update handlers** to the `fun(Args :: map(), Ctx :: map()) -> ...` signature
   and return `{ok, erlmcp:text(Result)}` or `{ok, erlmcp:structured(Map)}`.

4. **Replace `erlmcp_stdio_server:start_link/1`** with
   `erlmcp:start_stdio_setup(Id, Config)` if you were using the convenience wrapper.

5. **Replace `erlmcp_client:start_link/2`** with
   `erlmcp_client_session:start_link(Opts)` and update the method calls.

6. **Add a `sys.config`** that redirects logs to `standard_error` — MCP uses
   stdout for the protocol wire. See `config/sys.config` in any example.

The `examples/simple` example is the canonical minimal server in 0.6.0. Compare
your ported server against it.
