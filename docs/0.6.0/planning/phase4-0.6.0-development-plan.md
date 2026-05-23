# erlmcp 0.6.0 — Development Plan

**Mission.** Bring erlmcp to the same standard of quality as the Rust MCP SDK
(rmcp), realized in idiomatic Erlang/OTP — matching rmcp on ergonomics,
correctness, architecture, and coverage/docs/conformance, and *beating* it where
the BEAM is naturally stronger.

**Mandate (from the project owner).** Full modernization; **break freely** (no
obligation to preserve the 0.5.0 API); the **erlmcp Erlang AI skill**
(`priv/ai/erlang/SKILL.md` + `guides/`, symlinked into the repo; live as of
2026-05-21) is the house-style reference, built on the Inaka/OTP rubric
(`phase0-erlang-rubric`).

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
- Decisions (locked 2026-05-20): **JSON library** = keep `jsx`, isolated behind the
  `erlmcp_codec` boundary so the choice stays reversible; **schema validator** =
  `jesse`; **minimum OTP** = **25+** (note: forgoes `-doc`/EEP-48 attributes from
  OTP 27 — M5 docs use edoc/ex_doc); **coverage gate** = **90%, scoped to
  implemented modules** — empty skeletons and legacy modules slated for
  replacement/deletion are excluded via `cover_excl_mods`; the exclusion list
  shrinks each milestone as modules are implemented+tested or deleted, reaching
  **95% over the whole codebase by M5** (retire `--min_coverage=0`). Rationale: a
  flat aggregate gate conflicts with a re-core that front-loads empty scaffolding
  and carries soon-to-be-deleted legacy (M0 CI hit 38%). Plus rebar3 profiles.
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

**Split into M2a + M2b** (2026-05-21): the original single M2 spanned ~four
rmcp-quality feature areas — too large for the 5-iteration cap. Tools-first is
dependency-sound (resources/prompts reuse the same schema/validation/`list_changed`/
pagination patterns, and discoverability rides on the `add_tool/2` map).

#### M2a — Tools, ergonomics & discoverability
*Ledger: `milestones/M2a-tools-ergonomics-discoverability-ledger.md`.*

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
  (reverse-DNS namespace `io.erlmcp/`), and a generated **directory tool**. Behavioral
  hints go in protocol `annotations`. The registration map is the single source of
  truth; all surfaces are derived so they cannot drift (the failure mode that left
  32/51 tools ungoverned in the Fabryk reference server). The directory tool is an
  explicit non-protocol extension (excluded from the M5 scorecard; see M5).
- **Progress** via `erlmcp_ctx` from inside tool workers.

DoD: a calculator-style example exercises the tool surface end-to-end; **DISC-1…DISC-9
closed** (`m2-discoverability-design.md` §9) — 100% tool metadata coverage, a
dangling-free and orphan-free `next` graph, all surfaces derived from one source;
Dialyzer clean; CI green.

#### M2b — Resources, prompts, logging, completion & conformance
*Ledger: `milestones/M2b-resources-prompts-logging-completion-ledger.md`. Depends on M2a.*

- **Resources:** list/read, **templates**, subscribe/unsubscribe, `updated` +
  `list_changed`.
- **Prompts:** list/get + `list_changed`.
- **Logging** (`setLevel` + `notifications/message`) — make the advertised
  capability real.
- **Completion** (`completion/complete`).
- **Pagination** (cursor/nextCursor) across the resources/prompts list endpoints.

Closes: A (output schema/validation, completion, logging, pagination, structured
content, templates); B (god-module, records→opaque, boolean-param cleanup as these
APIs are written). DoD: a resource/prompt example exercises those capabilities;
**conformance server score ≥ rmcp's reference** (the harness's server scenarios land
here; the formal scorecard is M5).

### M3 — Client + server→client features · **P1**
*Goal: a symmetric client; the inverted-direction features work.*

**Split into M3a + M3b** (2026-05-22): the original single M3 spanned the full
client request surface (mirroring M2a+M2b) **plus** the three server→client callback
features and the bidirectional request machinery they need — ~25+ rows, too large
for the 5-iteration cap (same reasoning as the M2 split). The seam is direction:
M3a is the client as a *consumer* of the server (client→server); M3b adds the
*server-initiated* features (server→client) and the symmetric request plumbing.
M3b depends on M3a.

#### M3a — Client request API
*Ledger: `milestones/M3a-client-request-api-ledger.md`. Depends on M1 (client_session
spine) + M2a/M2b (the server surface it consumes).*

- Full `erlmcp_client_session` request API consuming the M2 server: `tools/list` +
  `tools/call`; `resources/list`/`read`/`templates/list` + subscribe/unsubscribe;
  `prompts/list`/`get`; `logging/setLevel`; `completion/complete`.
