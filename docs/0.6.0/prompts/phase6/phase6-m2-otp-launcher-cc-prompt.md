# CC Prompt — P6-M2: the 100% OTP launcher (reference: `simple`)

> Imperative brief for **CC**. This is the **blocking** piece of P6-M2: stdio is
> not "working" until we can launch it to test it, and the launcher must be done
> the **100% OTP way** — no `erl -eval` workaround, no monitor/`halt` hand-wiring.
> Build **`simple`** as a proper OTP application + relx release; it becomes both
> the round-trip test fixture and the template `calculator`/`weather` clone later.
> **CDC** re-runs the verification. Escalate, don't work around.

## Why (the diagnosis you're fixing)

The current `run.sh` does `erl -noshell -eval "simple_server:start()"`. `start/0`
builds `erlmcp_stdio_sup` via `supervisor:start_link`, which **links the tree to
the transient eval process**. When `start/0` returns, the eval process exits and
the linked supervisor terminates — the whole tree (incl. the stdin reader) dies,
the VM lingers under `-noshell`, and the server "starts but never responds." The
OTP fix is to make the tree **owned by the application controller** (an OTP
application), whose lifetime is the node's, not the launcher's.

## What to build

**1. `simple` becomes an OTP application.** In `examples/simple/`:
`simple.app.src` gets `{mod, {simple_app, []}}`, `{applications, [kernel, stdlib,
erlmcp]}`, and `{start_phases, [{serve, []}]}`. Add `simple_app` (application
behaviour).

**2. `simple_app:start/2` brings up the stdio subtree under the app.** It starts
`erlmcp_stdio_sup` (the per-server subtree: server + session + transport) with the
catalog **from config** (app env / start args — e.g. `#{name => simple, handler =>
simple_server}`), transport **paused**, and returns `{ok, SupPid}`. The
application master now owns the tree. Register the subtree under a known local name
(single-server release) so the serve phase can find it.

**3. `simple_app:start_phase(serve, _StartType, _Args)` calls `serve/1`.** Start
phases run *after* `start/2` returns (tree fully up) and before the app reports
started — so "fully built, then go live" is guaranteed by the OTP boot sequence.
This is the intended `start_phases` use (planning §3.6). (If locating the sup from
`start_phase` proves awkward, calling `serve/1` at the tail of `start/2` after the
tree is built is an acceptable variant — but prefer the phase.)

**4. Lifetime is OTP-managed.** App runs **`permanent`** in the release. Chain:
stdin EOF → reader exits → subtree (`one_for_all`, `intensity 0`) terminates →
permanent app terminates → **node shuts down cleanly**. No explicit `halt` — this
*is* P6M2-9 (EOF shutdown), delivered by OTP semantics.

**5. relx release for the `simple` profile.** Add a `relx` release to
`rebar.config` (under the `simple` profile): release name `simple`, apps
`[erlmcp, simple]`, bundling `config/sys.config` and a `vm.args`.

**6. Eliminate the `Exec:`/`Root:` stdout pollution from the launcher.** Empirical
status (verified via Claude Desktop, which round-trips tool calls today): the
release launches, `vm.args` correctly sets **`-noshell`** (not `-noinput`), and the
`io:get_line(user, "")` reader gets stdin — **the servers work.** The *only*
residual defect is that `bin/<rel> foreground` **echoes `Exec:`/`Root:` to stdout**
before exec (~lines 988–996, "Dump environment info"). Those non-JSON lines are the
"Unexpected token 'E', \"Exec: /opt\"…" parse errors Claude Desktop shows at
startup. Claude Desktop *tolerates* them (logs the errors, then reads the real
JSON-RPC) — but a stricter MCP client would reject the connection on that preamble,
and it violates "stdout carries protocol bytes only" (§1.1). So clean it.

The clean fix is to **boot the VM directly instead of via the `foreground`
wrapper**, so we control stdout and emit no diagnostics. The wrapper's own `Exec:`
line *is the recipe*: run `bin/simple foreground` once, copy the `Exec:` invocation
(it has the exact `-boot`/`-boot_var`/`-config`/`-args_file`), and replicate it in
`run.sh` with **`-noshell`** (drop `-noinput +Bd`) and **no echoes**. Keep the
existing `-noshell` `vm.args`. Do **not** use `console` (it starts a shell — banner
on stdout, competes for stdin). **Document the exact invocation** (howto §4.4 seed).
(Note: this is a stdout-hygiene fix, not a "nothing works" fix — don't destabilise
the working launch; the goal is a clean channel, verified by the assertion below.)

**7. `run.sh` boots the release directly (no `erl -eval`, no `foreground`/`console`).**
After `rebar3 as simple release`, `exec erl -noshell -boot
<rel>/releases/<vsn>/start -boot_var … -config <rel>/releases/<vsn>/sys -args_file
<rel>/releases/<vsn>/vm.args` (derived from the `Exec:` line per #6). Still a proper
release boot — app-controller-owned, permanent, EOF→node-halt — just without the
chatty daemon wrapper.

## Verify

- **Round-trip via the release:** launch `run.sh`, feed `initialize` +
  `notifications/initialized` + `tools/list` on stdin → full catalog on stdout.
  Harden `test/scripts/test_stdio_roundtrip.sh` to drive the release **and to
  assert stdout purity**: the **first non-blank line on stdout MUST parse as JSON**
  — no `Exec:`/`Root:`/path preamble, no `=INFO`/`=PROGRESS`/`=CRASH`. This single
  assertion catches both the launcher-echo pollution and (via no-response) the
  `-noinput`-can't-read failure; it's the regression guard for this whole class.
- **Lifetime:** the server stays alive while stdin is open; **stdin EOF → the node
  exits cleanly** (sane exit, no `reader_died` spew).
- **Not via a disqualified launcher:** `! grep -nE "eval|foreground|console" examples/simple/run.sh`.
- `make check` green; `make dialyzer` clean on OTP 27 and 28.

## Escalate, don't work around

If release `foreground` + `-noshell` + stdin proves fiddly (it can — foreground
mode and stdin handling have sharp edges), **surface the exact behaviour** (does it
read stdin? does `-noshell` hold in foreground? is `user` the right device?) and
we'll solve it the OTP way together. Do **not** fall back to `erl -eval`,
monitor/`halt`, or any scripted lifetime hack — that's the pattern we're
eliminating. This is the teamwork seam: you surface what the release VM actually
does; CDC/Duncan decide the OTP-correct resolution.

## Out of scope

- `calculator`/`weather` full app+release conversion — **P6-M6**, cloning this
  `simple` reference as the template. Do **only** `simple` here.
- HTTP/Cowboy (**P6-M4**); jesse payload validation (**P6-M5**); discoverability
  enrichment (**P6-M3**).

## Done when

`simple` is an OTP application launched via a relx release whose tree is owned by
the application controller; `run.sh` uses the release (no `erl -eval`); the
round-trip test passes against the release-launched server; stdin EOF exits the
node cleanly; the exact `-noshell` vm.args recipe is documented; `make check` green
and dialyzer clean on 27/28.
