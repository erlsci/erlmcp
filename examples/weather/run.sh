#!/bin/bash
# Launch the weather MCP server over stdio via OTP release.
# Usage: ./examples/weather/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as weather release >/dev/null 2>&1
exec _build/weather/rel/weather/bin/weather foreground