- **Pagination consumption** (cursor/nextCursor) across the client list calls.
- **Progress receipt** (inbound `notifications/progress` delivered to the caller)
  and **cancellation issuance** (client emits `notifications/cancelled`).
- **Notification receipt:** `notifications/*/list_changed`,
  `notifications/resources/updated`, `notifications/message`.
- **Capability gating:** the client only invokes endpoints the server advertised at
  `initialize`.
- **One client:** legacy `erlmcp_client` is deleted; `erlmcp_client_session` is the
  only client (closes the M1 carry-forward + the `cover_excl_mods` `erlmcp_client`
  entry).

DoD: a client example drives the full request API against an M2 server (same-VM CT);
Dialyzer clean; CI green.

#### M3b — Server→client features (sampling, roots, elicitation)
*Ledger: `milestones/M3b-server-to-client-features-ledger.md`. Depends on M3a.*

- **Bidirectional requests:** the server session can *initiate* a request to its
  bound client (via the `erlmcp_ctx` peer handle, M1-8) and correlate the response;
  the client session dispatches *inbound* requests to registered callbacks.
- **Sampling** end-to-end: server-initiated `sampling/createMessage` → client
  `erlmcp_sampling` callback → result back to the server worker (not just client-side
  dispatch).
- **Roots:** inbound `roots/list` → `erlmcp_roots` callback; client emits
  `notifications/roots/list_changed`.
- **Elicitation:** inbound `elicitation/create` → `erlmcp_elicitation` callback
  (accept/decline/cancel).
- **Client capability advertisement:** the client declares `sampling`/`roots`/
  `elicitation` at `initialize` only when a handler is registered (mirror of M2a-12,
  client side). Inbound requests validated at the client boundary (validate-at-edge).

Closes: A (roots, elicitation, full sampling); C (client/server symmetry). DoD:
client and server in separate nodes complete a sampling + elicitation round-trip;
conformance client score ≥ rmcp's reference (harness's client scenarios land here;
the formal scorecard is M5).

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
- **Unify the transport↔session contract.** Today the transports diverge: the
  session consumes `gen_statem:cast(Session, {transport_data, Data})`, but `stdio`
  raw-sends `Session ! {transport_data, _}` and `http` sends `Owner ! {transport_message, _}`
  (different tag). M4 standardizes one inbound contract (one tag, one delivery
  mechanism) so the session is genuinely transport-agnostic, and one outbound path
  via the behaviour `send/2`.
- **Coverage re-homed here (from the M2b close):** the registry and supervision tree
  — `erlmcp_registry` (discovery-only, M1-13) and the supervisors (`erlmcp_app`,
  `erlmcp_sup`, `erlmcp_server_sup`, `erlmcp_session_sup`, `erlmcp_transport_sup`) —
  leave `cover_excl_mods` with tests, since M4 is where the supervised system runs
  end to end over real transports. After M4 only the M6 task modules remain excluded.

Closes: C (transport behaviour fully realized). DoD: the same example server runs
unchanged over stdio, TCP, and streamable HTTP; transport conformance scenarios pass.

### M5 — Quality infrastructure · **P0 for credibility**
*Goal: the artifact that earns "same quality as rmcp."*

**Split into M5a + M5b** (2026-05-23): the original single M5 spanned the
verification artifact (scorecard, test pyramid, specs, coverage) **and** a full docs
rewrite + release automation — ~17 rows across two very different work modes
(code/tests vs prose/CI-config), too large for the 5-iteration cap (same reasoning as
the M2/M3 splits). The seam is character: M5a is the *quality artifact*; M5b is *docs
& release discipline*. M5b depends on M5a (docs describe the scorecard-validated core).

#### M5a — Conformance scorecard, test pyramid, specs & coverage
*Ledger: `milestones/M5a-conformance-pyramid-coverage-ledger.md`. Depends on M1–M4.*

- **`erlmcp_conformance`:** the harness (grown through M2b/M3b/M4) emits a **dated,
  versioned scorecard** (server + client + transport) mirroring rmcp's
  `conformance/results/*`, committed as a published artifact. Protocol-native
  discoverability surfaces (`instructions`, tool `_meta`, `annotations`, resources)
  are scored like any other capability; the **directory tool is excluded** (DISC-6,
  `m2-discoverability-design.md` §7).
- Full test pyramid: EUnit (units, 1–2 asserts), Common Test (lifecycle/transport/
  e2e), **PropEr** (envelope + state-machine fuzzing).
