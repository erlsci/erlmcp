# erlmcp

[![Build Status][gh-actions-badge]][gh-actions]

[![Project Logo][logo]][logo-large]

*Erlang implementation of the Model Context Protocol (MCP) SDK.*

MCP enables seamless communication between AI assistants and local services through a standardized protocol. This SDK provides both client and server implementations with full OTP compliance, allowing you to build robust, fault-tolerant integrations that expose resources, tools, and prompts to AI systems.

## Installation

**Requirements:** Erlang/OTP 25 or later

```bash
# Add to your rebar.config deps
{deps, [
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {branch, "main"}}}
]}.

# Fetch and compile
rebar3 get-deps
rebar3 compile
```

## Quick Start

### Creating an MCP Server

```erlang
%% Start a server that exposes resources
{ok, Server} = erlmcp_server:start_link({stdio, []}, Capabilities),

%% Add a resource
erlmcp_server:add_resource(Server, <<"hello://world">>,
    fun(_Uri) -> <<"Hello from Erlang!">> end),

%% Add a tool with JSON Schema validation
Schema = #{<<"type">> => <<"object">>,
           <<"properties">> => #{<<"name">> => #{<<"type">> => <<"string">>}}},
erlmcp_server:add_tool_with_schema(Server, <<"greet">>,
    fun(#{<<"name">> := Name}) ->
        <<"Hello, ", Name/binary, "!">>
    end, Schema).
```

### Creating an MCP Client

```erlang
%% Connect to an MCP server
{ok, Client} = erlmcp_client:start_link({stdio, []}, #{strict_mode => false}),

%% Initialize connection
{ok, _} = erlmcp_client:initialize(Client, Capabilities),

%% List available resources
{ok, #{<<"resources">> := Resources}} = erlmcp_client:list_resources(Client),

%% Call a tool
{ok, Result} = erlmcp_client:call_tool(Client, <<"greet">>,
                                        #{<<"name">> => <<"World">>}).
```

## Examples

See the [examples directory](examples/README.md) for comprehensive examples:

- **[Weather Server](examples/README.md#1-weather-server-weather_servererl)** - Full MCP server with resources, tools, and subscriptions
- **[Calculator Client](examples/README.md#2-calculator-client-calculator_clienterl)** - Sophisticated client with connection management
- **[Complete Application](examples/README.md#3-mcp-application-mcp_applicationerl)** - OTP application with supervision

## Documentation

- [Architecture Overview](docs/architecture.md) - System design and components
- [Protocol Guide](docs/protocol.md) - MCP protocol implementation details
- [OTP Patterns](docs/otp-patterns.md) - Erlang/OTP best practices used
- [API Reference](docs/api-reference.md) - Complete API documentation

## Key Features

- ✅ Full MCP protocol support (resources, tools, prompts)
- ✅ OTP-compliant with supervision trees
- ✅ Multiple transport layers (stdio, TCP, HTTP)
- ✅ JSON Schema validation for tools
- ✅ Resource subscriptions with notifications
- ✅ Automatic reconnection with backoff
- ✅ Comprehensive error handling
- ✅ Production-ready logging and monitoring

## License

Apache 2.0

## External Resources

- [Get started with the Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction)

[//]: ---Named-Links---

[logo]: priv/images/logo.png
[logo-large]: priv/images/logo-large.png
[gh-actions-badge]: https://github.com/erlsci/erlmcp/workflows/ci/badge.svg
[gh-actions]: https://github.com/erlsci/erlmcp/actions?query=workflow%3Aci
