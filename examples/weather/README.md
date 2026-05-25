# Weather MCP Server Example

A weather MCP server demonstrating resources, resource templates with
completion, prompts with arguments and completion, logging, and multiple
transports (stdio + tcp).

## Features

- **Tool:** `get_weather` — current weather for any city
- **Resource:** `weather://current/london` — static London weather
- **Resource template:** `weather://current/{city}` — dynamic city
  weather with tab-completion
- **Prompt:** `weather_report` — generates a report prompt with city and
  units arguments, both with completion
- **Multiple transports:** `start_stdio/0` and `start_tcp/2`

## Running

```bash
# Stdio transport
rebar3 as weather shell
1> weather_server:start_stdio().

# TCP transport
1> weather_server:start_tcp("localhost", 9000).
```

## Claude Desktop

```json
{
  "mcpServers": {
    "erlmcp-weather": {
      "command": "erl",
      "args": [
        "-pa", "<PATH>/erlmcp/_build/weather/lib/erlmcp/ebin",
        "-pa", "<PATH>/erlmcp/_build/weather/lib/jsx/ebin",
        "-pa", "<PATH>/erlmcp/_build/weather/lib/jesse/ebin",
        "-eval", "weather_server:start_stdio()",
        "-noshell"
      ]
    }
  }
}
```

## Tests

```bash
rebar3 ct --suite=erlmcp_example_weather_smoke_SUITE
rebar3 ct --suite=erlmcp_example_weather_SUITE
```
