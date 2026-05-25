# CC Prompt — erlmcp 0.6.0 examples: README, Claude Desktop config & maximal discoverability

> Imperative brief. **Phase 2 of examples work — run only after the rehabilitation
> (`examples-rehabilitation-cc-prompt.md`) has landed and is CDC-verified.** That phase
> got the examples onto the 0.6.0 core, into CI, and demonstrating the features. This
> phase makes them *exemplary*: a top-level README, a copy-pasteable Claude Desktop
> config per example, and **maximal discoverability** — the examples become the
> reference for the feature that motivated the whole discoverability design.

## Why this matters

The discoverability layer (M2a, `m2-discoverability-design.md`) exists because LLMs
flounder against servers that don't tell them what the tools are or how to chain them.
These examples are where we *prove it works*: an LLM connecting to an erlmcp example
must get a useful `instructions` overview on first contact, find every tool via
`tools/list` `_meta` + the directory tool, and chain them via the `next` graph. After
this phase, the examples are also the canonical "how to build a discoverable MCP server"
reference, and the input to live acceptance testing against Claude Desktop.

## Read first

- The rehabilitated `examples/` tree + its CI smoke tests (the Phase-1 output).
- `docs/0.6.0/planning/m2-discoverability-design.md` (the vocabulary + the DISC
  invariants) and `test/erlmcp_disc_tests.erl` (the invariant checks to mirror).
- `src/erlmcp.erl` — `add_tool/2` wayfinding keys (`category`, `when_to_use`, `returns`,
  `next`, `summary`, `entry_point`), `annotations`, `icons`, `make_directory_tool/0`;
  and `start_stdio_setup/2` (the stdio launch path Claude Desktop will use).

## Acceptance criteria (treat as a ledger; CDC verifies each)

- **ENH-1 — `examples/README.md`.** A new top-level index with **one section per
  example** (calculator, simple, weather, and any client/sampling/task demo). Each
  section: what it is, **what 0.6.0 features it demonstrates**, how to build + run, the
  Claude Desktop JSON config (ENH-2), and a short "what to expect" (a sample
  interaction / the discoverability surface it exposes). The main `README.md` links to it.
- **ENH-2 — Claude Desktop config per example.** In each section, a copy-pasteable
  `claude_desktop_config.json` `mcpServers` block for that example — the real
  `command` + `args` (+ `env` if needed) that boot the example's **stdio** server. The
  command **must actually work** when pasted into Claude Desktop. (If the launch is an
  escript / release script, ENH-4 provides it.)
- **ENH-3 — Maximal discoverability, per example.** Every tool in every example
  registers the **full** wayfinding set — `category`, `when_to_use`, `returns`, `next`,
  `summary` (under `io.erlmcp/`), plus `annotations` (`readOnlyHint`/… where apt) and
  `icons`. Set `entry_point => true` on the natural starting tools. Register the
  directory tool (`make_directory_tool/0`). The derived `instructions` must be
  genuinely useful (strategy + categories + entry points). **Per example**, the DISC
  invariants hold: 100% tool-metadata coverage (DISC-1), a **dangling-free** (DISC-2)
  and **orphan-free** (DISC-3) `next` graph. These examples are the reference
  implementation — make them the standard you'd point a user at.
- **ENH-4 — Runnable stdio launcher per example.** Each stdio example has a concrete,
  documented launch (escript or release/`bin` script) usable as the Claude Desktop
  `command`. No "run these five rebar commands first" — it must be a single invocation.
- **ENH-5 — CI + invariants stay green.** The Phase-1 smoke tests still pass; add a
  per-example discoverability check (reuse/parameterize the `erlmcp_disc_tests` pattern)
  asserting DISC-1/2/3 for each example's registry. CI fails if an example's
  discoverability regresses. `cover_excl_mods` stays `[]`; gates green.
- **ENH-6 — Docs aligned.** `examples/README.md` + each `examples/*/README.md` reflect
  the enhanced examples and the config blocks; no stale links.
- **ENH-7 — Server-initiated sampling/elicitation demo.** The rehab left
  sampling/roots/elicitation as CT-only, reasoning a standalone *client* demo is
  awkward. Correct — but against Claude Desktop **the client side is Claude Desktop
  itself**, so a *server* tool that **requests** sampling and/or elicitation from its
  connected client is natural and live-testable. Add at least one such tool to an
  example (e.g. a calculator tool that asks the client to sample an explanation, or a
  weather tool that elicits a missing parameter) via `erlmcp_ctx:request_peer/3`. It
  must be discoverable (full wayfinding per ENH-3) and documented in the README as
  "this exercises server→client sampling/elicitation when run under Claude Desktop."
  This is the live demonstration of the bidirectional symmetry — and a headline
  acceptance-test case.

## Working protocol

- **Branch:** `task/0.6.0-examples-enhance`, off `release/0.6.x` (after Phase-1 merges);
  PR into `release/0.6.x`.
- Commit per coherent group. Raise an amendment if a launcher (ENH-4) needs build
  tooling that doesn't exist (e.g. an escript escriptize target) rather than improvising.
- House style applies doubly — these are read by users and are now the discoverability
  reference. Clear, idiomatic, commented where it teaches.
- Closing report: per-criterion disposition (ENH-1…ENH-6); name uncertainty. Include the
  **exact Claude Desktop JSON config block for each example** in the closing report (we
  use it directly for acceptance testing).
- Iteration cap: 5. Subagents for lookup only.

## Out of scope

New `src/` features. The live acceptance testing against Claude Desktop (that's a joint
Duncan+CDC step, separate). Do not change `src/` discoverability behavior to suit an
example — if the example needs a wayfinding capability the API lacks, raise it.

## Done when

`examples/README.md` exists with a per-example section + working Claude Desktop config;
every example demonstrates maximal discoverability with DISC-1/2/3 holding per example
and CI-guarded; each stdio example has a single-invocation launcher; docs aligned; gates
green. The closing report lists each example's ready-to-paste config block. Submitted
for CDC sign-off — after which we do live acceptance testing against Claude Desktop.
