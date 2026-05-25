# CC Prompt — fix stdio logging the idiomatic way (logger → stderr via config, not code)

> Imperative brief. The examples fail under Claude Desktop because **non-JSON-RPC
> output reaches stdout** and corrupts the protocol stream (`=INFO REPORT…` / `SIGTERM
> received…` → "not valid JSON"). The previous fix (`e467d41`) patched the wrong layer.
> For a stdio MCP server, **stdout carries ONLY JSON-RPC**; all logging goes to stderr
> (or a file). Fix it at VM-config level, not in application code.

## Root cause (verified by CDC)

- `examples/*/run.sh` launches `erl -noshell ... -eval "..."` **without `-config`**, so
  `sys.config` is never loaded — the VM runs on the **default logger, which writes to
  `standard_io` (stdout)**.
- `config/sys.config`'s default handler is also `type => standard_io` (would still
  corrupt stdout even if loaded).
- `e467d41` added a runtime `redirect_logger_to_stderr/0` in `start_stdio_setup/2` —
  too late and too narrow: VM/app-start reports and the OTP signal handler's "SIGTERM
  received" message (logger-emitted) bracket that window. Wrong layer.

## Tasks

1. **Revert the code-layer fix.** Remove `redirect_logger_to_stderr/0` and its call at
   the top of `start_stdio_setup/2` in `src/erlmcp.erl` (the `e467d41` change). Logger
   destination is not application code's job.

2. **Fix `config/sys.config`.** Change the `kernel` default handler from
   `type => standard_io` to **`type => standard_error`**. Leave the file handler. Net
   effect: every log record (incl. app-start INFO reports and the SIGTERM message) goes
   to stderr/file, never stdout.

3. **Make the launchers load the config.** In each `examples/*/run.sh`, add `-config`
   so `sys.config` is actually applied at kernel boot (before any report is emitted).
   **Gotcha:** `erl -config` appends `.config`, so pass the basename without the
   extension — `-config "$REPO/config/sys"` loads `config/sys.config`. Verify it loads
   (don't assume): after boot, `logger:get_handler_config(default)` must show
   `type => standard_error`. (`cd`s to repo root already, so a relative `config/sys`
   works.)

4. **Prove stdout is clean.** Add a launcher-level smoke check (script or CT via a
   port): start the server through `run.sh`, send an `initialize` request on stdin,
   and assert **every line on stdout parses as a JSON-RPC message** — nothing else —
   while log output appears on stderr. This guards against regressions the in-VM smoke
   suites can't see (they don't exercise the real launcher + the real logger config).

## Notes / idiom

- `standard_error` is the MCP-spec-correct destination for stdio-server logs (the
  client reads stderr separately, never as protocol). This is the idiomatic OTP fix:
  logger config lives in `sys.config`, applied via `-config` at boot.
- For the eventual production-deployment story (the `creating-an-mcp-server.md` howto),
  a relx **release** bundles `sys.config` and loads it automatically — no `-config`
  flag needed. Worth noting there as the robust packaging path; the `erl -config`
  launcher is fine for the examples.

## Verify

- `git show` confirms `redirect_logger_to_stderr/0` is gone from `erlmcp.erl`.
- `config/sys.config` default handler is `type => standard_error`.
- `examples/*/run.sh` pass `-config config/sys`; a booted server shows the default
  handler on `standard_error`.
- The launcher smoke check: stdout is pure JSON-RPC, logs on stderr.
- All existing gates stay green.

## Done when

Logging is configured at the `sys.config` layer (not in `erlmcp.erl`), the launchers
load it, stdout carries only JSON-RPC under the real launcher, and a smoke check guards
it. Then re-attempt the Claude Desktop attach — the `=INFO REPORT`/`SIGTERM` JSON errors
should be gone. Submitted for CDC sign-off.
