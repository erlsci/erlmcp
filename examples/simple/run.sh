#!/bin/bash
# Launch the simple MCP server over stdio via OTP release.
# Usage: ./examples/simple/run.sh
#
# Boots the release VM directly via erlexec — no `foreground` wrapper
# (which echoes Exec:/Root: to stdout). Uses -noshell (not -noinput)
# so the `user` I/O server reads stdin. stdout carries only JSON-RPC.
#
# Recipe (for howto §4.4):
#   ROOTDIR=<rel_root> BINDIR=<erts_bin> EMU=beam PROGNAME=<name>
#   erlexec -noshell -boot <releases/vsn/start> -mode embedded
#           -boot_var SYSTEM_LIB_DIR <otp_lib>
#           -config <releases/vsn/sys.config>
#           -args_file <releases/vsn/vm.args>
cd "$(dirname "$0")/../.." || exit 1
rebar3 as simple release >/dev/null 2>&1

REL_ROOT="$(pwd)/_build/simple/rel/simple"
REL_VSN="0.1.0"

# Locate ERTS — bundled in release or system install
if [ -d "$REL_ROOT"/erts-* ]; then
    ERTS_DIR="$(ls -d "$REL_ROOT"/erts-*)"
    BINDIR="$ERTS_DIR/bin"
    SYS_LIB="$REL_ROOT/lib"
else
    ERL="$(which erl)"
    ERL_ROOT="$(dirname "$(dirname "$ERL")")/lib/erlang"
    ERTS_VSN="$(erl -noshell -eval 'io:format("~s",[erlang:system_info(version)]),halt().')"
    BINDIR="$ERL_ROOT/erts-$ERTS_VSN/bin"
    SYS_LIB="$ERL_ROOT/lib"
fi

export ROOTDIR="$REL_ROOT"
export BINDIR
export EMU=beam
export PROGNAME=simple

exec "$BINDIR/erlexec" \
    -noshell \
    -boot "$REL_ROOT/releases/$REL_VSN/start" \
    -mode embedded \
    -boot_var SYSTEM_LIB_DIR "$SYS_LIB" \
    -config "$REL_ROOT/releases/$REL_VSN/sys.config" \
    -args_file "$REL_ROOT/releases/$REL_VSN/vm.args"