- `-spec`/`-type` on **all** exports; Dialyzer + xref clean in CI.
- **Coverage ratchet to 95%** over implemented modules (the M0 plan's 90%→95% endpoint);
  M4's sub-90 coverage amendments (`stdio`, `server_sup`, `sup`) are resolved to the
  floor or formally accepted with line-level rationale; only the M6 task modules
  (`erlmcp_task`, `erlmcp_task_sup`) remain excluded.

DoD: scorecard published and ≥ rmcp's reference across L0–L4; CI runs
EUnit+CT+PropEr+Dialyzer+coverage green at the raised gate.

#### M5b — Docs rewrite & release/security automation
*Ledger: `milestones/M5b-docs-release-ledger.md`. Depends on M5a.*

- **Docs rewrite to match the code:** `architecture.md`, `protocol.md`,
  `otp-patterns.md`, `api-reference.md` (all currently 0.5-era), an accurate README,
  and the finished `MIGRATION-0.5-to-0.6.md`. All examples on the new core.
- **Docs verified against code:** no doc references a removed module/function; API
  reference matches actual exports.
- Release/security automation: SemVer + a maintained CHANGELOG; CodeQL/dependabot
  equivalents.

Closes: D (conformance harness, test strategy, stale docs, release discipline);
B (specs/coverage). DoD: docs verified against code; release/security automation live.

### M6 — Native-strength features · **P1/P2**
*Goal: the places erlmcp can exceed rmcp (Phase 2 §12).*

**Split into M6a + M6b** (2026-05-23): M6 bundles the meaty Tasks feature (a new
supervised, long-lived process lifecycle distinct from M1's ephemeral worker) with
three small protocol-completeness loose ends — ~16–17 rows, the same split territory
as M2/M3/M5. The seam: M6a is the Tasks feature; M6b is the 0.6.0 finish line
(`_meta`/icons/batch + the final empty `cover_excl_mods`). M6b depends on M6a.

#### M6a — Tasks (supervised long-running execution)
*Ledger: `milestones/M6a-tasks-ledger.md`. Depends on M1 (worker/ctx/cancellation) +
M2a (`add_tool` map, `tools/call`).*

- **Supervised task processes:** `erlmcp_task` (a long-lived `gen_server` holding task
  lifecycle state — running/completed/failed/cancelled, progress, result — distinct
  from the ephemeral per-request worker) under `erlmcp_task_sup` (`simple_one_for_one`).
- **Per-tool task support:** `taskSupport` (`forbidden`/`optional`/`required`,
  protocol-native `ToolExecution.taskSupport`) on the `add_tool` map, surfaced in
  `tools/list`; a `tasks` capability advertised when a task-supporting tool exists.
- **Task surface:** `tools/call` task-augmented execution spawns a supervised task and
  returns a task id; `tasks/get` (status+progress), `tasks/list`, `tasks/result`,
  `tasks/cancel` (cancellation-as-exit: terminate mid-flight, no late result). Progress
  via `notifications/progress` (reuses M1-8).

DoD: a long-running tool reports via tasks and can be cancelled mid-flight; conformance
covers tasks; the task modules leave `cover_excl_mods`.

#### M6b — `_meta`, icons, batch & the 0.6.0 finish line
*Ledger: `milestones/M6b-meta-icons-batch-finish-ledger.md`. Depends on M6a.*

- **`_meta` channel end-to-end:** request `_meta` carried through `erlmcp_ctx` to the
  handler and usable on the response (beyond the discoverability `_meta` of M2a).
- **Icons:** `Tool.icons` settable on the `add_tool` map + surfaced in `tools/list`.
- **Graceful batch tolerance:** session-level JSON-RPC batch *execution* (closes the
  M1-2 deferral — M1-2 landed batch parse/classify; M6b dispatches batches via the
  worker model and aggregates responses, degrading gracefully on malformed members).
- **Coverage endpoint:** `cover_excl_mods` is empty (the last two modules left in M6a);
  the gate holds over the whole codebase with stdio's io-loop the sole named exception.

Closes: A (tasks, `_meta`, batch). DoD: `_meta`/icons/batch land; conformance updated;
`cover_excl_mods` empty; full pipeline green — 0.6.0 release-ready.

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
| JSON library choice (`jsx` vs `jsone`/`thoas`) | **Resolved (2026-05-20):** keep `jsx` behind `erlmcp_codec`; reversible by design. |
| Streamable-HTTP transport complexity (sessions, resumability) | Largest transport lift; may slip within M4 — keep stdio/TCP as the guaranteed set. |
| Conformance reference: what do we measure against? | Use the MCP spec + rmcp's published scenarios as the bar; consider interop tests against rmcp itself. |
| Minimum OTP version | **Resolved (2026-05-20):** OTP 25+. Trade-off: no `-doc`/EEP-48 attributes (OTP 27); docs use edoc/ex_doc. gen_statem + maps unaffected. |
| Owner's erlmcp SKILL.md | **Resolved (2026-05-21):** live at `priv/ai/erlang/` (`SKILL.md` + `guides/`); now the operative house-style reference for all milestones. Convention-dependent calls Phase 2 flagged should be revisited against the skill. |

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
