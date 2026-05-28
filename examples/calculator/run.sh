#!/bin/bash
# Launch the calculator MCP server over stdio via OTP release.
# Usage: ./examples/calculator/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as calculator release >/dev/null 2>&1
exec _build/calculator/rel/calculator/bin/calculator foreground
