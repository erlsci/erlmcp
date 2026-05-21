# Milestone M2: Server feature surface

> Per-milestone verification ledger (see `../../../*/LEDGER_DISCIPLINE.md` / the
> project copy). CC works against this ledger; CDC verifies every disposition
> independently against the actual commit state. No milestone advances until the
> ledger is fully closed.

**Scope note.** M2 (per `../planning/phase4-0.6.0-development-plan.md`) covers
tools, the ergonomics layer, discoverability, resources, prompts, logging,
completion, pagination, and progress. **This ledger is currently seeded only
with the discoverability rows (DISC-*).** Rows for the other M2 sub-features are
added to this same table as each is specified — they are not omissions, they are
not-yet-written. Per LEDGER_DISCIPLINE §"Missing rows are ledger bugs," the row
set is expected to grow before M2 opens for closure; the count check applies once
the full set is enumerated.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| DISC-1 | Every registered tool has non-empty `category` and `when_to_use` in its registration metadata. | EUnit `test_all_tools_have_metadata` iterates the registry and asserts both keys present + non-empty for every tool; fails listing any tool missing either. | correctness | discoverability design §3; music-theory gap | open | | The direct countermeasure to the 32/51 "general"/empty failure. |
| DISC-2 | The `next` wayfinding graph has no dangling edges: every tool named in any `next` is a registered tool. | EUnit `test_next_graph_no_dangling_edges` collects all `next` targets and asserts each resolves to a registered tool name. | correctness | discoverability design §3 | open | | |
| DISC-3 | No orphan tools: every tool is reachable in the `next` graph from at least one entry point named in `instructions`. | EUnit `test_all_tools_reachable_from_entrypoints` does graph reachability from the declared entry points; fails listing unreachable tools. | correctness | discoverability design §3,§5 | open | | Catches tools that exist but have no wayfinding path to them. |
| DISC-4 | `instructions`, each tool's `_meta`, and the directory payload are all derived from the single registration map — no hand-maintained parallel metadata store. | EUnit `test_surfaces_share_source`: register a tool with known metadata, then assert the same values appear in `_meta` (via `tools/list`), in the directory payload, and that its category appears in `instructions`. | serious | discoverability design §3 | open | | The architectural invariant that prevents the reference-impl failure mode. |
| DISC-5 | Wayfinding `_meta` keys use the project reverse-DNS prefix `io.erlmcp/` and conform to the MCP `_meta` key-name grammar (prefix = dot-labels + `/`, second label ∉ {`modelcontextprotocol`,`mcp`}; name begins/ends alphanumeric). | EUnit `test_meta_key_namespace` asserts every wayfinding `_meta` key matches `^io\.erlmcp/[A-Za-z0-9][A-Za-z0-9._-]*$`. | correctness | discoverability design §8 | open | | Grammar verified 2026-05-20 against the 2025-11-25 `_meta` spec; no longer blocked. Final domain label (`io.erlmcp` vs `io.github.erlsci`) is Duncan's call (§8). |
| DISC-6 | A directory tool is registered, returns a categorized projection of all tools, and is excluded from the conformance scorecard. | EUnit `test_directory_covers_all_tools` (directory entry count == registry tool count, minus the directory tool itself) + `test_directory_excluded_from_conformance` asserts the conformance manifest omits it. | correctness | discoverability design §5,§7 | open | | |
| DISC-7 | Behavioral hints live in protocol `annotations`, not duplicated in wayfinding `_meta`. | EUnit `test_no_behavioral_keys_in_meta` asserts wayfinding `_meta` contains none of `readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint`. | polish | discoverability design §4 | open | | |
| DISC-8 | `instructions` describes strategy/categories/entry points only and does not enumerate individual tools by name. | EUnit `test_instructions_no_tool_enumeration`: register N tools, assert the `instructions` string does not contain per-tool names beyond declared entry points; remains byte-identical after a runtime add/remove. | correctness | discoverability design §6 | open | | Prevents `instructions` going stale against `tools/list_changed`. |
| DISC-9 | Directory payload and per-tool `_meta` update automatically on runtime tool add/remove (consistent with `notifications/tools/list_changed`). | EUnit `test_runtime_change_reflected`: add a tool at runtime, assert it appears in the directory payload and `tools/list` `_meta`; remove it, assert it disappears. | correctness | discoverability design §3,§6 | open | | |

### Significance legend
`serious` = architectural invariant whose violation reintroduces the failure the
discoverability design exists to prevent. `correctness` = a guarantee the feature
claims. `polish` = hygiene that does not by itself reintroduce the failure.

## What Worked

_(Filled in at milestone close. Patterns, practices, or decisions that made the
milestone close cleanly and should be preserved or generalised.)_

## Closure

_(Open. Filled at close.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: `<N>`. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
