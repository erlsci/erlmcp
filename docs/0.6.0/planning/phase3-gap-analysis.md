# Phase 3 — Gap analysis: ideal erlmcp vs. erlmcp 0.5.0

Measures the **actual** 0.5.0 codebase (from `phase1b-erlmcp-inventory.md`) against
the **ideal** design (`phase2-idiomatic-erlmcp.md`), with rmcp (`phase1-rmcp-audit.md`)
as the coverage reference. Every delta is classified into one of four buckets and
given a priority (P0 = foundational/blocking, P1 = needed for a credible 0.6.0,
P2 = polish / can trail).

---

## 1. Capability matrix (Phase 0 §3, filled in)

Legend: ✓ full · ◑ partial · ✗ absent. Cells are (client / server) where the
feature is directional; single mark where it applies to one role.

| Layer / Feature | rmcp | erlmcp 0.5.0 | ideal 0.6 |
|---|---|---|---|
| L0 JSON-RPC envelope | ✓ | ◑ encode/decode ok, id-correlation weak | ✓ |
| L0 standard error codes | ✓ | ◑ partial set | ✓ |
| L0 batching (parse gracefully) | ✓ | ✗ | ◑ parse, don't choke |
| L1 initialize + capability negotiation | ✓ | ✓ | ✓ |
| L1 protocol-version negotiation | ✓ multi-version | ✗ | ✓ |
| L1 ping | ✓ | ✗ | ✓ |
| L2 tools — list/call | ✓ | ✓ | ✓ |
| L2 tools — output schema / structured content | ✓ | ✗ | ✓ |
| L2 tools — input schema **validation** | ✓ | ✗ (jesse unused) | ✓ |
| L2 resources — list/read | ✓ | ✓ | ✓ |
| L2 resources — templates | ✓ | ◑ server only | ✓ |
| L2 resources — subscribe/updated | ✓ | ◑ on the *unsupervised* server | ✓ |
| L2 prompts | ✓ | ◑ reduced in supervised fork | ✓ |
| L2 completion | ✓ | ✗ | ✓ |
| L2 logging (setLevel + message) | ✓ | ◑ advertised, no methods | ✓ |
| L3 roots | ✓ | ✗ | ✓ |
| L3 sampling | ✓ | ◑ client dispatch only | ✓ |
| L3 elicitation | ✓ | ✗ | ✓ |
| L4 progress | ✓ | ◑ server `report_progress` only | ✓ |
| L4 cancellation | ✓ | ✗ | ✓ |
| L4 pagination (cursors) | ✓ | ✗ | ✓ |
| L4 tasks (long-running) | ✓ | ✗ | ✓ |
| L4 `_meta` channel | ✓ | ✗ | ✓ |
| **Spec version targeted** | 2025-11-25 | unversioned / implicit-old | 2025-11-25 |

Rough score: rmcp ≈ full across both roles; **erlmcp 0.5.0 covers ~7 of 20+
capabilities fully, with several of those living on code paths that aren't even
the supervised ones.**

---

## 2. Bucket A — Missing features

Capabilities the spec defines that 0.5.0 simply does not implement.

| Gap | Priority | Notes |
|---|---|---|
| **Cancellation** (`notifications/cancelled`) | **P0** | In the ideal design this is "kill the request worker" — cheap to add *once the per-request-process model exists*, near-impossible to bolt onto the current monolithic server. Drives the architecture. |
| **ping** | **P0** | Trivial, but it's a lifecycle basic clients expect. |
| **Protocol-version negotiation** | **P0** | Without it, 0.6.0 can't honestly claim 2025-11-25 support or interop with older clients. |
| **Input/output schema validation** | **P0** | `jesse` is already a declared dep but never called; "JSON Schema validation" is advertised in the README but not real. Correctness axis. |
| **Pagination** (cursor/nextCursor) | P1 | Needed for any server with large tool/resource lists; clients page by default. |
| **Completion** (`completion/complete`) | P1 | Argument autocompletion for prompts/resources. |
| **Roots** (client→server roots, server `roots/list`) | P1 | Half of the client side is currently absent. |
| **Elicitation** | P1 | Server-asks-user; increasingly used by real tools. |
| **Logging methods** (`logging/setLevel` + `notifications/message`) | P1 | Currently advertised but unimplemented — worse than not advertising. |
| **Structured content / output schema** | P1 | Modern tools return typed results, not just text. |
| **Tasks** (long-running) | P2 | A natural Erlang win (supervised processes) but not table-stakes for 0.6.0. |
| **Sampling — full** (server→client round-trip, not just client dispatch) | P1 | 0.5.0 only dispatches; the server-initiated request path is missing. |
| **Graceful batch parsing** | P2 | De-emphasized in the spec; parse without crashing is enough. |

---

## 3. Bucket B — Non-idiomatic implementation

Things that exist but are built in ways the house style (Inaka) rejects, so they'd
be reworked even where the feature is "present."

