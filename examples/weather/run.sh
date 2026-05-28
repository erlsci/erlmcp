#!/bin/bash
# Launch the weather MCP server over stdio.
# Usage: ./examples/weather/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as weather compile >/dev/null 2>&1
exec erl -noshell \
    -pa $(rebar3 as weather path --ebin -s ' -pa ') \
    -config config/sys \
    -eval 'application:ensure_all_started(weather)'
