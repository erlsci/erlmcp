# Calculator MCP Server Example

A calculator MCP server demonstrating the `erlmcp_server_handler`
behaviour, discoverability, tasks, icons, structured output, and `_meta`
passthrough.

## Features

- **Tools (handler behaviour):** `add`, `subtract`, `multiply`, `divide`
  — registered via `erlmcp:register_handler/2`
- **Directory tool:** categorized listing of all tools
- **Task-enabled tool:** `slow_compute` — long-running with progress
  reporting and cancellation support
- **Icons:** emoji icons on arithmetic tools
- **Structured output:** `outputSchema` with validated
  `structuredContent`
- **Discoverability:** `instructions`, `_meta` wayfinding, entry points,
  `next` chains

## Running

```bash
rebar3 as calculator shell
1> calculator_server:start().
```

## Claude Desktop

```json
{
  "mcpServers": {
    "erlmcp-calculator": {
      "command": "erl",
      "args": [
        "-pa", "<PATH>/erlmcp/_build/calculator/lib/erlmcp/ebin",
        "-pa", "<PATH>/erlmcp/_build/calculator/lib/jsx/ebin",
        "-pa", "<PATH>/erlmcp/_build/calculator/lib/jesse/ebin",
        "-eval", "calculator_server:start()",
        "-noshell"
      ]
    }
  }
}
```

## Tests

```bash
rebar3 ct --suite=erlmcp_example_calculator_smoke_SUITE
rebar3 ct --suite=erlmcp_example_calculator_SUITE
```
