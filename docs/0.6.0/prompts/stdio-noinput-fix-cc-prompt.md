# CC Prompt — stdio `{fd,0,1}` port needs `-noinput` (the runtime is stealing stdin)

> Imperative brief. The port refactor (`open_port({fd, 0, 1}, …)`) is the right
> primitive, but the server still gets no input because **under `-noshell` the Erlang
> runtime's `user` I/O server is still reading fd 0** and consumes the `initialize`
> line before the port can. Free stdin for the port with **`-noinput`**.

## Root cause

- `-noshell` disables the interactive shell but **still starts the `user` process,
  which reads stdin (fd 0)**.
- `open_port({fd, 0, 1}, …)` also wants fd 0 → the two compete; `user` wins, the port
  never receives the client's line → session never processes `initialize` → 60 s
  timeout. (Output on fd 1 via `port_command` is unaffected — this is input-only.)
- `-noinput` tells the runtime **not** to read stdin, leaving fd 0 to the port. This is
  the standard combination for an Erlang stdio server that owns the fds via a port.

## Fix

1. **Add `-noinput` to every launcher.** In each `examples/*/run.sh`:
   `exec erl -noshell -noinput -config config/sys -pa … -eval "…"`.
   (Keep `-noshell` and `-config`; just add `-noinput`.)
2. **Add `-noinput` to the round-trip test's child invocation** — the CT test that
   spawns the child `erl` via `open_port({spawn,…})` must launch it with `-noinput`
   too, or its `user` process eats the test's `port_command` input the same way. If the
   test launches through `run.sh`, fixing #1 covers it.
3. Logging is unaffected (`logger` → stderr handler, not the `user` server). Confirm
   stderr logging still works after adding `-noinput`.

## Simpler alternative (if the port keeps fighting across the OTP 25–28 matrix)

Drop the port and stay on the I/O server, but target the **real** device instead of the
group leader: keep `-noshell` (no `-noinput`), and use `io:get_line(user, "")` +
`io:put_chars(user, [Data,$\n])`. `user` is bound to real stdio in `-noshell`; this
fixes the original group-leader misdirection with no launcher-flag changes and no fd
contention. Pick whichever passes cleanly on all matrix versions; **document the choice
and why** (the `{fd,0,1}`+`-noinput` vs `user`-device tradeoff is exactly the kind of
thing the next maintainer needs spelled out).

## Verify

- The round-trip subprocess test (send `initialize` over a real pipe → assert a
  JSON-RPC response on stdout) **passes** — this is the guard that proves the real I/O
  path works; it must be green before re-attaching Claude Desktop.
- All three example servers complete `initialize` under Claude Desktop.
- Gates green; stderr still carries logs, stdout only JSON-RPC.

## Done when

The real stdin reaches the server (port owns fd 0 via `-noinput`, or the `user`-device
fallback), the round-trip test passes in CI, and Claude Desktop completes `initialize`
against all three examples. Submitted for CDC sign-off.
