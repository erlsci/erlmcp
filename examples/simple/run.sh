#!/bin/bash
# Launch the simple MCP server over stdio.
# Usage: ./examples/simple/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as simple compile >/dev/null 2>&1
exec erl -noshell \
    -pa $(rebar3 as simple path --ebin -s ' -pa ') \
    -config config/sys \
    -eval 'application:ensure_all_started(simple, permanent)'
