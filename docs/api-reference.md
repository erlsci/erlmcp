# erlmcp API Reference

## Client API

### Starting a Client

```erlang
-spec erlmcp_client:start_link(TransportOpts, Options) -> {ok, pid()} | {error, term()}.

TransportOpts :: {stdio, []} | 
                 {tcp, #{host => string(), port => integer()}} |
                 {http, #{url => string()}}

Options :: #{
    strict_mode => boolean(),     % Default: false
    timeout => timeout(),         % Default: 5000ms
    max_pending => integer()      % Default: 100
}
```

### Core Operations

```erlang
%% Initialize connection
-spec initialize(Client, Capabilities) -> {ok, InitResult} | {error, term()}.
-spec initialize(Client, Capabilities, Options) -> {ok, InitResult} | {error, term()}.

%% Resource operations
-spec list_resources(Client) -> {ok, #{resources => [Resource]}} | {error, term()}.
-spec read_resource(Client, Uri) -> {ok, #{contents => [Content]}} | {error, term()}.
-spec subscribe_to_resource(Client, Uri) -> ok | {error, term()}.
-spec unsubscribe_from_resource(Client, Uri) -> ok | {error, term()}.

%% Tool operations  
-spec list_tools(Client) -> {ok, #{tools => [Tool]}} | {error, term()}.
-spec call_tool(Client, Name, Arguments) -> {ok, #{content => [Content]}} | {error, term()}.

%% Prompt operations
-spec list_prompts(Client) -> {ok, #{prompts => [Prompt]}} | {error, term()}.
-spec get_prompt(Client, Name) -> {ok, #{messages => [Message]}} | {error, term()}.
-spec get_prompt(Client, Name, Arguments) -> {ok, #{messages => [Message]}} | {error, term()}.
```

### Advanced Features

```erlang
%% Batch operations
-spec with_batch(Client, fun((BatchId) -> Result)) -> Result.
-spec send_batch_request(Client, BatchId, Method, Params) -> {ok, RequestId} | {error, term()}.

%% Notification handling
-spec set_notification_handler(Client, Method, Handler) -> ok.
Handler :: fun((Method :: binary(), Params :: map()) -> any()) |
           {Module :: atom(), Function :: atom()}

%% Sampling support
-spec set_sampling_handler(Client, Handler) -> ok.
-spec remove_sampling_handler(Client) -> ok.
```

## Server API

### Starting a Server

```erlang
-spec erlmcp_server:start_link(TransportOpts, Capabilities) -> {ok, pid()} | {error, term()}.

Capabilities :: #mcp_server_capabilities{
    resources :: #mcp_capability{} | undefined,
    tools :: #mcp_capability{} | undefined, 
    prompts :: #mcp_capability{} | undefined,
    logging :: #mcp_capability{} | undefined
}
```

### Resource Management

```erlang
%% Add static resource
-spec add_resource(Server, Uri, Handler) -> ok.
Handler :: fun((Uri :: binary()) -> binary() | #mcp_content{})

%% Add dynamic resource template
-spec add_resource_template(Server, UriTemplate, Name, Handler) -> ok.
UriTemplate :: binary()  % e.g., <<"user://{id}/profile">>

%% Example
erlmcp_server:add_resource(Server, <<"config://app">>,
    fun(_Uri) ->
        #mcp_content{
            type = <<"application/json">>,
            text = jsx:encode(get_config())
        }
    end).
```

### Tool Management

```erlang
%% Add tool without schema
-spec add_tool(Server, Name, Handler) -> ok.
Handler :: fun((Arguments :: map()) -> Result)
Result :: binary() | #mcp_content{} | [#mcp_content{}]

%% Add tool with JSON Schema validation
-spec add_tool_with_schema(Server, Name, Handler, Schema) -> ok.
Schema :: map()  % JSON Schema

%% Example
Schema = #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"x">> => #{<<"type">> => <<"number">>},
        <<"y">> => #{<<"type">> => <<"number">>}
    },
    <<"required">> => [<<"x">>, <<"y">>]
},
erlmcp_server:add_tool_with_schema(Server, <<"add">>,
    fun(#{<<"x">> := X, <<"y">> := Y}) ->
        #mcp_content{
            type = <<"text">>,
            text = float_to_binary(X + Y)
        }
    end, Schema).
```

### Prompt Management

```erlang
%% Add simple prompt
-spec add_prompt(Server, Name, Handler) -> ok.

%% Add prompt with arguments
-spec add_prompt_with_args(Server, Name, Handler, Arguments) -> ok.
Arguments :: [#mcp_prompt_argument{}]

%% Example
Args = [
    #mcp_prompt_argument{
        name = <<"language">>,
        description = <<"Programming language">>,
        required = true
    }
],
erlmcp_server:add_prompt_with_args(Server, <<"code_template">>,
    fun(#{<<"language">> := Lang}) ->
        [#{
            <<"role">> => <<"system">>,
            <<"content">> => <<"You are an expert ", Lang/binary, " programmer.">>
        }]
    end, Args).
```

### Notifications

```erlang
%% Subscribe to resource updates
-spec subscribe_resource(Server, Uri, Subscriber) -> ok.

%% Send notifications
-spec notify_resource_updated(Server, Uri, Metadata) -> ok.
-spec notify_resources_changed(Server) -> ok.

%% Progress reporting
-spec report_progress(Server, Token, Progress, Total) -> ok.
```

## Type Definitions

### Content Types

```erlang
#mcp_content{
    type :: binary(),           % "text" | "image" | "binary"
    text :: binary() | undefined,
    data :: binary() | undefined,  % Base64 for binary content
    mime_type :: binary() | undefined
}
```

### Resource Types

```erlang
#mcp_resource{
    uri :: binary(),
    name :: binary(), 
    description :: binary() | undefined,
    mime_type :: binary() | undefined,
    metadata :: map() | undefined
}

#mcp_resource_template{
    uri_template :: binary(),
    name :: binary(),
    description :: binary() | undefined,
    mime_type :: binary() | undefined
}
```

### Tool Types

```erlang
#mcp_tool{
    name :: binary(),
    description :: binary(),
    input_schema :: map() | undefined  % JSON Schema
}
```

### Prompt Types

```erlang
#mcp_prompt{
    name :: binary(),
    description :: binary() | undefined,
    arguments :: [#mcp_prompt_argument{}] | undefined
}

#mcp_prompt_argument{
    name :: binary(),
    description :: binary() | undefined,
    required :: boolean()
}
```

## Error Handling

Common error returns:

```erlang
{error, not_initialized}
{error, capability_not_supported} 
{error, {tcp_error, Reason}}
{error, {invalid_response, Data}}
{error, {error_response, #{<<"code">> => Code, <<"message">> => Message}}}
```

## Examples

See the [examples directory](../examples/) for complete working examples.