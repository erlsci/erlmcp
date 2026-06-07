# Weather MCP Server

A weather server demonstrating resources, templates with completion,
prompts with arguments, discoverability, and multiple transports.

## What this server is for

A weather MCP server demonstrating resources, resource templates with
completion, prompts with arguments, and full discoverability. It shows
the resource and prompt sides of the MCP protocol that `simple` and
`calculator` don't cover — use it to explore URI templates, argument
completion, and resource subscriptions.

## Tool orientation

- **weather** — `get_weather` (entry point: current weather for a city),
  `get_forecast` (multi-day forecast, 1-7 days). Start with `get_weather`.
- **discoverability** — `directory` (the oriented overview; call it
  first for a structured map of all tools with workflow hints).

Resources: `weather://current/london` (static) and
`weather://current/{city}` (template with city completion).

Prompts: `weather_report` (generates a weather report prompt with
city and units arguments, both with completion).

## Protocol features exercised

- The `weather://current/{city}` resource template declares
  `[completion]` — it provides city name completion via the
  `completion/complete` endpoint.

## Run

`./examples/weather/run.sh`

See [examples/README.md](../README.md) for Claude Desktop config,
feature coverage, and test commands.
