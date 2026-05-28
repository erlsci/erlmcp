# Phase 6 — Discoverability Plan

**Date:** 2026-05-27
**Source:** CD's consumer-side assessment
(`workbench/erlmcp-discoverability-assessment.md`) + CDC server-side verification.
**Goal:** "README + SKILL.md on first response" — a consuming LLM knows how to use
the server, and where to go for more, from first contact.

---

## 0. Reconciliation — what CD saw vs what's actually wired

CD assessed black-box (as a consuming LLM) and flagged one thing only the server
side can answer: *does erlmcp populate `InitializeResult.instructions`?* Verified:

- **`instructions` IS populated.** `erlmcp_server_session` builds it on `initialize`
  (`Instructions = erlmcp_instructions:generate(maps:values(Tools))`, emitted as
  `<<"instructions">>` in the result). So the spec-blessed slot CD called "the
  single highest-leverage change" is **already filled** — the work is *content*,
  not wiring.
- **…but it's thin.** The generator emits, verbatim: *"This server provides tools
  organized by category. Categories: arithmetic, demo. Start with: add. Use
  tools/list for the full catalog."* No server identity, no protocol-feature
  warnings, no pointer to `directory` (it points to `tools/list`), no workflow hints.
- **Per-tool richness exists but isn't first-contact.** The examples already carry
  `category` / `when_to_use` / `next` / `entry_point` (e.g. `explain`'s
  `when_to_use` literally says "exercises server-to-client sampling"). That detail
  reaches the client only via the `directory` tool / `_meta`, not the tool
  *descriptions* the client surfaces first.

**So the real shape of the work is ENRICH + SURFACE, not WIRE.** CD's verdict (80%
there; the artifact exists but isn't *first*) holds, refined: the handshake slot is
already there but under-filled, and the rich metadata exists but lives one tool-call
deep.

---

## 1. Gating question — do this first (CD owns it)

**Does Claude Desktop actually surface `InitializeResult.instructions` to the
model?** Neither CD (couldn't tell if empty or just not shown) nor CDC (can't see
the client) can answer this from where we sit. It **gates the investment split**:

- If **yes** → enriching `instructions` is the top lever (handshake-time,
  client-agnostic, every consumer sees it).
- If **no** → leverage shifts to the always-visible surfaces: tool **descriptions**
  and the `directory` tool. We still enrich `instructions` (other clients honor it),
  but we lean harder on descriptions.

This is a 5-minute check for CD: connect, ask the model what the server's
instructions say, or inspect whether the populated string influences behavior.
Everything below is worth doing regardless; this just sets the *order*.

---

## 2. Prioritized actions

In leverage order, tagged by where the work lives (**core** = erlmcp library,
**example** = the demo servers, **docs** = READMEs/howto).

**A. Enrich `instructions` generation — README-grade. [core]**
Upgrade `erlmcp_instructions:generate/_` to produce a SKILL.md-grade string:
server **identity** (name, purpose, version, source URL), category overview,
entry points, **protocol features exercised** (sampling / tasks / progress), and an
explicit **"call `directory` for the oriented tool map with workflow hints."**
Two inputs it lacks today: (1) server identity — pass `server_info` + an optional
`purpose`/`source` from config into generation; (2) protocol-feature flags — from
the new per-tool field in **C**. Allow an **author-supplied override** (a server
may hand in its own README string) with the enriched auto-generation as the default.

**B. Add a server-level block to `directory`'s output. [core]**
Today `directory` answers "what tools," not "what *is* this server." Add a
top-level block: name, purpose, version, source URL, protocol features, docs
pointer. (`server_info` is already in session state; identity/source come from
config.) This makes the second-contact surface a true README.

**C. Add a per-tool `protocol_features` field + make it first-class. [core + example]**
Promote the buried "(exercises … sampling)" note from inside `when_to_use` prose to
a structured, prominent field, e.g. `protocol_features => [sampling]` /
`[tasks, progress]`. Feeds both **A** (instructions) and **B** (directory), and
warns a consuming LLM that `explain`/`slow_compute` aren't ordinary one-shot tools
*before* it calls them blind.

**D. Tighten `directory`'s self-description + seed orientation in first-contact
descriptions. [core + example]**
Make `directory`'s own description unmissable: *"Start here — an oriented overview
of this server, with workflow hints and which tools use advanced protocol
features."* And, as the robust client-agnostic fallback (some clients only surface
descriptions), put a one-line orientation in the entry-point tool's description
("Call `directory` first for an oriented overview") and a protocol-feature note in
`explain`/`slow_compute`'s descriptions.

**E. Document the three-server relationship. [docs]**
CD couldn't tell whether `simple` is a subset, a minimal reference, etc. The example
READMEs should state the intent plainly: `simple` = minimal reference; `calculator`
= tasks + sampling + discoverability demo; `weather` = resources + prompts +
completion demo. One sentence each, plus a top-level note tying them together.

---

## 3. Where it slots in the milestone plan

- **Now (CD):** the §1 gating check. Plus a free quick win — even the *current* thin
  instructions say "Use tools/list" instead of "call `directory`"; flipping that one
  pointer is a one-line, high-value change.
- **Core machinery (A, B, C-core, D-core):** the new **P6-M3 — Discoverability
  enhancement** (decision 2026-05-27; the rest of Phase 6 renumbered up by one to
  accommodate). Library work and a prerequisite for the examples to demonstrate it,
  so it lands before HTTP/validation/examples.
- **Example content (C-example, D-example, E):** **P6-M6** (examples rehabilitation)
  — the examples supply identity/purpose/source values, the `protocol_features`
  flags, the orientation descriptions, and the READMEs.
- **Teach it:** **P6-M7** (the `creating-an-mcp-server.md` howto) — a "make your
  server discoverable" section: populate `instructions`, the `directory` tool,
  per-tool `when_to_use`/`next`/`protocol_features`, server identity.

---

## 4. Explicitly NOT a discoverability issue

The `°` → `` the assessment's appendix noted is **not** a bug: `weather_server.erl`
uses `"°C"/utf8` (valid UTF-8 on the wire) and the codec's outbound UTF-8 guard
would fail-closed on a bad byte. It was a downstream display/transcription artifact.
No action — except the round-trip test may assert the exact `0xC2 0xB0` bytes for
certainty (already noted in the P6-M2 ledger).

---

## 5. The one-line summary

The discoverability *artifact* (`directory`) and the *slot* (`instructions`) both
already exist — the gap is that the slot is under-filled and the rich metadata lives
one tool-call deep. Fill the handshake with README-grade content (identity +
protocol features + "call `directory`"), promote protocol-feature warnings to a
first-class field, and make the always-visible surfaces (descriptions, `directory`'s
own description) point inward. Verify the client surfaces `instructions` first, to
set the order.
