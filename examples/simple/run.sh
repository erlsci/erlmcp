#!/bin/bash
# Launch the simple MCP server over stdio via OTP release.
# Usage: ./examples/simple/run.sh
# Claude Desktop command: "bash", args: ["<PATH>/examples/simple/run.sh"]
cd "$(dirname "$0")/../.." || exit 1
rebar3 as simple release >/dev/null 2>&1
exec _build/simple/rel/simple/bin/simple foreground
