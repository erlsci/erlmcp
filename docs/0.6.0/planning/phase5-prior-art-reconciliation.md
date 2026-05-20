# Phase 5 — Reconciliation with the July-2025 prior art

After today's audit/plan was written, four design docs from **July 2025** surfaced
in `docs/` (a previous planning effort by Duncan, Claude-assisted). They were not
consulted during Phases 0–4 (an oversight — the `docs/` listing was truncated and
the redesign docs were missed). This document reconciles them.

Docs reviewed:
- `docs/otp-architecture-redesign.md` (2025-07-19) — the supervision-tree redesign
- `docs/transport-architecture-redesign.md` (2025-07-19) — early "thoughts" on server+transports
- `docs/transport-architecture-redesign-for-v0.6.0.md` (2025-07-20) — fuller transport plan
- `docs/phase3_implementation_plan.md` (2025-07-20) — detailed transport-standardization steps

---

## 1. The single most important finding: "0.6.0" meant something different

The July effort defined a **version→phase roadmap** (in `otp-architecture-redesign.md`):

| Phase | Version | Scope |
|---|---|---|
| 1 | 0.4.0 | Build `erlmcp_registry` + supervision tree |
| 2 | 0.5.0 | Decouple `erlmcp_server` from transport management |
| **3** | **0.6.0** | **Transport standardization** (behaviour, registry integration) |
| 4 | 0.7.0 | Update examples/docs |
| 5 | 0.8.0 | Remove legacy (`erlmcp_stdio`, `erlmcp_stdio_server`, old `erlmcp_transport_stdio`) |
| 6 | 0.9.0 | Rename `*_new` modules → canonical names |
| 7 | 1.0.0 | Release |

So in the prior plan, **"0.6.0" = "standardize the transport layer"** — a narrow
OTP-plumbing milestone. Today's "0.6.0" = **full modernization to rmcp-quality
across the whole protocol surface**. These are not the same target. The prior
version numbering is now **obsolete** and should not be carried forward, or it will
collide with the new scope.

## 2. This explains the codebase mess (it's a stalled refactor, not just sloppiness)

The audit's "quality smells" are now legible as **a migration that stalled partway
through Phase 3**:

- The `*_new` modules (`erlmcp_transport_stdio_new`, `erlmcp_server_new`) were
  **intentional** — the plan deliberately built new modules beside the old, with
  Phase 5 (remove old) and Phase 6 (rename `_new` → canonical) scheduled later. The
  effort stopped before those phases, leaving the forks frozen in place.
- Worse, the implementation diverged even from its own plan: the live
  `erlmcp_transport_sup` dispatches to `erlmcp_transport_tcp_new` /
  `erlmcp_transport_http_new`, but the Phase 3 doc says to refactor
  `erlmcp_transport_tcp` / `_http` **in place** (no `_new`). So the supervisor
  points at modules that were planned-away *and* never created.
- `erlmcp_server_new` being the supervised-but-weaker server is the Phase-2
  "decoupled server" that hadn't yet reached feature parity when work stopped.

**Implication:** the codebase is frozen mid-migration. This *strengthens* the
"break freely / clean re-core" decision — there is no coherent in-progress state to
preserve.

## 3. Where the prior art AGREES with today's plan (validation)

The July docs independently reached several of the same conclusions, which is
reassuring:

- **One transport behaviour, many implementations.** Their proposed
  `erlmcp_transport` behaviour — `init/2`, `send/2`, `close/1`, optional
  `get_info/1` + `handle_transport_call/2`, with `-optional_callbacks` — is almost
  exactly today's Phase 2 §6 / Phase 4 M4. **This design is already done and is
  directly reusable.**
- **Map-based, validated transport config** with per-type `validate_transport_config/1`
  — matches today's M0/M2 validation goal, with concrete code already written.
- **Kill the duplicate `erlmcp_stdio_server`.** `transport-architecture-redesign.md`
  argues for a single protocol implementation behind pluggable transports — the
  same "collapse the three server impls" conclusion as Phase 3.
- **Transports as supervised gen_servers**, transport failures isolated from the
  server — consistent with today's supervision design.

## 4. Where the prior art DISAGREES with today's plan (decisions to make)

### 4.1 The registry: message bus vs. discovery-only — *the real disagreement*

The July design makes `erlmcp_registry` the **centerpiece**: *every* message is
routed through it (`route_to_server/3`, `route_to_transport/3`). Today's plan
(Phase 2 §4) deliberately **demotes** the registry to discovery/binding only and has
sessions talk to their transport directly, calling per-message routing through a
single gen_server a latent SPOF/bottleneck.

