# erlmcp API Reference

## Server Facade (`erlmcp`)

### Server Management

| Function | Description |
|----------|-------------|
| `start_server(ServerId)` | Start a server session |
| `start_server(ServerId, Config)` | Start with config |
| `stop_server(ServerId)` | Stop a server |
| `list_servers()` | List registered servers |
| `start_transport(Id, Type)` | Start a transport |
| `start_transport(Id, Type, Config)` | Start with config |
| `stop_transport(Id)` | Stop a transport |
| `bind_transport_to_server(TransId, ServerId)` | Bind transport to server |

### Tools

| Function | Description |
|----------|-------------|
| `add_tool(Session, ToolSpec)` | Register a tool (data-driven map) |
| `remove_tool(Session, Name)` | Unregister a tool |
| `register_handler(Session, Module)` | Register a handler behaviour module |
| `make_directory_tool()` | Create the directory tool spec |
| `conformance_tools(Session)` | List tools excluding the directory |

### Resources

| Function | Description |
|----------|-------------|
| `add_resource(Session, Spec)` | Register a resource |
| `remove_resource(Session, Uri)` | Unregister a resource |
| `add_resource_template(Session, Spec)` | Register a URI template |
| `remove_resource_template(Session, UriTpl)` | Unregister a template |
| `notify_resource_updated(Session, Uri)` | Notify subscribers of a change |

### Prompts

| Function | Description |
|----------|-------------|
| `add_prompt(Session, Spec)` | Register a prompt |
| `remove_prompt(Session, Name)` | Unregister a prompt |

### Logging

| Function | Description |
|----------|-------------|
| `log_message(Session, Level, Logger, Data)` | Emit a log notification |

### Content Constructors

| Function | Description |
|----------|-------------|
| `text(Binary)` | Text content item |
| `image(Data, MimeType)` | Base64 image content |
| `audio(Data, MimeType)` | Base64 audio content |
| `embedded_resource(Resource)` | Embedded resource content |
| `resource_link(Uri, MimeType)` | Resource link content |

### Convenience Setup

| Function | Description |
|----------|-------------|
| `start_stdio_setup(ServerId, Config)` | Start server + stdio transport |
| `start_tcp_setup(ServerId, ServerConfig, TcpConfig)` | Start server + TCP |
| `start_http_setup(ServerId, ServerConfig, HttpConfig)` | Start server + HTTP |

## Client Session (`erlmcp_client_session`)

### Lifecycle

| Function | Description |
|----------|-------------|
| `start_link(Opts)` | Start a client session |
| `initialize(Session, Params)` | Perform MCP initialize handshake |
| `ping(Session)` | Ping the server |
| `cancel(Session, RequestId)` | Cancel an in-flight request |
| `stop(Session)` | Stop the session |

### Request API

| Function | Description |
|----------|-------------|
| `list_tools(Session)` | List all tools (auto-paginate) |
| `list_tools(Session, Params)` | List one page of tools |
| `call_tool(Session, Name, Args)` | Call a tool |
| `call_tool(Session, Name, Args, Opts)` | Call with options (progress token) |
| `list_resources(Session)` | List all resources (auto-paginate) |
| `read_resource(Session, Uri)` | Read a resource |
| `list_resource_templates(Session)` | List all templates (auto-paginate) |
| `subscribe_resource(Session, Uri)` | Subscribe to resource updates |
| `unsubscribe_resource(Session, Uri)` | Unsubscribe |
| `list_prompts(Session)` | List all prompts (auto-paginate) |
| `get_prompt(Session, Name, Args)` | Get a rendered prompt |
| `set_log_level(Session, Level)` | Set server log level |
| `complete(Session, Ref, Argument)` | Get completions |

### Callback Registration

| Function | Description |
|----------|-------------|
| `set_sampling_handler(Session, Module)` | Register sampling callback |
| `set_roots_handler(Session, Module)` | Register roots callback |
| `set_elicitation_handler(Session, Module)` | Register elicitation callback |
| `notify_roots_changed(Session)` | Notify server of roots change |

## Schema Builder (`erlmcp_schema`)

| Function | Description |
|----------|-------------|
| `object(Fields)` | Build an object schema |
| `object(Fields, Opts)` | Build with options |
| `field(Name, Type)` | Define a field |
| `field(Name, Type, Opts)` | Define with options (`required`, `{doc, _}`, etc.) |
| `string()`, `integer()`, `number()`, `boolean()` | Type constructors |
| `array(ItemSchema)` | Array type |
| `enum(Values)` | Enum type |
| `any_of(Schemas)` | Union type |
| `validate(Schema, Data)` | Validate data against schema via jesse |

## Handler Behaviour (`erlmcp_server_handler`)

```erlang
-callback tools() -> [map()].
-callback handle_tool(binary(), map(), erlmcp_ctx:ctx()) ->
    {ok, term()} | {error, integer(), binary()}.
```

## Callback Behaviours

### `erlmcp_sampling`

```erlang
-callback handle_create_message(map(), erlmcp_ctx:ctx()) ->
    {ok, map()} | {error, term()}.
```

### `erlmcp_roots`

```erlang
-callback list_roots(erlmcp_ctx:ctx()) ->
    {ok, [map()]} | {error, term()}.
```

### `erlmcp_elicitation`

```erlang
-callback handle_elicit(map(), erlmcp_ctx:ctx()) ->
    {ok, map()} | {error, term()}.
```

## Context (`erlmcp_ctx`)

| Function | Description |
|----------|-------------|
| `new(Opts)` | Create a new context |
| `session(Ctx)` | Get the session pid |
| `request_id(Ctx)` | Get the request id |
| `report_progress(Ctx, Fraction, Msg)` | Report progress to client |
| `request_peer(Ctx, Method, Params)` | Issue a request to the peer |

## Transport Behaviour (`erlmcp_transport`)

```erlang
-callback init(TransportId, Config) -> {ok, state()} | {error, term()}.
-callback send(state(), iodata()) -> ok | {error, term()}.
-callback close(state()) -> ok.
-callback get_info(state()) -> map().           %% optional
-callback handle_transport_call(Request, state()) -> ...  %% optional
```

Implementations: `erlmcp_transport_stdio`, `_tcp`, `_http`,
`_streamable_http`. Each exports `validate_config/1`.
