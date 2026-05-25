#!/bin/bash
# Launch the simple MCP server over stdio.
# Usage: ./examples/simple/run.sh
# Claude Desktop command: "bash", args: ["<PATH>/examples/simple/run.sh"]
cd "$(dirname "$0")/../.." || exit 1
rebar3 as simple compile >/dev/null 2>&1
exec erl -noshell \
  -pa _build/simple/lib/*/ebin \
  -eval "simple_server:start()"