This is a genuine reversal of a deliberate prior decision, so it deserves an honest
treatment rather than a silent override:

- **What the prior design got right:** the *goals* — decoupling server lifecycle
  from transport lifecycle, supporting many-to-many server↔transport binding, and
  runtime rebinding. Those are good goals worth keeping.
- **What's questionable:** achieving them by routing *every message* through one
  gen_server. That serializes all traffic through a single process and makes it a
  single point of failure for liveness (throughput, head-of-line blocking,
  crash-blast-radius).
- **Proposed synthesis (not a wholesale rejection):** keep the registry for
  **binding and discovery** (exactly the decoupling the prior author wanted), but
  let an established session own its transport and exchange messages **directly**,
  off the registry hot path. This preserves the prior design's intent while removing
  its bottleneck.

**This is a decision point for Duncan**, not a settled matter — flagged explicitly.

### 4.2 gen_server vs gen_statem for the session

July models `erlmcp_server` as a plain `gen_server` handling requests inline in
`handle_info`. Today's plan uses a **`gen_statem`** session (lifecycle is a real
state machine: uninitialized→initializing→operational) **plus one process per
in-flight request**. The per-request-process model — which gives cancellation,
fault isolation, and no head-of-line blocking — is **absent from the prior art** and
is today's most important architectural addition.

### 4.3 Scope the prior art never covered

The July effort was entirely about supervision + transport plumbing. It says nothing
about MCP **feature coverage** (roots, sampling, elicitation, completion, pagination,
cancellation, tasks, structured content), **schema validation wiring**,
**protocol-version negotiation**, a **conformance harness**, or any **comparison to
rmcp**. Today's plan owns all of those. The two are complementary in scope, not
competing — the prior art is a deep cut on one layer the new plan treats more
briefly.

---

## 5. What to harvest into the new plan

Concrete, reusable assets from the prior art (mostly into Phase 4 **M4 — Transports**
and the M0 validation work):

1. The `erlmcp_transport` **behaviour interface** (callbacks + optional callbacks +
   the `transport_message()` type) — adopt nearly as-is.
2. The **standard transport gen_server skeleton** (`init/2` registering with the
   registry, `handle_info` send/receive pattern) — adapt to "register binding, then
   talk to the session directly."
3. **`validate_transport_config/1`** per-type validation — adopt for M0/M2.
4. The **transport test-suite layout** (`*_transport_*_SUITE.erl` per transport +
   a behaviour-conformance suite) — fold into M5's Common Test plan.
5. The **convenience setup functions** (`start_stdio_setup/2`, `start_tcp_setup/3`,
   `start_http_setup/3`) — good ergonomics to preserve in the facade.

## 6. Keep / remove recommendation

None of the four should remain in `docs/` **as current documentation** — they
describe a half-built architecture and an obsolete version→phase mapping that now
conflicts with the new 0.6.0 scope, and leaving them next to the (also stale)
`architecture.md` will mislead future readers and users. But they should **not be
deleted** — they hold the historical "why" behind the registry and `_new` modules,
plus reusable transport design.

| Doc | Recommendation | Rationale |
|---|---|---|
| `otp-architecture-redesign.md` | **Archive** (after harvesting supervision/transport bits) | Foundational context for why the registry + `_new` exist; phase/version map obsolete. |
| `phase3_implementation_plan.md` | **Harvest → archive** | Transport behaviour + validation + test layout are reusable; phase scope obsolete. |
| `transport-architecture-redesign-for-v0.6.0.md` | **Harvest → archive** | Fullest transport plan; overlaps phase3 heavily. |
| `transport-architecture-redesign.md` | **Archive (low value)** | Earliest exploratory "thoughts"; superseded by the `-for-v0.6.0` version and by today's Phase 2. |

**Proposed action:** move all four to `docs/archive/2025-07-pre-modernization/`
with a short `README.md` explaining they are superseded historical design docs
(what "0.6.0" meant then vs now, and what was harvested into the new plan). This
removes them from the live `docs/` root while preserving the history. The harvested
items (§5) get folded into `phase4-0.6.0-development-plan.md` M4.

Also flagged: `docs/architecture.md`, `docs/otp-patterns.md`, `docs/protocol.md`,
`docs/api-reference.md` (the 2025-06 "Claude-updated docs") are *also* stale relative
to current code (the audit found `architecture.md` describes a nonexistent
`erlmcp_client_sup` tree). Those are part of the M5 docs-rewrite, separate from this
archive decision.
