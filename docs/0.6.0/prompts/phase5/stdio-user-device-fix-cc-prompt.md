# CC Prompt — stdio I/O the idiomatic OTP way (route to the `user` I/O server)

> Imperative brief. **Supersedes the earlier `-noinput`/port prompts.** Root cause is
> now confirmed against 0.5.0: the machinery is fine — we changed the reader's **group
> leader** by moving it under the application supervisor. Fix it by routing protocol
> I/O to the real I/O server (`user`), not the group leader. **No port, no `-noinput`.**

## Root cause (confirmed empirically)

- 0.5.0's stdio server used **the same `io:get_line("")`** and worked, because
  `erlmcp_stdio_server` was `start_link`'d **directly from the launch process** — so its
  group leader (and its spawned reader's) was **`user`** (the real stdin/stdout).
- The 0.6.0 transport is a **supervised child** under `erlmcp_transport_sup` → the
  `erlmcp` application, so its processes inherit the **application master** as group
  leader. `io:get_line("")` targets the group leader → the app master → which does not
  serve stdin reads → no line is ever delivered → the session never sees `initialize`.
- This is a group-leader/device problem, not an `io:get_line` or fd-contention problem.
  The Erlang I/O machinery is correct; we were addressing the wrong device.

## Fix

1. **Revert the `open_port({fd,0,1}, …)` refactor.** Restore the reader-process +
   `write_stdout` structure (the pre-port shape), and **do not** add `-noinput`.
2. **Target the `user` I/O server explicitly** in both directions (process-agnostic —
   doesn't depend on who calls it or where it sits in the tree):
   - read: `io:get_line(user, "")` (in `default_read/0`).
   - write: `io:put_chars(user, [Data, $\n])` (in `write_stdout/1`).
   *(Equivalent alternative, if preferred: set the reader's group leader once with
   `erlang:group_leader(whereis(user), self())` at the top of the read loop and keep the
   plain calls — this is exactly what 0.5.0 got implicitly. Pick one; the explicit-device
   form is clearer about intent. Document the choice.)*
3. Keep `-noshell` (no `-noinput`), keep `-config config/sys` (the logging fix stays).
4. Guard `whereis(user)`/the `user` device: it must resolve to the real I/O server under
   `erl -noshell` on the **OTP 25–28** matrix. The round-trip test (below) confirms it;
   if any matrix version misbehaves (e.g. an OTP-26+ `user_drv` default edge case), raise
   it rather than papering over — but 0.5.0's behavior says the simple path holds.

## The round-trip test (mandatory — keep it regardless of approach)

Launch a server through its `run.sh` as a subprocess (`open_port({spawn_executable,…})`
or `{spawn,…}`), write a complete `initialize` request + `\n` to its stdin, keep stdin
open, and **assert a JSON-RPC `initialize` result comes back on stdout** within a
timeout, with no non-JSON noise. This exercises the real `io:get_line`/`io:put_chars`
path that `test_mode`/`simulate_input` deliberately bypasses — the gap that hid both
this bug and the logging bug. Must run in CI.

## Verify

- `grep -n "open_port\|fd, 0\|-noinput" src examples` → none (port + `-noinput` removed).
- `grep -n "io:get_line\|io:put_chars" src/erlmcp_transport_stdio.erl` → targets `user`
  (or the reader sets `group_leader(whereis(user), …)`).
- Round-trip test passes in CI; all gates green; logs still on stderr, stdout pure JSON.
- Claude Desktop completes `initialize` against all three example servers.

## Done when

The stdio transport routes protocol I/O to the `user` I/O server (idiomatic OTP, no
port, no `-noinput`), the round-trip test proves the real path end-to-end in CI, and
Claude Desktop attaches + initializes against calculator/simple/weather. Submitted for
CDC sign-off — then the acceptance pass.
