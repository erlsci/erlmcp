#!/bin/bash
# Launch the calculator MCP server over stdio.
# Usage: ./examples/calculator/run.sh
# Claude Desktop command: "bash", args: ["<PATH>/examples/calculator/run.sh"]
cd "$(dirname "$0")/../.." || exit 1
rebar3 as calculator compile >/dev/null 2>&1
exec erl -noshell \
  -config config/sys \
  -pa _build/calculator/lib/*/ebin \
  -eval "calculator_server:start()"
