# erlmcp 0.6.0 — Development Plan

**Mission.** Bring erlmcp to the same standard of quality as the Rust MCP SDK
(rmcp), realized in idiomatic Erlang/OTP — matching rmcp on ergonomics,
correctness, architecture, and coverage/docs/conformance, and *beating* it where
the BEAM is naturally stronger.

**Mandate (from the project owner).** Full modernization; **break freely** (no
obligation to preserve the 0.5.0 API); Inaka guidelines (+ the OTP reference texts)
as the house style until a dedicated erlmcp SKILL.md exists.

**Strategy.** A **clean re-core**, not incremental patching. Phase 3 showed the
existing server is three overlapping implementations (one supervised but weaker,
one fuller but unsupervised), with transports that reference nonexistent modules.
Given "break freely," rebuilding the core around the Phase 2 design is faster and
sounder than untangling the forks. We keep what's genuinely reusable (much of the
JSON-RPC and schema logic, the examples, the docs *structure*) and re-seat it on a
`gen_statem` session + per-request-process spine.

This plan is the synthesis of:
`phase0-mcp-capability-rubric.md` (what the protocol needs) ·
`phase0-erlang-rubric.md` (how we may build it) ·
`phase1-rmcp-audit.md` (the reference bar) ·
`phase1b-erlmcp-inventory.md` (the starting point) ·
`phase2-idiomatic-erlmcp.md` (the target design) ·
`phase3-gap-analysis.md` (the deltas, classified).

---

## 1. Guiding principles (carry these into every PR)

1. **Imitate the protocol, not Rust.** Re-realize each capability in OTP; consult
   the divergence ledger (Phase 2 §11) before copying any rmcp shape.
2. **Foundations before features.** The architectural P0s (gen_statem session +
   per-request workers + transport behaviour) come first because most feature gaps
   are blocked behind them (Phase 3 §6.2).
3. **One way to do a thing.** No parallel `_new` modules ever again. If something
   is being replaced, replace it.
4. **Validate at the edge, crash in the interior.** (Phase 2 §5.)
5. **A feature isn't done until it's in the conformance scorecard.** Coverage is
   measured, not asserted.
6. **The `erlmcp` facade is the only stable surface.** Everything else is internal
   and may change.

---

## 2. Milestone sequence

Milestones are ordered by dependency, not by feature glamour. Each lists its
deliverables, the Phase 3 gaps it closes, and its definition of done.

### M0 — Decide, scaffold, and clear the ground
*Goal: a clean slate and the decisions that everything else depends on.*

- Delete the `_new` forks and the unsupervised duplicate server; remove the
  phantom `erlmcp_client_sup` from `app.src`; remove dispatch to nonexistent
  `*_tcp_new`/`*_http_new`. (Closes D: dead code, phantom modules, broken sup.)
- Decisions to lock: JSON library (keep `jsx` behind an `erlmcp_codec` boundary, or
  move to `jsone`/`thoas` — decide once); confirm `jesse` as the schema validator;
  minimum OTP version (recommend OTP 26+); rebar3 profiles and a real coverage gate.
- Stand up the new module skeleton from Phase 2 §10 (empty modules + behaviours +
  specs), so the architecture is visible before logic lands.
- Write a short `MIGRATION-0.5-to-0.6.md` stub (filled in as the API solidifies).

DoD: project compiles with the new skeleton; CI green; no `_new` modules remain;
xref clean.

### M1 — The re-core (foundational architecture) · **P0**
*Goal: a working stdio session that can initialize, ping, negotiate version, and
cancel — end to end — with nothing else.*

- `erlmcp_codec` (JSON boundary) + `erlmcp_json_rpc` (2.0 envelope encode/decode/
  classify, full error-code set, graceful batch parsing).
- `erlmcp_model` (opaque MCP types + constructors/accessors; **no shared records**).
- `erlmcp_capabilities` (capability + **protocol-version negotiation** over a
  declared supported-version set).
- `erlmcp_server_session` and `erlmcp_client_session` as `gen_statem`s
  (`uninitialized → initializing → operational → shutting_down`).
- **Per-request worker model:** session spawns + monitors one process per in-flight
  request; `erlmcp_ctx` carries progress/cancellation/_meta/peer handle.
- **Cancellation = kill the worker**; **ping**; request-id correlation table.
- `erlmcp_transport` behaviour + `erlmcp_transport_stdio` (fixing the deadlock
  pattern); supervision tree per Phase 2 §3.
- `erlmcp_registry` demoted to discovery/binding only (off the hot path).

Closes: C (per-request processes, gen_statem session, transport behaviour, registry
hot-path); A (cancellation, ping, version negotiation). DoD: an stdio client and
server in the same VM complete initialize→ping→cancel; PropEr model of the envelope
+ lifecycle passes; Dialyzer clean.

### M2 — Server feature surface · **P0/P1**
*Goal: a server that passes the bulk of the conformance server scenarios.*

- **Tools:** `tools/list`, `tools/call`, **input-schema validation** (jesse),
  **output schema + structured content**, content types (text/image/audio/embedded
  resource/resource link), annotations, runtime add/remove → automatic
  `notifications/tools/list_changed`.
