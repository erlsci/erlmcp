# Phase 6, Milestone P6-M2: stdio on the new shape (+ serve/1 gate)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M2):** the first transport fully working on the correct
spine. Rebuild `erlmcp_transport_stdio` against the redefined `erlmcp_transport`
behaviour and the `erlmcp_reply` responder seam; start it **paused** and add the
`serve/1` go-live gate; fold server + session + transport into a **per-server
subtree**; and make `start_stdio_setup/2` build that subtree, register the catalog
from `Config`, **then** serve — so the startup race that began this whole arc is
closed **by construction**, not patched. Exit: an `initialize → ping → tools/list →
tools/call → cancel` round-trip over real stdio, a subprocess round-trip test, and
a "register N → `*/list` returns N" conformance test, all green on OTP 25–28
(dialyzer on 27/28).

**Locked decisions (carried):** JSON via `jsx` behind `erlmcp_codec` only; `jesse`
at the edge; min OTP 25+; coverage 90% scoped via `cover_excl_mods`; validate at
the edge, crash in the interior; opaque types + accessors, no shared records; one
way to do a thing, no `_new` forks. **Never loosen a check to make it pass**
(`CLAUDE.md`): no suppressions, no widened specs, no skipped tests — escalate
instead. Dialyzer is gated to OTP 27+ (`make dialyzer`); run it on 27 **and** 28.

