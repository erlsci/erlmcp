# Calculator MCP Server

A calculator demonstrating `erlmcp_server_handler`, discoverability,
tasks, icons, structured output, and server-initiated sampling.

## What this server is for

An arithmetic MCP server demonstrating handler behaviours, structured
output, task support with progress/cancel, and server-initiated sampling.
It exercises more of the MCP protocol surface than `simple` — use it to
explore tasks, progress notifications, and the server-to-client sampling
round-trip.

## Tool orientation

- **arithmetic** — `add` (entry point), `subtract`, `multiply`, `divide`.
  All return structured output (`outputSchema` with `result` field).
  Start with `add`, then follow the `next` chain.
- **demo** — `slow_compute` (exercises tasks + progress: emits progress
  notifications, supports cancel mid-flight), `explain` (exercises
  server-initiated sampling: asks the connected client to explain a
  calculation).
- **discoverability** — `directory` (the oriented overview; call it
  first for a structured map of all tools with workflow hints and
  protocol feature details).

## Protocol features exercised

- `slow_compute` declares `[tasks, progress]` — the handler calls
  `erlmcp_ctx:report_progress/3` and supports `task_support => optional`.
- `explain` declares `[sampling]` — the handler calls
  `erlmcp_ctx:request_peer/3` to issue a `sampling/createMessage` back
  to the connected client.

## Run

`./examples/calculator/run.sh`

See [examples/README.md](../README.md) for Claude Desktop config,
feature coverage, and test commands.
