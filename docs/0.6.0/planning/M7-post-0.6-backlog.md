# M7 / post-0.6 backlog

**Status:** Not scheduled. **Nothing here blocks 0.6.0** — the 0.6.0 feature surface is
complete and verified (M0→M6b). This file consolidates the post-0.6 items so the
carry-forwards scattered across the milestone ledgers don't get lost. It is a
**backlog, not a spec** — ledgers + CC prompts get written per item when one is
scheduled (same discipline as M0–M6).

Provenance: the dev plan's M7 section
(`phase4-0.6.0-development-plan.md` → "M7 — Stretch / post-0.6") plus the
`Carry-forward to M7 / post-0.6` notes accumulated during implementation.

---

## Cluster A — net-new features (≈ 0.7 scope; demand-driven)

These are new capability, large and self-contained. Sequence after 0.6.0 ships, driven
by actual user need rather than completeness.

- **OAuth 2.1 client subsystem.** rmcp has it; large and self-contained. The dev plan
  explicitly says "sequence after 0.6.0 unless a user needs it." Likely its own
  milestone (or mini-project), not a row in a grab-bag.
- **Multi-node / distributed registry.** `erlmcp_registry` is currently single-node;
  a `pg`/`gproc`-backed distributed registry would let sessions/transports span nodes.
- **Telemetry / metrics hooks.** Observability instrumentation (e.g. `telemetry`
  events on session lifecycle, tool calls, task transitions).

## Cluster B — internal refinements (≈ 0.6.x polish; cheap, no new surface)

These improve the code we just shipped. Low-risk, high-maintainability-value; a natural
**0.6.x point release** rather than 0.7.

- **`erlmcp_server_session` god-module extraction.** ~1250 LOC handling the entire
  protocol surface (tools/resources/prompts/logging/completion/tasks/batch). Extract
  per-feature handler modules behind the FSM for maintainability. *Flagged since M2b,
  re-affirmed at M6b. The "no god module" house rule (M2a-14) is under pressure here.*
- **Concurrent batch dispatch.** `handle_batch/2` currently dispatches batch members
  **sequentially within the session process**. A worker-per-member dispatch (reusing
  the M1 per-request worker model) would scale for high-throughput batches and match
  the BEAM-native isolation story. *From M6b-3.*
- **`request_peer/3` peer-death fast-fail.** A server-side worker awaiting a client
  reply blocks up to the 30s timeout if the client peer dies mid-request; the
  `out_pending` entry lingers until then. A proactive client-death → flush-`out_pending`
  path would fail fast instead of waiting out the timeout. *From M3b-1.*

## Known / accepted (no action)

- **stdio `default_read/0`** — the single remaining uncovered line (the `io:get_line`
  blocking read). Genuinely unreachable in test without a real stdin; confined to 1
  line by the M5a DI refactor. Accepted exception, not a backlog item.

---

## Suggested sequencing (when the time comes)

1. **0.6.x polish point-release** — Cluster B (cheap, improves just-shipped code; no
   new protocol surface, so low conformance/coverage churn).
2. **0.7 feature work** — Cluster A, OAuth and/or distributed registry, prioritized by
   real user demand.

Each scheduled item gets a ledger (`docs/0.6.x|0.7/milestones/`) + a CC prompt, written
at scheduling time — not pre-specced here.