**Branch:** `task/0.6.0-p6m2`, cut from `release/0.6.x` **after P6-M1 merges**.
PR back into `release/0.6.x`. All Verify commands run from the repo root. All rows
start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M2-1 | `erlmcp_transport_stdio` implements the redefined `erlmcp_transport` behaviour (`init`/`serve`/`close`); the old `send(state(), iodata())` shape is gone. | `grep -q "behaviour(erlmcp_transport)" src/erlmcp_transport_stdio.erl`; `grep -qE "serve\(" src/erlmcp_transport_stdio.erl`; `! grep -n "send(state()" src/erlmcp_transport_stdio.erl`. | serious | Phase 6 §3.4–3.5 | open | | |
| P6M2-2 | The transport starts **paused** — the stdin reader is **not** spawned in `init/1`; only `serve/1` spawns it. | `! grep -nE "spawn(_link)?\(" ` within the `init/` clause of `src/erlmcp_transport_stdio.erl`; CT: a transport that is started-but-not-served delivers nothing; after `serve/1`, input is read. | serious | Phase 6 §3.5–3.6, §1.4 | open | | The structural half of the race fix. |
| P6M2-3 | Outbound goes through the responder: the session emits via `erlmcp_reply` to a `{device, _}` responder bound to the transport; no session-side `io:put_chars`/direct-stdout bypass. | `! grep -nE "io:(put_chars\|format)\(" src/erlmcp_server_session.erl`; CT: a response written by the session arrives on stdout via the transport. | serious | Phase 6 §3.3 | open | | The transport is the device writer; `erlmcp_reply:send({device,Pid},_)` → `Pid ! {send,_}`. |
| P6M2-4 | A **per-server subtree** supervises `{erlmcp_server, erlmcp_server_session, erlmcp_transport_stdio}` as one unit (lifetimes coincide; restart strategy chosen and documented). | New subtree supervisor module with the three child specs; CT: the three start as a unit; the chosen strategy's failure behaviour holds (document `rest_for_one`/`one_for_all` + `temporary`/`transient` choice in Notes). | serious | Phase 6 §3.5; OTP error-kernel | open | | Draws the error-kernel boundary around the unit that must live/die together (fixes the M1 finding that session+transport were flat siblings). |
| P6M2-5 | `start_stdio_setup/2` builds the subtree, registers the catalog **from `Config`** (config-driven, in the server's synchronous start), and **then** calls `serve/1` — one call, race impossible. | EUnit/CT: `start_stdio_setup(Id, #{tools=>…,resources=>…,prompts=>…})` yields a fully-catalogued, serving server with **no** post-setup registration call. | serious | Phase 6 §3.6, §1.4 | open | | The behavioural half of the race fix. |
| P6M2-6 | **Race conformance:** register N tools + M resources + K prompts via config, drive `initialize` then `tools/list`/`resources/list`/`prompts/list` over stdio — each list returns **all** registered items (no undercount, no trailing `list_changed`). | CT (e.g. `erlmcp_stdio_SUITE`): counts equal N/M/K for all three list endpoints. | serious | Phase 6 §1.4; the bug that began the arc; **M1 lesson (encode race-closure as a test)** | open | | This is the regression guard that would have caught the original 4-of-7. |
| P6M2-7 | Round-trip subprocess test: the **release-launched** `simple` server (see P6M2-15/16), fed `initialize`+`initialized`+`tools/list` on stdin, returns the full catalog on stdout. | `test/scripts/test_stdio_roundtrip.sh` passes in CI driving the relx-release `simple` server. | serious | handoff §1.8 | open | | The in-VM `simulate_input` path bypasses real I/O **and the launcher lifetime** — it hid both the original group-leader bug and the eval-process-link bug. This is the test that catches them. |
| P6M2-8 | End-to-end in-VM over stdio: `initialize → ping → tools/list → tools/call → cancel`. | CT `erlmcp_e2e_SUITE` (or stdio suite) passes the scenario over the real stdio transport. | serious | Phase 6 §6 P6-M2 DoD | open | | The milestone's headline acceptance scenario. |
| P6M2-9 | stdin **EOF triggers clean shutdown** of the subtree (the OS process exits; no hang). | CT/script: closing stdin terminates the transport and tears the subtree down cleanly (no `reader_died` error spew, exit code sane). | serious | handoff §3 (open: "server doesn't exit on stdin EOF") | open | | Decide + implement: client closing stdin = server exits. |
| P6M2-10 | stdout carries **JSON-RPC bytes only**; logs/progress/crash reports go to stderr. | round-trip test asserts no `=INFO REPORT`/`=PROGRESS`/`=CRASH` or stray bytes on stdout; `config/sys.config` routes the kernel logger to `standard_error`. | serious | handoff §1.1 | open | | Regression guard for the original "could not attach" pollution. |
| P6M2-11 | **Coverage scoping (pre-specified, per M1 lesson):** `erlmcp_transport_stdio` and the new subtree supervisor are **included** and each ≥90%; `cover_excl_mods` still excludes — with re-entry noted here — `erlmcp_transport_streamable_http` (→P6-M3, replaced), the client transports `erlmcp_transport_tcp`/`erlmcp_transport_http` (orthogonal; their milestone), and example modules (→P6-M5). | `rebar3 as test cover -v --min_coverage=90` exits 0; the two M2 modules ≥90% per-module; every `cover_excl_mods` entry has a re-entry note. | serious | Locked decision (coverage); **M1 lesson (scope up front, not at iteration 3)** | open | | Settle the exclusion list in the first commit, not under pressure later. |
| P6M2-12 | Dialyzer clean on **OTP 27 and 28** under the strict set with **zero suppressions**; `compile` warning-free; `xref` clean. | `make dialyzer` clean on 27 and on 28; `make check` exits 0; `! grep -rn "nowarn\|-dialyzer(" src` (no new suppressions). | serious | DoD; `CLAUDE.md` never-loosen rule | open | | If a widened spec or new code trips dialyzer, fix it or escalate — never suppress. |
| P6M2-13 | CI green on `task/0.6.0-p6m2` across the OTP 25–28 matrix. | CI workflow (compile + xref + examples + eunit + CT + proper + dialyzer[27/28] + cover) passes. | serious | DoD | open | | CI is the independent reproducer; CDC sandbox has no toolchain. |
| P6M2-14 | The dynamic path survives as a documented escape hatch: `start_server` + `start_transport(paused)` + manual registration + explicit `serve/1`. Registering **after** `serve` is the unsupported ordering, documented. | A test drives the dynamic path with explicit `serve/1`; a doc/spec note states the caller owns gating on this path. | correctness | Phase 6 §3.6 | open | | Keeps genuine runtime/dynamic registration possible without reintroducing the race for the common (config-driven) path. |
| P6M2-15 | **The standalone server is launched the 100% OTP way:** `simple` is an OTP **application** whose supervision tree is owned by the **application controller** (not a transient `erl -eval` process); it stays alive while stdin is open and the node **exits cleanly on EOF** (permanent app → subtree down → node halt). | `! grep -n "eval" examples/simple/run.sh` (no eval launcher); CT/script: server responds while stdin open, and stdin EOF exits the node cleanly. | serious | the eval-process-link lifetime bug; Duncan: "100% OTP, no workarounds" | open | | The OTP fix for "starts but never responds": the tree must be application-owned. Subsumes/realises P6M2-9 via OTP lifetime semantics. `simple` is the **reference**; calculator/weather clone it in P6-M5. |
| P6M2-16 | A **relx release** for the `simple` profile bundles `erlmcp`+`simple`+`config/sys.config`+`vm.args`; the VM runs `-noshell` (**not** `-noinput`) so the transport reads stdin and stdout carries protocol bytes only. The exact vm.args recipe is documented. | `rebar3 as simple release` builds; `run.sh` boots the release; round-trip (P6M2-7) green; the `-noshell` vm.args recipe is written down (howto §4.4 seed). | serious | Phase 6 release route; handoff §1.1 | open | | The make-or-break detail for stdio-under-a-release; nail it once, document it, let the round-trip test guard it. |
| P6M2-17 | "Go live" is sequenced by the OTP boot, not ad-hoc: `serve/1` runs from a `start_phases` `serve` phase (after the tree is fully up), or equivalently at the tail of `start/2` once the tree is built. | `grep -q "start_phases" examples/simple/simple.app.src`; the serve phase calls `erlmcp_stdio_sup:serve/1`; race-conformance (P6M2-6) holds for the released server. | correctness | Phase 6 §3.6 (start_phases at the release layer) | open | | The application-layer expression of "build fully, then serve" we predicted in the planning doc. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M2 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M3+

_(Filled in at close — e.g. the `{http,_,_}`/`{sse,_}` responder kinds + Cowboy
listener + session manager (P6-M3); example rehab onto config-driven setup (P6-M5).
Note any module still in `cover_excl_mods` with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 17. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.

**Scope note (2026-05-27):** P6-M2 absorbed the 100% OTP launcher (rows
P6M2-15/16/17) when the `erl -eval` launcher was found to kill the
application-unowned tree — testability of stdio is a prerequisite to proceeding,
so the OTP application/release work moved here from the old P6-M5/M6 plan. Only
the `simple` reference is built here; calculator/weather clone it in P6-M5, and
P6-M6 documents the recipe.
