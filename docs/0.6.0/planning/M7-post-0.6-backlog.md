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

## Cluster C — audit-deferred findings (pre-release code audit, 2026-05-24)

Source: `workbench/2026.05.24-audit-results-erlang.md`. CDC-reviewed; deferred to M7.

### Medium

- **F-02:** Blanket `catch _:_` in `erlmcp_codec:decode/1` — `src/erlmcp_codec.erl:20-21`. Catch `error:badarg` specifically, as `encode/1` does.
- **F-03:** `list_to_atom/1` in convenience setup — `src/erlmcp.erl:273,282,291`. Use a tuple transport ID or document as single-use-only.
- **F-05:** Server session god-module (1329 LOC) — `src/erlmcp_server_session.erl`. Extract `erlmcp_pagination`, `erlmcp_uri_template`, `erlmcp_instructions` at minimum.

### Low

- **F-06:** ~80 unused macros in `include/erlmcp.hrl:59-143`. Remove `?MCP_METHOD_*`, `?MCP_CAPABILITY_*`, `?MCP_FEATURE_*`, `?MCP_CONTENT_TYPE_*`, `?MCP_ROLE_*`, `?MCP_MIME_*`, `?MCP_INFO_*`, `?MCP_FIELD_*`, `?MCP_PARAM_*`.
- **F-07:** Dead `#mcp_capability{}`/`#mcp_server_capabilities{}` records in `src/erlmcp_registry.erl:8-14`. Align with the map-based capability model.
- **F-08:** Dead legacy stubs `start_stdio_server/0,1`, `stop_stdio_server/0` in `src/erlmcp_sup.erl:67-79`. Delete.
- **F-10:** Hardcoded 30s timeout in `src/erlmcp_ctx.erl:53`. Make configurable via context map.
- **F-12:** Double `length/1` in pagination — `src/erlmcp_server_session.erl:1303-1304`. Use `lists:split/2` or carry count.
- **F-13:** Left-side `++` in `group_by_category` — `src/erlmcp.erl:219`. Prepend and reverse.
- **F-14:** `?SERVER` macro alias for `?MODULE` — `src/erlmcp_sup.erl:11`. Replace with `?MODULE`.
- **F-15:** Single-`%` function-level comments in `src/erlmcp_registry.erl`. Change to `%%`.

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
