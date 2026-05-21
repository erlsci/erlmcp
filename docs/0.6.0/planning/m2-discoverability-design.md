# erlmcp 0.6.0 — Tool Discoverability (M2 design)

**Status:** Accepted (design); folds into M2.
**Date:** 2026-05-20.
**Provenance:** Designed jointly (Duncan + Claude). Motivated by two observed
LLM failure modes against MCP servers — (a) the model doesn't find all the
tools, and (b) the model doesn't know how to use or chain them — and by a
concrete anti-pattern observed in a sibling Fabryk server (see §1).

---

## 1. The problem, and the lesson from the reference implementation

LLMs hitting an MCP server frequently flounder: they miss tools, or find them
but don't know when to call what. The Fabryk/ai-music-theory server addressed
this with a `DiscoverableRegistry` carrying per-tool metadata (`summary`,
`when_to_use`, `returns`, `next`, `category`) plus a generated `mt_directory`
tool.

The live `mt_directory` output revealed the trap: **32 of 51 tools fell into a
`"general"` category with an empty `use_when`.** The cause is architectural —
the metadata was authored in a *separate, parallel structure*
(`with_tool_meta(...)` chained after registration), so adding a tool did not
force adding its metadata, and nothing detected the divergence. In our own
terms (LEDGER_DISCIPLINE.md) this is textbook **partial adoption** and
**silent drop**.

The lesson carried into erlmcp is not "write more metadata." It is: **make
discoverability metadata a property of tool registration, derived into every
surface, and verify completeness as a ledgered invariant.**

## 2. Protocol grounding (verified against the 2025-11-25 schema)

Contrary to earlier advice that "this isn't in the protocol," most of what we
need is protocol-native. Verified against
`schema/2025-11-25/schema.ts`:

- **`InitializeResult.instructions?: string`** (schema line ~298). Free-form
  server guidance returned on the first call, which clients MAY inject into the
  system prompt. This is the protocol-native home for the "SKILL.md on first
  contact."
- **`Tool extends BaseMetadata, Icons`** (line ~1255) — so every tool carries
  `name` + `title` (BaseMetadata) and `icons` (Icons) as standard fields.
- **`Tool._meta?: { [key: string]: unknown }`** (line ~1302). The sanctioned,
  in-envelope extension point. Rides `tools/list`; clients that don't read it
  see a normal tool. This is the home for navigational metadata.
- **`ToolAnnotations`** (lines ~1186–1228): `readOnlyHint`, `destructiveHint`,
  `idempotentHint`, `openWorldHint`, `title`. The protocol-native home for
  *behavioral* hints. (Spec warning, line ~1181: clients must not make tool-use
  decisions based on annotations from untrusted servers — these are hints, not
  security boundaries. The same caveat applies to our `_meta` hints.)
- **`ToolExecution.taskSupport?: "forbidden" | "optional" | "required"`**
  (lines ~1235–1248). Task-augmented execution is first-class in the tool
  definition — i.e. *discoverability of execution semantics* is protocol-native.
  Relevant to M6.

What is **not** in the protocol: the structured *wayfinding* vocabulary —
`when_to_use`, `next`, `category` as machine-readable fields — and a single
"directory" call returning the catalog as structured data. That residue is the
only explicitly-supplemental part of this design.

## 3. Architecture: one source of truth, derived views

