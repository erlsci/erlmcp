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
need is protocol-native. Verified against the in-repo schema copy
`planning/schema.ts` (line numbers below refer to that file):

- **`InitializeResult.instructions?: string`** (interface at line 281, field at
  294). Free-form server guidance returned on the first call, which clients MAY
  inject into the system prompt. This is the protocol-native home for the
  "SKILL.md on first contact."
- **`Tool extends BaseMetadata, Icons`** (line 1251) — so every tool carries
  `name` + `title` (BaseMetadata, line 530) and `icons` (Icons, line 510) as
  standard fields.
- **`Tool._meta?: { [key: string]: unknown }`** (line 1298). The sanctioned,
  in-envelope extension point. Rides `tools/list`; clients that don't read it
  see a normal tool. This is the home for navigational metadata.
- **`ToolAnnotations`** (lines 1182–1224): `readOnlyHint`, `destructiveHint`,
  `idempotentHint`, `openWorldHint`, `title`. The protocol-native home for
  *behavioral* hints. (Spec warning, line 1177: clients must not make tool-use
  decisions based on annotations from untrusted servers — these are hints, not
  security boundaries. The same caveat applies to our `_meta` hints.)
- **`ToolExecution.taskSupport?: "forbidden" | "optional" | "required"`**
  (interface at 1231, field at 1243). Task-augmented execution is first-class in
  the tool definition — i.e. *discoverability of execution semantics* is
  protocol-native. Relevant to M6.

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
  wayfinding vocabulary (§4) under the project's reverse-DNS `_meta` prefix
  (`io.erlmcp/`, §8), travelling with the standard list call every client makes.
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

## 8. The `_meta` key-naming grammar (verified)

Verified 2026-05-20 against the spec prose
(`specification/2025-11-25/basic` → "General fields → `_meta`"). A key has an
optional **prefix** plus a **name**:

- **Prefix** (if present): a series of labels separated by dots (`.`), followed
  by a slash (`/`). Each label starts with a letter and ends with a letter or
  digit; interior characters may be letters, digits, or hyphens. Reverse-DNS
  notation is RECOMMENDED (`com.example/`, not `example.com/`).
- **Reserved:** any prefix whose **second label** is `modelcontextprotocol` or
  `mcp` is reserved for MCP (`io.modelcontextprotocol/`, `dev.mcp/`,
  `org.modelcontextprotocol.api/`, `com.mcp.tools/`). Note `com.example.mcp/` is
  *not* reserved — the second label is `example`.
- **Name:** unless empty, begins and ends with `[a-z0-9A-Z]`; may contain `-`,
  `_`, `.` in between.

**Decision:** namespace our wayfinding keys under the project's reverse-DNS
prefix `io.erlmcp/` — i.e. `io.erlmcp/when_to_use`, `io.erlmcp/next`,
`io.erlmcp/category`, `io.erlmcp/returns`, `io.erlmcp/summary`. This is
well-formed (reverse-DNS) and *not* reserved (second label `erlmcp`). The only
remaining choice is the domain itself: `io.erlmcp/` assumes the project claims
`erlmcp.io`; if you'd rather anchor to the GitHub org, `io.github.erlsci/` is
the reverse-DNS of `erlsci.github.io`. Either is spec-valid; pick the one whose
domain you actually control.

(Earlier draft suggested `erlmcp.io/…`; that was forward DNS and is corrected
here to the reverse-DNS form the spec recommends.)

---

## 9. Ledger (folds into M2)

The acceptance criteria for this design — **DISC-1 … DISC-9** — live as the
canonical, operational ledger (the place where `Status`/`Evidence` are updated
during implementation, in `LEDGER_DISCIPLINE.md` column format) at:

> `../milestones/M2a-tools-ergonomics-discoverability-ledger.md`

They are kept there rather than duplicated here so the two can't drift — the same
single-source-of-truth discipline this design applies to tool metadata (§3). This
section is the *design rationale*; the ledger is the *verifiable contract*. In
brief, the rows cover: 100% tool metadata coverage (DISC-1); a dangling-free
(DISC-2) and orphan-free (DISC-3) `next` graph; all surfaces derived from one
registration map (DISC-4, the `serious` invariant); namespaced `_meta` keys
(DISC-5); the directory tool's coverage and conformance exclusion (DISC-6);
behavioral hints kept in `annotations` (DISC-7); non-enumerating, drift-proof
`instructions` (DISC-8); and runtime-change consistency (DISC-9).
