# Archived design docs — July 2025 (pre-modernization)

These four documents are **superseded historical design docs** from an earlier
planning effort (July 2025). They are kept for historical context and because parts
of their design were harvested into the current 0.6.0 modernization plan. **Do not
read them as a description of the current or intended architecture.**

## Why they're archived

They belong to a *different* 0.6.0 than the one now in progress. The July roadmap
mapped phases to versions like this:

| Phase | Version | Scope |
|---|---|---|
| 1 | 0.4.0 | Build `erlmcp_registry` + supervision tree |
| 2 | 0.5.0 | Decouple `erlmcp_server` from transport management |
| **3** | **0.6.0** | **Transport standardization** |
| 4–6 | 0.7–0.9 | Examples/docs, legacy removal, rename `*_new` modules |
| 7 | 1.0.0 | Release |

So back then **"0.6.0" meant "standardize the transport layer."** The current 0.6.0
is a **full modernization to bring erlmcp to parity-of-quality with the Rust MCP SDK
(rmcp)** across the whole protocol surface. The version→phase numbering in these
docs is obsolete and must not be carried forward.

That earlier effort **stalled partway through its Phase 3**, which is why the live
tree still contains the `*_new` module forks (they were intentional, build-beside-
the-old artifacts awaiting a later remove-and-rename phase that never happened).

## The documents

- `otp-architecture-redesign.md` — the supervision-tree redesign and the
  version→phase roadmap above. Foundational context for why `erlmcp_registry` and
  the `_new` modules exist.
- `transport-architecture-redesign.md` — earliest exploratory "thoughts" on a
  server+transports split; superseded by the `-for-v0.6.0` version below.
- `transport-architecture-redesign-for-v0.6.0.md` — the fuller transport plan.
- `phase3_implementation_plan.md` — detailed transport-standardization steps.

## What was harvested into the current plan

The current plan lives in `workbench/0.6.0-planning/`. From these docs it adopted
(see `phase5-prior-art-reconciliation.md` §5):

- the `erlmcp_transport` **behaviour interface** (init/send/close + optional
  `get_info`/`handle_transport_call` + the `transport_message()` type),
- the per-type **`validate_transport_config/1`** field sets,
- the per-transport + behaviour-conformance **test-suite layout**,
- the **`start_{stdio,tcp,http}_setup`** convenience functions.

## The one deliberate departure

These docs route **every message** through `erlmcp_registry`. The current design
keeps the registry for **binding/discovery only** and has sessions talk to their
transport **directly**, off the message hot path (rationale and the open decision are
in `phase5-prior-art-reconciliation.md` §4.1).
