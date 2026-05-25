# Simple MCP Server Example

A minimal erlmcp server demonstrating inline tool/resource/prompt
registration using the 0.6.0 facade API.

## Features

- **Tools:** `echo` (returns input), `add` (sums two numbers)
- **Resource:** `file://example.txt` (static content)
- **Prompt:** `greet` (generates a greeting with an argument)

## Running

```bash
rebar3 as simple shell
1> simple_server:start().
```

## API Used

- `erlmcp:start_stdio_setup/2` — one-call server + transport setup
- `erlmcp:add_tool/2` — inline fun-based tool registration
- `erlmcp:add_resource/2` — static resource with handler fun
- `erlmcp:add_prompt/2` — prompt with arguments

## Claude Desktop

```json
{
  "mcpServers": {
    "erlmcp-simple": {
      "command": "erl",
      "args": [
        "-pa", "<PATH>/erlmcp/_build/simple/lib/erlmcp/ebin",
        "-pa", "<PATH>/erlmcp/_build/simple/lib/jsx/ebin",
        "-pa", "<PATH>/erlmcp/_build/simple/lib/jesse/ebin",
        "-eval", "simple_server:start()",
        "-noshell"
      ]
    }
  }
}
```

## Tests

```bash
rebar3 ct --suite=erlmcp_example_simple_SUITE
```