**The tool registration map (`erlmcp:add_tool/2`, M2's data-driven API) is the
single source of truth.** Discoverability metadata are optional keys on that
same map — never a parallel structure. Everything else is *derived*:

```
            registration map  (source of truth)
                    │
        ┌───────────┼───────────────┬────────────────────┐
        ▼           ▼               ▼                    ▼
  instructions  per-tool _meta   directory tool      annotations
  (Tier 0)      in tools/list    (structured cat.)   (behavioral)
  strategy +    (Tier 1,          (Tier 2,            readOnly/
  categories    protocol-native)  supplemental)       destructive/…
```

Because the three navigational surfaces are projections of one map, they
cannot drift from each other or from the actual tool set. This is the
structural fix for the music-theory failure: a tool with no metadata is a
registration with missing optional keys — greppable, lintable, and caught by
the ledger invariants in §9.

## 4. Metadata vocabulary

Registration-map keys (recommendation: keep Fabryk's names for cross-project
muscle memory, with one refinement):

| Key           | Meaning                                          | Carrier |
|---------------|--------------------------------------------------|---------|
| `summary`     | One-line "what it does." **Defaults to / derives from the protocol `description`** to avoid duplication. | `_meta`, directory |
| `when_to_use` | When the model should reach for this tool.       | `_meta`, directory |
| `returns`     | What the tool returns.                           | `_meta`, directory |
| `next`        | Tool name(s) a model typically calls afterward.  | `_meta`, directory |
| `category`    | Grouping key (e.g. `search`, `content`, `graph`).| `_meta`, directory |

Behavioral semantics (`readOnlyHint`, `destructiveHint`, `idempotentHint`,
`openWorldHint`) are **not** part of this vocabulary — they go in protocol
`annotations` (§2) and must not be duplicated in `_meta`.

## 5. The four surfaces — what goes where

- **`instructions` (Tier 0, protocol-native).** A derived overview: server
  purpose, a numbered query strategy, the category list, and the named entry
  points (e.g. "start with `semantic_search`; call the directory tool for the
  full catalog"). Auto-injected by compliant clients.
- **Per-tool `_meta` in `tools/list` (Tier 1, protocol-native).** The
  wayfinding vocabulary (§4) under a reserved `erlmcp` namespace (§8), travelling
  with the standard list call every client makes.
- **The directory tool (Tier 2, supplemental).** A generated tool returning the
  same metadata as one categorized, structured payload — for models that prefer
  one call over parsing `_meta` across a list. A convenience projection, not the
  source of truth. **Explicitly non-protocol** (see §7).
- **Resources (Tier 3, protocol-native).** Deep per-topic docs / conventions via
  `resources`. Not the home for must-see orientation, because clients do not
  reliably auto-fetch resources.

## 6. The static-vs-dynamic rule

`instructions` is fixed at `initialize`, but M2 introduces runtime
`notifications/tools/list_changed`. Therefore **`instructions` MUST describe
strategy, categories, and entry points only — never enumerate individual tools
by name** — so it cannot go stale when tools are added or removed at runtime.
The live inventory is always `tools/list` (and the directory tool), both of
which are derived and update automatically.

## 7. Conformance boundary

The protocol-native surfaces (`instructions`, `_meta`, `annotations`,
`resources`) are part of normal MCP and are exercised by the conformance
harness like any other capability. **The directory tool is an erlmcp extension
and MUST be excluded from the M5 conformance scorecard** and trivially
omittable for a purist who wants a spec-only server. Least surprise for library
users: discoverability uses protocol-native carriers wherever possible, and the
one extension is clearly labeled and optional.

## 8. Open verification item

The `_meta` **key-naming grammar** is defined in spec prose
(`specification/2025-11-25/basic/index#meta`), not in `schema.ts`. Recollection:
MCP reserves a `modelcontextprotocol.io/`-style prefix namespace and recommends
a `label/key` convention. We intend to namespace our keys under an `erlmcp`
label (e.g. `erlmcp.io/when_to_use` or similar). **Confirm the exact grammar
against that doc page before locking key names** (DISC-5). This is the one
assertion in this design sourced from memory rather than from the schema we
read.

---

## 9. Ledger (folds into M2)

These rows are scoped to discoverability within M2. They are written in the
`LEDGER_DISCIPLINE.md` column format and are ready to merge into the full M2
ledger when it is created. Each `Verify` is intended to be a test or grep that
**fails if the criterion is violated** (not merely one that compiles). All rows
start `open`.

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| DISC-1 | Every registered tool has non-empty `category` and `when_to_use` in its registration metadata. | EUnit `test_all_tools_have_metadata` iterates the registry and asserts both keys present + non-empty for every tool; fails listing any tool missing either. | correctness | This design §3; music-theory gap | open | | The direct countermeasure to the 32/51 "general"/empty failure. |
| DISC-2 | The `next` wayfinding graph has no dangling edges: every tool named in any `next` is a registered tool. | EUnit `test_next_graph_no_dangling_edges` collects all `next` targets and asserts each resolves to a registered tool name. | correctness | This design §3 | open | | |
| DISC-3 | No orphan tools: every tool is reachable in the `next` graph from at least one entry point named in `instructions`. | EUnit `test_all_tools_reachable_from_entrypoints` does graph reachability from the declared entry points; fails listing unreachable tools. | correctness | This design §3,§5 | open | | Catches tools that exist but have no wayfinding path to them. |
| DISC-4 | `instructions`, each tool's `_meta`, and the directory payload are all derived from the single registration map — no hand-maintained parallel metadata store. | EUnit `test_surfaces_share_source`: register a tool with known metadata, then assert the same values appear in `_meta` (via `tools/list`), in the directory payload, and that its category appears in `instructions`. | serious | This design §3 | open | | The architectural invariant that prevents the reference-impl failure mode. |
| DISC-5 | Wayfinding `_meta` keys use the reserved `erlmcp` namespace and conform to the MCP `_meta` key-naming grammar. | EUnit `test_meta_key_namespace` asserts every wayfinding `_meta` key matches the namespace pattern; grammar confirmed against `basic/index#meta`. | correctness | This design §8 | open | | Blocked on the §8 grammar confirmation; re-entry: once the prefix grammar is verified. |
| DISC-6 | A directory tool is registered, returns a categorized projection of all tools, and is excluded from the conformance scorecard. | EUnit `test_directory_covers_all_tools` (directory entry count == registry tool count, minus the directory tool itself) + `test_directory_excluded_from_conformance` asserts the conformance manifest omits it. | correctness | This design §5,§7 | open | | |
| DISC-7 | Behavioral hints live in protocol `annotations`, not duplicated in wayfinding `_meta`. | EUnit `test_no_behavioral_keys_in_meta` asserts wayfinding `_meta` contains none of `readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint`. | polish | This design §4 | open | | |
| DISC-8 | `instructions` describes strategy/categories/entry points only and does not enumerate individual tools by name. | EUnit `test_instructions_no_tool_enumeration`: register N tools, assert the `instructions` string does not contain per-tool names beyond declared entry points; remains byte-identical after a runtime add/remove. | correctness | This design §6 | open | | Prevents `instructions` going stale against `tools/list_changed`. |
| DISC-9 | Directory payload and per-tool `_meta` update automatically on runtime tool add/remove (consistent with `notifications/tools/list_changed`). | EUnit `test_runtime_change_reflected`: add a tool at runtime, assert it appears in the directory payload and `tools/list` `_meta`; remove it, assert it disappears. | correctness | This design §3,§6 | open | | |

### Significance legend
`serious` = architectural invariant whose violation reintroduces the failure
this design exists to prevent. `correctness` = a guarantee the feature claims.
`polish` = hygiene that does not by itself reintroduce the failure.
