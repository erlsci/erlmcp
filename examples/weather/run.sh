#!/bin/bash
# Launch the weather MCP server over stdio via OTP release.
# Usage: ./examples/weather/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as weather release >/dev/null 2>&1

REL_ROOT="$(pwd)/_build/weather/rel/weather"
REL_VSN="0.1.0"

if [ -d "$REL_ROOT"/erts-* ]; then
    BINDIR="$(ls -d "$REL_ROOT"/erts-*)/bin"
    SYS_LIB="$REL_ROOT/lib"
else
    ERL_ROOT="$(dirname "$(dirname "$(which erl)")")/lib/erlang"
    ERTS_VSN="$(erl -noshell -eval 'io:format("~s",[erlang:system_info(version)]),halt().')"
    BINDIR="$ERL_ROOT/erts-$ERTS_VSN/bin"
    SYS_LIB="$ERL_ROOT/lib"
fi

export ROOTDIR="$REL_ROOT"
export BINDIR
export EMU=beam
export PROGNAME=weather

exec "$BINDIR/erlexec" \
    -noshell \
    -boot "$REL_ROOT/releases/$REL_VSN/start" \
    -mode embedded \
    -boot_var SYSTEM_LIB_DIR "$SYS_LIB" \
    -config "$REL_ROOT/releases/$REL_VSN/sys.config" \
    -args_file "$REL_ROOT/releases/$REL_VSN/vm.args"
