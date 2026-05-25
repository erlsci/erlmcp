#!/bin/bash
# Real stdio round-trip test for the example MCP servers.
#
# For each example: launch its run.sh, send an `initialize` request on stdin,
# and assert a valid JSON-RPC response comes back on stdout. This exercises the
# real io:get_line(user,"")/io:put_chars(user,...) path that the in-VM smoke
# suites bypass via test_mode/simulate_input — the gap that hid both the logging
# bug and the group-leader I/O bug.
#
# Run from anywhere; resolves the repo root itself. Exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"roundtrip","version":"0"}}}'

EXAMPLES=(simple calculator weather)

# Pre-compile once so run.sh's per-launch `rebar3 compile` is a fast no-op and
# does not eat into the response window below.
echo "Pre-compiling example profiles..."
for p in "${EXAMPLES[@]}"; do
    if ! rebar3 as "$p" compile >/dev/null 2>&1; then
        echo "FAIL: $p — compile failed"; exit 1
    fi
done

pass=0
fail=0
for example in "${EXAMPLES[@]}"; do
    SCRIPT="examples/$example/run.sh"
    if [ ! -f "$SCRIPT" ]; then
        echo "SKIP: $SCRIPT not found"; continue
    fi

    out="$(mktemp)"
    # Send initialize, then hold stdin open (sleep) so the server doesn't see an
    # immediate EOF while it boots + replies. Cap the whole launch with a timeout.
    # Capture ALL stdout to a file (no `head -1` mid-pipe — that SIGPIPEs the VM).
    {
        printf '%s\n' "$INIT_REQ"
        sleep 10
    } | timeout 25 bash "$SCRIPT" >"$out" 2>/dev/null || true

    # First line that looks like a JSON-RPC message; tolerate stray output before it.
    resp="$(grep -m1 '"jsonrpc"' "$out" 2>/dev/null || true)"
    if [ -n "$resp" ] && printf '%s' "$resp" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); assert d.get('jsonrpc')=='2.0' and ('result' in d or 'error' in d)" \
        2>/dev/null; then
        echo "PASS: $example — valid JSON-RPC response"
        pass=$((pass + 1))
    else
        echo "FAIL: $example — no valid JSON-RPC response on stdout. Captured (first 5 lines):"
        sed 's/^/    /' "$out" | head -5
        fail=$((fail + 1))
    fi
    rm -f "$out"
done

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
