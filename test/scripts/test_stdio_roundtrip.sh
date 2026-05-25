#!/bin/bash
# Real round-trip test: launches a server via run.sh, sends initialize
# on stdin, asserts a JSON-RPC response on stdout. Run from repo root.
# Exit 0 on success, 1 on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}'

pass=0
fail=0

for example in simple calculator weather; do
    SCRIPT="examples/$example/run.sh"
    if [ ! -f "$SCRIPT" ]; then
        echo "SKIP: $SCRIPT not found"
        continue
    fi

    # Launch server, send initialize on stdin, capture stdout (keep stdin open 5s)
    STDOUT=$( { echo "$INIT_REQ"; sleep 5; } | bash "$SCRIPT" 2>/dev/null | head -1 )

    if [ -z "$STDOUT" ]; then
        echo "FAIL: $example — no response on stdout"
        fail=$((fail + 1))
        continue
    fi

    # Check it parses as JSON with jsonrpc key
    if echo "$STDOUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'jsonrpc' in d" 2>/dev/null; then
        echo "PASS: $example — valid JSON-RPC response"
        pass=$((pass + 1))
    else
        echo "FAIL: $example — stdout is not valid JSON-RPC: $STDOUT"
        fail=$((fail + 1))
    fi
done

echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