- **Ergonomics layer:** `erlmcp_schema` builder + the data-driven `add_tool/2` API +
  the `erlmcp_server_handler` behaviour (Phase 2 §1) — the "low-boilerplate without
  macros" story.
- **Discoverability layer** (see `m2-discoverability-design.md`): wayfinding metadata
  (`when_to_use`/`next`/`category`/`returns`/`summary`) as optional keys on the
  `add_tool/2` map, derived into three surfaces — `InitializeResult.instructions`
  (strategy/categories/entry points only), per-tool `_meta` in `tools/list`
  (namespaced under `erlmcp`), and a generated **directory tool**. Behavioral hints go
  in protocol `annotations`. The registration map is the single source of truth; all
  surfaces are derived so they cannot drift (the failure mode that left 32/51 tools
  ungoverned in the Fabryk reference server). The directory tool is an explicit
  non-protocol extension (excluded from the M5 scorecard; see M5).
- **Resources:** list/read, **templates**, subscribe/unsubscribe, `updated` +
  `list_changed`.
- **Prompts:** list/get + `list_changed`.
- **Logging** (`setLevel` + `notifications/message`) — make the advertised
  capability real.
- **Completion** (`completion/complete`).
- **Pagination** (cursor/nextCursor) across all list endpoints.
- **Progress** via `erlmcp_ctx` from inside workers.

Closes: A (output schema/validation, completion, logging, pagination, structured
content, templates); B (god-module, records→opaque, boolean-param cleanup as these
APIs are written). DoD: a non-trivial example server (rebuild the weather/calculator
examples on the new core) exercises every server capability; conformance server
score ≥ rmcp's reference; **discoverability invariants DISC-1…DISC-9 closed**
(`m2-discoverability-design.md` §9) — in particular 100% tool metadata coverage, a
dangling-free and orphan-free `next` graph, and all surfaces derived from one source.

### M3 — Client + server→client features · **P1**
*Goal: a symmetric client; the inverted-direction features work.*

- Full `erlmcp_client_session` API: list/read/call/get, subscriptions, progress
  receipt, cancellation issuance.
- **Sampling** end-to-end (server-initiated `sampling/createMessage` → client
  callback), not just client-side dispatch.
- **Roots** (`roots/list` + `list_changed`) and **elicitation** (`elicitation/create`)
  as client callback behaviours (`erlmcp_sampling`, `erlmcp_roots`,
  `erlmcp_elicitation`).

Closes: A (roots, elicitation, full sampling); C (client/server symmetry). DoD:
client and server in separate VMs complete a sampling + elicitation round-trip;
conformance client score ≥ rmcp's reference.

### M4 — Transports · **P1**
*Goal: production transports behind the one behaviour.*

- `erlmcp_transport_tcp`, `erlmcp_transport_http` (HTTP + SSE),
  `erlmcp_transport_streamable_http` (current-spec HTTP transport), each a
  `gen_server` implementing `erlmcp_transport`; session stays transport-agnostic.
- **Harvest, don't reinvent:** the `erlmcp_transport` behaviour interface,
  `validate_transport_config/1`, the per-transport + behaviour-conformance test-suite
  layout, and the `start_{stdio,tcp,http}_setup` convenience functions are taken from
  the July-2025 prior art (see `phase5-prior-art-reconciliation.md` §5 and Phase 2 §6).
  The only change: transports deliver to/receive from the **bound session directly**,
  not via registry hot-path routing.
- **Baseline as of 2026-05-20 — http is the reference pattern.** Issue #4 (the
  `gen_server:call(self(),...)` deadlock) is fixed in commit 57e2f50: `erlmcp_transport_http`
  is now a real gen_server started via `start_link(Opts#{owner => self()})`, with
  `send/2` messaging the transport Pid and responses delivered `Owner ! {transport_message, _}`
  — i.e. **already pid-based and already off the registry hot path**. M4's job is to bring
  `erlmcp_transport_stdio` and `_tcp` up to this same shape (pid-based, owner/session-direct
  delivery), **not** to revert http. Its meck-mocked test suite (`erlmcp_transport_http_tests.erl`)
  is the template for the per-transport suites.

Closes: C (transport behaviour fully realized). DoD: the same example server runs
unchanged over stdio, TCP, and streamable HTTP; transport conformance scenarios pass.

### M5 — Quality infrastructure · **P0 for credibility**
*Goal: the artifact that earns "same quality as rmcp."*

