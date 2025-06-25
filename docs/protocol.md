# MCP Protocol Implementation

## Protocol Overview

The Model Context Protocol (MCP) enables structured communication between AI assistants and local services using JSON-RPC 2.0 over various transports.

## Message Types

### Requests
```erlang
%% Initialize connection
#{
    <<"jsonrpc">> => <<"2.0">>,
    <<"id">> => 1,
    <<"method">> => <<"initialize">>,
    <<"params">> => #{
        <<"protocolVersion">> => <<"2024-11-05">>,
        <<"capabilities">> => #{...}
    }
}
```

### Responses
```erlang
%% Success response
#{
    <<"jsonrpc">> => <<"2.0">>,
    <<"id">> => 1,
    <<"result">> => #{...}
}

%% Error response
#{
    <<"jsonrpc">> => <<"2.0">>,
    <<"id">> => 1,
    <<"error">> => #{
        <<"code">> => -32602,
        <<"message">> => <<"Invalid params">>
    }
}
```

### Notifications
```erlang
%% Resource update notification
#{
    <<"jsonrpc">> => <<"2.0">>,
    <<"method">> => <<"resources/updated">>,
    <<"params">> => #{
        <<"uri">> => <<"weather://city">>,
        <<"metadata">> => #{...}
    }
}
```

## Core Methods

### Client → Server

| Method | Description | Required Capability |
|--------|-------------|-------------------|
| `initialize` | Establish connection | None |
| `resources/list` | List available resources | resources |
| `resources/read` | Read resource content | resources |
| `resources/subscribe` | Subscribe to updates | resources |
| `tools/list` | List available tools | tools |
| `tools/call` | Execute a tool | tools |
| `prompts/list` | List available prompts | prompts |
| `prompts/get` | Get prompt template | prompts |

### Server → Client

| Method | Description | Trigger |
|--------|-------------|---------|
| `resources/updated` | Resource changed | Subscription |
| `resources/list_changed` | Resource list changed | Capability |
| `tools/list_changed` | Tool list changed | Capability |
| `prompts/list_changed` | Prompt list changed | Capability |

## Capability Negotiation

### Client Capabilities
```erlang
#mcp_client_capabilities{
    roots = #mcp_capability{enabled = true},      % File system roots
    sampling = #mcp_capability{enabled = true}    % LLM sampling support
}
```

### Server Capabilities
```erlang
#mcp_server_capabilities{
    resources = #mcp_capability{enabled = true},  % Resource support
    tools = #mcp_capability{enabled = true},      % Tool support
    prompts = #mcp_capability{enabled = true},    % Prompt support
    logging = #mcp_capability{enabled = true}     % Logging support
}
```

## Resource System

### Static Resources
```erlang
erlmcp_server:add_resource(Server, <<"doc://readme">>, 
    fun(_Uri) -> 
        {ok, Content} = file:read_file("README.md"),
        Content
    end).
```

### Dynamic Resources (Templates)
```erlang
erlmcp_server:add_resource_template(Server, 
    <<"user://{username}/profile">>,
    <<"User Profile">>,
    fun(Uri) ->
        %% Extract username and fetch profile
        #mcp_content{
            type = <<"application/json">>,
            text = fetch_user_profile(Uri)
        }
    end).
```

## Tool System

### Tool with JSON Schema
```erlang
Schema = #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"query">> => #{
            <<"type">> => <<"string">>,
            <<"description">> => <<"SQL query">>
        },
        <<"limit">> => #{
            <<"type">> => <<"integer">>,
            <<"minimum">> => 1,
            <<"maximum">> => 1000,
            <<"default">> => 100
        }
    },
    <<"required">> => [<<"query">>]
},

erlmcp_server:add_tool_with_schema(Server, <<"sql_query">>,
    fun(#{<<"query">> := Query} = Args) ->
        Limit = maps:get(<<"limit">>, Args, 100),
        execute_query(Query, Limit)
    end, Schema).
```

## Prompt System

### Prompt with Arguments
```erlang
Arguments = [
    #mcp_prompt_argument{
        name = <<"language">>,
        description = <<"Target programming language">>,
        required = true
    },
    #mcp_prompt_argument{
        name = <<"style">>,
        description = <<"Code style guide">>,
        required = false
    }
],

erlmcp_server:add_prompt_with_args(Server, <<"code_review">>,
    fun(#{<<"language">> := Lang} = Args) ->
        Style = maps:get(<<"style">>, Args, <<"default">>),
        [#{
            <<"role">> => <<"system">>,
            <<"content">> => generate_review_prompt(Lang, Style)
        }]
    end, Arguments).
```

## Error Handling

### Standard Error Codes
- `-32700` - Parse error
- `-32600` - Invalid request
- `-32601` - Method not found
- `-32602` - Invalid params
- `-32603` - Internal error

### Application Errors
```erlang
%% Return error from handler
fun(Args) ->
    case validate_args(Args) of
        ok -> process(Args);
        {error, Reason} ->
            throw({mcp_error, -32602, Reason})
    end
end
```

## Best Practices

1. **Always validate inputs** - Use JSON Schema for tools
2. **Handle partial failures** - Return partial results when possible
3. **Use appropriate content types** - text, image, binary
4. **Implement timeouts** - Prevent hanging requests
5. **Log errors with context** - Aid debugging
6. **Version your resources** - Include version in URIs
7. **Document tool schemas** - Use description fields