| Issue | Priority | House-style rule violated |
|---|---|---|
| God-module servers (`erlmcp_server` does dispatch + state + features + transport glue) | **P0** | "No God modules"; "smaller modules/functions" |
| Likely shared records / records crossing module boundaries for wire types | P1 | "Don't share your records"; "no records in specs"; "no types in include files" — needs the opaque-type model layer |
| `--min_coverage=0` and EUnit-only testing | P1 | "Simple unit tests" + reference texts on CT/PropEr; the gate is currently meaningless |
| Boolean/positional flags in places (e.g. `strict_mode => bool`) | P2 | "Avoid boolean parameters" — prefer tagged atoms |
| Direct `jsx:` calls scattered vs. a codec boundary | P2 | DRY / encapsulation; blocks swapping the JSON lib |
| Spec coverage of `-spec`/`-type` on exports unknown/incomplete | P1 | "Write function specs"; Dialyzer is our stand-in for Rust's type checking |

---

## 4. Bucket C — Architectural divergences (from the ideal)

Structural decisions that differ from the Phase 2 design and need realignment.

| Divergence | Priority | Detail |
|---|---|---|
| **No per-request process model** | **P0** | The single biggest one. Without it there is no clean cancellation, no fault isolation, and head-of-line blocking on slow tools. Everything in §2 P0 leans on this. |
| **Session is not a `gen_statem`** | **P0** | Lifecycle/negotiation is a state machine; modeling it as ad-hoc `gen_server` state is why version negotiation/ping/lifecycle gaps are awkward to add. |
| **Registry on the message hot path** | P1 | Central `erlmcp_registry` routes every message — a SPOF/bottleneck. Demote to discovery/binding only. |
| **Transport behaviour is inconsistent / partly broken** | **P1** (was P0) | UPDATE 2026-05-20: the `erlmcp_transport_http:send/2` `gen_server:call(self(),...)` deadlock is **fixed** (Issue #4, commit 57e2f50) — http is now a pid-based gen_server that delivers responses directly to its `owner`, off the registry. Remaining work: stdio/tcp still implement the behaviour inconsistently; M4 standardizes them **to match http** (the new reference pattern), not the other way. |
| **Client/server asymmetry** | P1 | Server is (partially) built out; the client lacks roots/elicitation/full sampling handlers. The ideal design is symmetric via client callback behaviours. |

---

## 5. Bucket D — Quality-infrastructure gaps

The dimension where the distance from rmcp is largest.

| Gap | Priority | Detail |
|---|---|---|
| **No conformance harness** | **P0** | rmcp's standout artifact: a spec-driven harness with dated scorecards (server 87.5% / client 80%). erlmcp has nothing comparable. 0.6.0 should ship `erlmcp_conformance` + a scorecard. |
| **Dead/abandoned code: the `_new` forks** | **P0** | The *weaker* `erlmcp_server_new` is the supervised one; the fuller `erlmcp_server` is unsupervised but tested; three overlapping server impls coexist. Must collapse to one. |
| **Supervisor references nonexistent modules** | **P0** | `erlmcp_transport_sup` dispatches to `*_tcp_new` / `*_http_new` that don't exist — TCP/HTTP transports cannot actually start under supervision. |
| **Phantom registered process** | P1 | `app.src` lists `erlmcp_client_sup` in `registered` but no such process exists. |
| **No real test strategy** | P1 | EUnit-only despite CT/PropEr being configured; tests split across `test/` and `priv/test/` (the latter only under a `testlocal` profile); coverage gate at 0. |
| **Stale/incorrect docs** | P1 | `docs/architecture.md` describes a supervision tree (`erlmcp_client_sup`) that doesn't exist; no root README accuracy guarantee. Docs describe aspirations, not the code. |
| **No versioned release discipline tie-in** | P2 | rmcp uses release-plz + Keep-a-Changelog/SemVer + CodeQL/dependabot. erlmcp has CI but no comparable release/security automation. |

---

## 6. Headline read

The uncomfortable but useful summary:

1. **A meaningful share of 0.5.0's "working" features are on code paths that aren't
   wired into supervision** (the fuller server, subscriptions, progress). The
   library as *assembled* is weaker than the library as *written*.
2. **The missing P0 features (cancellation, ping, version negotiation, real
   validation) are not independent** — three of four are blocked behind the same
   two architectural changes (per-request processes + `gen_statem` session). That's
   good news for sequencing: a small number of foundational moves unlock most of
   the feature gaps.
3. **The widest gap from rmcp is not features, it's quality infrastructure** —
   conformance measurement, a single coherent server implementation, a real test
   strategy, and accurate docs. This is also the most reputationally important gap
   for "an SDK of the same quality."
4. Given the owner's choices (**full modernization, break freely**), the dead-code
   and architectural gaps argue for a **clean re-core** rather than incremental
   patching of `erlmcp_server`/`_new`. Phase 4 sequences exactly that.
