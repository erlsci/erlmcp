#!/bin/bash
# Launch the calculator MCP server over stdio.
# Usage: ./examples/calculator/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as calculator compile >/dev/null 2>&1
exec erl -noshell \
    -pa $(rebar3 as calculator path --ebin -s ' -pa ') \
    -config config/sys \
    -eval 'application:ensure_all_started(calculator)'
