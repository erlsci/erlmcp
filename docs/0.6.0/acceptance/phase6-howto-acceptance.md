# Phase 6 — Howto Following Acceptance Test

> Acceptance document for P6M7-7. Documents the test procedure for
> `docs/creating-an-mcp-server.md`. The verdict must be **pass** before the
> 0.6.0 tag is cut. See `docs/0.6.0/RELEASE-CHECKLIST.md` item 1.4.
>
> The test is executed by following the howto literally on a fresh environment.
> For coverage, the `examples/simple` server (which the howto uses as its
> canonical reference) is also verified against Claude Desktop.

---

## Procedure

### Environment setup

```bash
# Clone erlmcp (simulate a fresh environment — no prior build artifacts)
git clone https://github.com/erlsci/erlmcp.git
cd erlmcp

# Verify prerequisites
erl +V          # should show OTP 25 or newer
rebar3 version  # should show 3.22 or newer
```

### Step 1: Create the project

Follow `docs/creating-an-mcp-server.md` §1 through §5 exactly as written.
Copy each code block verbatim into the corresponding file.

Expected state after step 5:

```
my_mcp_server/
├── rebar.config
├── config/sys.config
├── run.sh          (executable)
└── src/
    ├── my_mcp_server.app.src
    ├── my_mcp_server_app.erl
    └── my_mcp_server.erl
```

### Step 2: Compile

```bash
cd my_mcp_server
rebar3 compile
```

Expected: exits 0 with no warnings (or only `nowarn_missing_spec` if test profile
is not loaded). No `Error:` lines.

### Step 3: Smoke test via stdin

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ./run.sh
```

Expected response (JSON-RPC result with `result.serverInfo.name` = `my_mcp_server`
or similar):

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"my_mcp_server","version":"0.1.0"},"capabilities":{...},"instructions":"..."}}
```

Followed by `notifications/initialized` notification. The `instructions` field
should be non-empty (auto-generated from the identity block).

### Step 4: Verify tools/list

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ./run.sh
```

Expected: the `tools/list` response contains at least two tools: `hello` and
`directory`. The `hello` tool has `_meta` with `io.erlmcp/when_to_use` and
`io.erlmcp/category`.

### Step 5: Verify tools/call

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"hello","arguments":{"name":"World"}}}\n' | ./run.sh
```

Expected: response with `result.content[0].text` = `"Hello, World!"` (or similar
per the howto's handler).

### Step 6 (optional): Claude Desktop integration

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-mcp-server": {
      "command": "bash",
      "args": ["/absolute/path/to/my_mcp_server/run.sh"]
    }
  }
}
```

Restart Claude Desktop. Open a new conversation and ask:
- "What tools do you have?" (expect: hello, directory listed)
- "Call the directory tool." (expect: categorized listing with `greetings` category)
- "Say hello to Alice." (expect: tool call with `name: "Alice"`, returns "Hello, Alice!")

---

## Verification: `examples/simple` as the canonical reference

The howto's §10 points to `examples/simple` as the finished shape. Verify it
works identically:

```bash
# From the erlmcp root
./examples/simple/run.sh &
PID=$!

echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ./examples/simple/run.sh
```

Expected: same structure as Step 3. Add `simple` to Claude Desktop config
(per `examples/README.md`) and verify the acceptance items in
`docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`.

---

## Observed state

_(To be filled in during execution.)_

### Step 2: compile

```
Verdict: pending
Observed:
```

### Step 3: initialize smoke test

```
Verdict: pending
Observed:
```

### Step 4: tools/list

```
Verdict: pending
Observed:
```

### Step 5: tools/call

```
Verdict: pending
Observed:
```

### Step 6: Claude Desktop (optional)

```
Verdict: pending
Observed:
```

---

## Overall verdict

| Step | Verdict | Notes |
|------|---------|-------|
| Compile | pending | |
| Initialize smoke test | pending | |
| tools/list | pending | |
| tools/call | pending | |
| Claude Desktop | pending | Optional |

**Final verdict:** pending — requires human execution.

If any mandatory step (steps 2–5) fails, the howto is **not done** — go back to
`docs/creating-an-mcp-server.md`, fix the relevant section, and re-run the
procedure.

---

## Closing the arc

The original bug: "no tools available" when connecting erlmcp to Claude Desktop.

The root causes (from Phase 6 §1): startup race, payload non-conformance (invalid
Icon shape, invalid `taskSupport` enum, non-UTF-8 content), and catalog/session
fusion breaking HTTP.

The fix: P6-M1 split the catalog from the session and added the UTF-8 guard;
P6-M2 introduced the `serve/1` gate that eliminates the startup race; P6-M5 added
the jesse validation seam that makes the payload bugs structurally impossible;
P6-M6 verified the example servers produce clean payloads end-to-end; P6-M7 wrote
the howto that makes all of this teachable.

**The acceptance of this howto is the acceptance of the Phase 6 arc.**