- **`erlmcp_conformance`:** a Common Test harness that drives a real session through
  every L0–L4 capability and emits a **dated, versioned scorecard** (mirroring
  rmcp's `conformance/results/*`). The protocol-native discoverability surfaces
  (`instructions`, tool `_meta`, `annotations`, resources) are scored like any other
  capability; the **directory tool is an erlmcp extension and is excluded from the
  scorecard** (DISC-6, `m2-discoverability-design.md` §7).
- Full test pyramid: EUnit (units, 1–2 asserts), Common Test (lifecycle/transport/
  e2e), **PropEr** (envelope + state-machine fuzzing). Real coverage gate (retire
  `--min_coverage=0`).
- `-spec`/`-type` on all exports; Dialyzer in CI; xref clean.
- **Docs rewrite to match the code** (architecture, protocol, OTP patterns, API
  reference) + accurate README + the finished migration guide. Examples all on the
  new core.
- Release/security automation: SemVer + a maintained CHANGELOG; consider CodeQL/
  dependabot equivalents.

Closes: D (conformance harness, test strategy, stale docs, release discipline);
B (specs/coverage). DoD: scorecard published; CI runs EUnit+CT+PropEr+Dialyzer+
coverage; docs verified against code.

### M6 — Native-strength features · **P1/P2**
*Goal: the places erlmcp can exceed rmcp (Phase 2 §12).*

- **Tasks** (long-running): `tasks/get|list|result|cancel` as supervised task
  processes + per-tool task support.
- `_meta` channel end-to-end; icons; graceful batch tolerance hardening.

Closes: A (tasks, _meta, batch). DoD: a long-running tool reports via tasks and can
be cancelled mid-flight; conformance covers tasks.

### M7 — Stretch / post-0.6
- OAuth 2.1 client subsystem (rmcp has it; large and self-contained — sequence after
  0.6.0 unless a user needs it).
- Multi-node / distributed registry (`pg`/`gproc`), telemetry/metrics hooks.

---

## 3. Why this order (sequencing rationale)

- **M1 is load-bearing.** Phase 3 §6.2: cancellation, ping, and version negotiation
  are all blocked behind the gen_statem-session + per-request-process change. Build
  the spine once and those features become small.
- **Validation rides with M2** because it's where tool I/O is defined; retrofitting
  validation later means touching every handler twice.
- **Conformance (M5) is scheduled as a milestone, but the harness is grown
  incrementally** from M1 onward — each feature milestone adds its scenarios. M5 is
  where it's formalized into a scorecard, not where testing begins.
- **OAuth and distribution are deferred** so they don't hold 0.6.0 hostage; neither
  is core MCP.

---

## 4. Breaking-change & release strategy

0.6.0 is an intentional clean break. To make it a *responsible* one:

- The `erlmcp` facade is the only documented surface; design it first and freeze it
  early so examples/docs stabilize.
- Ship `MIGRATION-0.5-to-0.6.md` mapping each old entry point to its new form
  (e.g. `erlmcp_server:add_tool_with_schema/4` → `erlmcp:add_tool/2` with an
  `erlmcp_schema`-built schema).
- Tag a `0.5.x` maintenance branch before the re-core so existing users aren't
  stranded mid-migration.
- SemVer + Keep-a-Changelog discipline from M0.

---

## 5. Risks & open questions

| Risk / question | Mitigation / decision needed |
|---|---|
| **Schema ergonomics gap** (no derive-from-types) is inherent | Invest in `erlmcp_schema` builder quality; accept and document the limit (Phase 2 §1). Decide how far to push the builder. |
| JSON library choice (`jsx` vs `jsone`/`thoas`) | Decide in M0; isolate behind `erlmcp_codec` so it's reversible. |
| Streamable-HTTP transport complexity (sessions, resumability) | Largest transport lift; may slip within M4 — keep stdio/TCP as the guaranteed set. |
| Conformance reference: what do we measure against? | Use the MCP spec + rmcp's published scenarios as the bar; consider interop tests against rmcp itself. |
| Minimum OTP version | Recommend OTP 26+; confirm with owner (affects gen_statem features, maps, `-doc`). |
| Owner's erlmcp SKILL.md not yet written | The Inaka rubric is the interim bar; revisit convention-dependent calls (Phase 2 flags them) once the SKILL.md lands. |

---

## 6. Definition of done for 0.6.0

1. One server implementation, one client implementation, both `gen_statem`-based,
   no `_new` forks anywhere.
2. Full L0–L4 capability coverage for the targeted spec version (**2025-11-25**),
   minus the explicitly deferred items (OAuth, distribution).
3. Input *and* output schema validation actually enforced.
4. A published conformance scorecard at least matching rmcp's (server 87.5% /
   client 80%) — ideally exceeding it.
5. EUnit + Common Test + PropEr suites, Dialyzer-clean, real coverage gate.
6. Docs and examples that match the code, plus a migration guide.
7. The three native-strength differentiators demonstrated: cancellation-as-exit,
   per-request fault isolation, supervised long-running tasks.

---

## 7. One-screen summary

> Re-core erlmcp around a `gen_statem` session with one supervised process per
> request (M1); that single move unlocks cancellation, ping, and version
> negotiation and gives erlmcp fault-isolation and cancellation semantics *better*
> than rmcp's. Build the full server surface with real schema validation and a
> no-macro ergonomic API plus a derived, drift-proof discoverability layer (M2), a symmetric client with sampling/roots/elicitation
> (M3), production transports behind one behaviour (M4), and — the part that earns
> "rmcp-quality" — a conformance scorecard plus a real EUnit/CT/PropEr/Dialyzer
> test pyramid and accurate docs (M5). Tasks and other BEAM-native wins follow
> (M6); OAuth and distribution are post-0.6 (M7). Break freely, migrate
> responsibly, measure everything.
