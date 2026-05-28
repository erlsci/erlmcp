#!/bin/bash
# Launch the calculator MCP server over stdio via OTP release.
# Usage: ./examples/calculator/run.sh
cd "$(dirname "$0")/../.." || exit 1
rebar3 as calculator release >/dev/null 2>&1

REL_ROOT="$(pwd)/_build/calculator/rel/calculator"
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
export PROGNAME=calculator

exec "$BINDIR/erlexec" \
    -noshell \
    -boot "$REL_ROOT/releases/$REL_VSN/start" \
    -mode embedded \
    -boot_var SYSTEM_LIB_DIR "$SYS_LIB" \
    -config "$REL_ROOT/releases/$REL_VSN/sys.config" \
    -args_file "$REL_ROOT/releases/$REL_VSN/vm.args"
