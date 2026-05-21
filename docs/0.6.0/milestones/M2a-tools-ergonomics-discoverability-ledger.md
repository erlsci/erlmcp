# Milestone M2a: Tools, ergonomics & discoverability

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the tool-server core on the new spine — the ergonomics layer (schema
builder, `add_tool/2`, `erlmcp_server_handler`), the full `tools/*` surface with
real input/output validation, and the discoverability layer (DISC-1…9). M2a is the
first half of the former M2; **M2b** covers resources, prompts, logging,
completion, and the conformance scorecard.

**Locked decisions (carried):** JSON = `jsx` behind `erlmcp_codec`; validator =
`jesse`, wired at the session boundary; OTP 25+; coverage 90% scoped (exclusion
list shrinks — M2a-15); validate at the edge, crash in the interior; no shared
records; no `_new` forks; no macros for logic.

**Branch:** `task/0.6.0-m2a`, cut from `release/0.6.x`; PR into `release/0.6.x`.
Depends on M1 (the session + per-request worker spine). All Verify commands run
from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M2a-1 | `erlmcp_schema` builder (`object`, `field`, enum/array, …) produces a JSON Schema map **and** a matching validator in one place. | EUnit `erlmcp_schema_tests`: a built schema validates conforming input and rejects non-conforming; emits a `jesse`-usable schema. | serious | dev plan M2a; Phase 2 §1a | open | | Functions over data; no hand-written JSON Schema maps. |
| M2a-2 | Data-driven `erlmcp:add_tool/2` accepts a map: `name`, `description`, `input_schema`, optional `output_schema`, `handler` (`fun/2` or `{M,F}`), optional wayfinding keys, optional `annotations`. | CT: `add_tool/2` registers a tool and `tools/call` reaches the handler. | serious | dev plan M2a; Phase 2 §1b | open | | This map is the single source of truth for the discoverability surfaces (DISC-4). |
| M2a-3 | `erlmcp_server_handler` behaviour: `tools/0` introspected once at registration to answer `tools/list`; `tools/call` routed to `handle_tool/3`; no `apply/3`. | `grep -c "^-callback" src/erlmcp_server_handler.erl` ≥ 2; CT with a handler module; `rebar3 xref` clean. | serious | dev plan M2a; Phase 2 §1c | open | | xref-checkable extension point, not dynamic dispatch. |
| M2a-4 | `tools/list` returns each tool with `inputSchema`, optional `outputSchema`, `annotations`, and wayfinding `_meta`; paginated (cursor/nextCursor). | CT: `tools/list` shape correct; a paginated list round-trips with an opaque cursor. | serious | dev plan M2a; Phase 2 §1 | open | | |
| M2a-5 | `tools/call` runs the handler in a per-request worker (the M1 spine) and returns its result. | CT: a registered tool call returns the expected result via a worker. | serious | dev plan M2a; Phase 2 §3 | open | | Reuses M1's worker model; no new concurrency machinery. |
| M2a-6 | Input args are validated against `input_schema` via `jesse` at the session boundary **before** dispatch; invalid args → `-32602` and the handler never runs. | CT: malformed args → `-32602`; handler not invoked. | serious | dev plan M2a; Phase 2 §2,§5; closes "jesse declared, never used" | open | | Turns advertised schema validation into a real guarantee. |
| M2a-7 | A tool declaring `output_schema` has its result validated and returned as `structuredContent`. | CT: structured output validated + returned; schema-violating output is caught. | correctness | dev plan M2a; Phase 2 §2 | open | | |
| M2a-8 | All five content types — text, image, audio, embedded resource, resource link — have constructors and emit correctly in tool results. | EUnit/CT: each content type round-trips through `erlmcp_model` + a `tools/call`. | correctness | dev plan M2a | open | | |
| M2a-9 | Tool `annotations` (`readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint`/`title`) are settable and surfaced in `tools/list`. | CT: a tool with annotations shows them in `tools/list`. | correctness | dev plan M2a; 2025-11-25 `ToolAnnotations` | open | | Behavioral hints live here, **not** in `_meta` (DISC-7). |
| M2a-10 | Runtime add/remove of a tool emits `notifications/tools/list_changed`. | CT: add → notification observed; remove → notification observed. | correctness | dev plan M2a | open | | |
| M2a-11 | A tool worker calling `erlmcp_ctx:report_progress/3` emits `notifications/progress` keyed by the request's `progressToken`. | CT: a long-running tool reports progress; client observes `notifications/progress`. | correctness | dev plan M2a; Phase 2 §3 (wires M1-8) | open | | |
| M2a-12 | The capability map advertised in `initialize` reflects what's registered (advertises `tools` + `listChanged` only when tools exist). | CT: capability map matches registrations. | correctness | dev plan M2a; Phase 2 §8 | open | | Derived, not hardcoded. |
| M2a-13 | A calculator-style example server on the new core exercises tools end to end: list, call, input validation, structured output, annotations, list_changed, progress, and the discoverability surfaces. | CT `erlmcp_example_calculator_SUITE` drives all of the above green. | serious | dev plan M2a DoD | open | | The non-trivial example required by the DoD (tools half). |
| M2a-14 | New public APIs follow house style: no boolean parameters (tagged atoms/tuples), opaque types at boundaries, no god module. | Review + grep: no boolean-flag params in new exported funs; reasonable module sizes; `-opaque`/accessors at boundaries. | polish | dev plan M2 (B-axis); Phase 2 §2; Erlang skill | open | | Cleanup "as these APIs are written," per dev plan. |
| M2a-15 | `erlmcp` (facade) and the new M2a modules are removed from `cover_excl_mods`; the gate holds ≥90% over them. | `cover_excl_mods` no longer lists `erlmcp` (or the M2a modules); CI `cover --min_coverage=90` passes including them. | serious | M1-16 pattern; coverage ratchet | open | | `erlmcp` was tagged "M2a" in the exclusion list. |
| M2a-16 | Dialyzer clean; CI green on `task/0.6.0-m2a`. | `rebar3 dialyzer` exit 0; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green on the branch. | serious | dev plan M2a DoD | open | | |
| DISC-1 | Every registered tool has non-empty `category` and `when_to_use` in its registration metadata. | EUnit `test_all_tools_have_metadata` iterates the registry and asserts both keys present + non-empty for every tool; fails listing any tool missing either. | correctness | discoverability design §3; music-theory gap | open | | The direct countermeasure to the 32/51 "general"/empty failure. |
| DISC-2 | The `next` wayfinding graph has no dangling edges: every tool named in any `next` is a registered tool. | EUnit `test_next_graph_no_dangling_edges` collects all `next` targets and asserts each resolves to a registered tool name. | correctness | discoverability design §3 | open | | |
| DISC-3 | No orphan tools: every tool is reachable in the `next` graph from at least one entry point named in `instructions`. | EUnit `test_all_tools_reachable_from_entrypoints` does graph reachability from the declared entry points; fails listing unreachable tools. | correctness | discoverability design §3,§5 | open | | Catches tools that exist but have no wayfinding path to them. |
| DISC-4 | `instructions`, each tool's `_meta`, and the directory payload are all derived from the single registration map — no hand-maintained parallel metadata store. | EUnit `test_surfaces_share_source`: register a tool with known metadata, then assert the same values appear in `_meta` (via `tools/list`), in the directory payload, and that its category appears in `instructions`. | serious | discoverability design §3 | open | | The architectural invariant that prevents the reference-impl failure mode. |
| DISC-5 | Wayfinding `_meta` keys use the project reverse-DNS prefix `io.erlmcp/` and conform to the MCP `_meta` key-name grammar (prefix = dot-labels + `/`, second label ∉ {`modelcontextprotocol`,`mcp`}; name begins/ends alphanumeric). | EUnit `test_meta_key_namespace` asserts every wayfinding `_meta` key matches `^io\.erlmcp/[A-Za-z0-9][A-Za-z0-9._-]*$`. | correctness | discoverability design §8 | open | | Grammar verified 2026-05-20 against the 2025-11-25 `_meta` spec. Final domain label (`io.erlmcp` vs `io.github.erlsci`) is Duncan's call (§8). |
| DISC-6 | A directory tool is registered, returns a categorized projection of all tools, and is excluded from the conformance scorecard. | EUnit `test_directory_covers_all_tools` (directory entry count == registry tool count, minus the directory tool itself) + `test_directory_excluded_from_conformance` asserts the conformance manifest omits it. | correctness | discoverability design §5,§7 | open | | |
| DISC-7 | Behavioral hints live in protocol `annotations`, not duplicated in wayfinding `_meta`. | EUnit `test_no_behavioral_keys_in_meta` asserts wayfinding `_meta` contains none of `readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint`. | polish | discoverability design §4 | open | | |
| DISC-8 | `instructions` describes strategy/categories/entry points only and does not enumerate individual tools by name. | EUnit `test_instructions_no_tool_enumeration`: register N tools, assert the `instructions` string does not contain per-tool names beyond declared entry points; remains byte-identical after a runtime add/remove. | correctness | discoverability design §6 | open | | Prevents `instructions` going stale against `tools/list_changed`. |
| DISC-9 | Directory payload and per-tool `_meta` update automatically on runtime tool add/remove (consistent with `notifications/tools/list_changed`). | EUnit `test_runtime_change_reflected`: add a tool at runtime, assert it appears in the directory payload and `tools/list` `_meta`; remove it, assert it disappears. | correctness | discoverability design §3,§6 | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
tool-server core or reintroduces the discoverability drift failure. `correctness`
= a guarantee the feature claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M2b+

_(Filled in at close — e.g. modules still in `cover_excl_mods`, shared patterns
M2b should reuse: pagination, `list_changed`, schema/validation.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 25. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
