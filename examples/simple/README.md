# Simple MCP Server

A minimal erlmcp server demonstrating inline tool/resource/prompt
registration with full discoverability wayfinding.

## What this server is for

A minimal MCP server for testing connectivity and demonstrating
config-driven tool, resource, and prompt registration with inline
handlers. It shows the simplest possible erlmcp server — no handler
module, no advanced protocol features, just tools + resources + prompts
wired in one config map.

## Tool orientation

- **utility** — `echo` (entry point: returns input unchanged), `add`
  (adds two numbers). Start with `echo` to verify connectivity.
- **discoverability** — `directory` (the oriented overview; call it
  first for a structured map of all tools with workflow hints).

One resource (`file://example.txt`) and one prompt (`greet`).

## Run

`./examples/simple/run.sh`

See [examples/README.md](../README.md) for Claude Desktop config,
feature coverage, and test commands.
