# CC Prompt — fix stdio real-I/O (group-leader bug) + add a real round-trip test

> Imperative brief. The logging fix worked, but Claude Desktop still can't talk to the
> servers: the client sends `initialize` and **the server never responds** (60 s →
> `-32001` timeout). Root cause: the stdio transport reads/writes via the **process
> group leader**, which for a supervised process is the **application master, not the
> real OS stdin/stdout**. The reader can't read the real pipe. This path has **zero test
> coverage** (smoke tests use `test_mode`/`simulate_input` + `transport => self()`).

## Root cause (CDC, from reading `src/erlmcp_transport_stdio.erl`)

- `default_read/0` → `io:get_line("")` (line 161) and `write_stdout/1` →
  `io:put_chars([Data,$\n])` (line 154) both use the **group leader** as the I/O device.
- The transport gen_server runs under `erlmcp_transport_sup` (the `erlmcp` app tree), so
  its group leader is the **application master**, not the node's real stdio. The
  spawned reader inherits that group leader. `io:get_line` therefore reads the wrong
  device and never delivers the client's `initialize` line.
- Logging is unaffected because `logger` writes to its handler (stderr) directly, not
  via the group leader — which is why the earlier fix didn't surface this.
- `session => Server` **is** wired correctly (`start_stdio_setup`), so the inbound guard
  isn't the issue; the I/O device is.

## Fix

1. **Target the real stdio device explicitly**, not the group leader. Minimal change:
   in `default_read/0` use `io:get_line(user, "")` and in `write_stdout/1` use
   `io:put_chars(user, [Data, $\n])` — `user` is the registered I/O server connected to
   the node's real fd 0/1 under `erl -noshell`. **Verify it's correct across the OTP
   25–28 CI matrix** (the `user`/`user_drv` setup differs by version; confirm
   `io:get_line(user, …)` reads real stdin in `-noshell` on each). If `user` proves
   unreliable on a matrix version, use the bulletproof alternative:
   **`open_port({fd, 0, 1}, [stream, binary, eof])`** and read/write the port directly,
   which bypasses the I/O-server/group-leader machinery entirely. Pick one; document why.
2. Keep the pure functions (`process_raw_input`/`prepare_line`/`trim_trailing_crlf`) and
   the `test_mode`/`simulate_input` path unchanged — only the real device target changes.

## The test that was missing (mandatory — this bug existed because it didn't exist)

Add a **real round-trip subprocess test**: launch a server through its `run.sh` (or
`erl -noshell -config config/sys -pa … -eval …`) as a `port`/`open_port({spawn_executable…})`,
write a complete `initialize` request + `\n` to its stdin, and **assert a JSON-RPC
response comes back on its stdout within a timeout** — and that stdout contains only
JSON-RPC (no log noise). Keep stdin open until the response arrives (don't send EOF
early). This exercises the real `io:get_line`/`io:put_chars` path end-to-end — the thing
`test_mode` deliberately bypasses. It must be in CI.

## Verify

- A booted example server, sent `initialize` over a real pipe, returns an
  `initialize` result on stdout (the new round-trip test passes).
- `grep -n "io:get_line\|io:put_chars" src/erlmcp_transport_stdio.erl` shows the real
  device target (`user`/port), not the bare group-leader form.
- All existing gates stay green; the new round-trip test runs in CI.
- Re-attach Claude Desktop: the "Could not attach" / 60 s-timeout errors are gone and
  `initialize` completes.

## Done when

The stdio transport reads/writes the real OS stdin/stdout (not the supervised group
leader), a real round-trip subprocess test guards it in CI, and Claude Desktop completes
`initialize` against all three example servers. Submitted for CDC sign-off — then we run
the acceptance pass.
