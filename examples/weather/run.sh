#!/bin/bash
# Launch the weather MCP server over stdio.
# Usage: ./examples/weather/run.sh
# Claude Desktop command: "bash", args: ["<PATH>/examples/weather/run.sh"]
cd "$(dirname "$0")/../.." || exit 1
rebar3 as weather compile >/dev/null 2>&1
exec erl -noshell \
  -pa _build/weather/lib/*/ebin \
  -eval "weather_server:start_stdio()"
