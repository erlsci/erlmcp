# CC Prompt — erlmcp 0.6.0 examples rehabilitation + CI (release blocker)

> Imperative brief. **This is a pre-tag release blocker.** The runnable `examples/`
> tree still calls **deleted 0.5 modules** and won't compile against the current code,
> and **CI never builds it** (the example rebar profiles aren't in the pipeline). M5b-7
> ("all examples on the new core") was satisfied only for the `test/` example *suites*;
> the user-facing `examples/` tree was missed. Bring every example onto the 0.6.0 core,
> make the example set demonstrate the headline features, and **get examples into CI so
> a broken example fails the build.** Do not tag 0.6.0 until this is green.

## What's wrong (CDC findings)

- `examples/{calculator,simple,weather}/*.erl` reference removed modules:
  `erlmcp_client:*` (deleted M3a), `erlmcp_stdio_server`/`erlmcp_server:*` (deleted M1).
  They cannot compile on the current core.
- CI runs `eunit/ct/proper/cover` (default + `test` profiles). The examples live behind
  the `testlocal`/`simple`/`calculator`/`weather` profiles (`rebar.config` lines 51–120),
  which CI never builds — so the breakage is invisible.
- Those profiles are themselves stale: `erl_first_files` points at
  `examples/simple_server.erl` / `examples/simple_client.erl`, which **do not exist**
  (the real files are `examples/simple/simple_server_stdio.erl`, etc.).
- The per-example `README.md`s and any main-README links likely point at the stale code.

## Read first

- `examples/` (all of it: `calculator/`, `simple/`, `weather/` — servers, clients,
  demos, tests, READMEs).
- The **current** API surface they must use: `src/erlmcp.erl` (facade — `start_server`,
  `add_tool/2` map, content constructors, `start_stdio_setup/2`/`start_tcp_setup/3`/
  `start_http_setup/3`, resources/prompts/logging), `src/erlmcp_client_session.erl`
  (the client), and the `test/erlmcp_example_*_SUITE.erl` + `test/example_*_handler.erl`
  as the canonical new-core examples to mirror.
- `rebar.config` profiles (51–120) and `.github/workflows/ci.yml`.
- `priv/ai/erlang/SKILL.md` (house style; examples are read by users — they must be
  exemplary, not just compiling).

## Acceptance criteria (treat as a ledger; CDC verifies each)

- **EX-1 — Inventory & plan.** List every file under `examples/`, every example the docs/
  READMEs reference, and every example rebar profile. For each: rewrite / delete /
  consolidate. Record it (a short table at the top of the work).
- **EX-2 — Onto the new core.** Every retained `examples/` file uses only the current
  API. **Verify:** `grep -rn "erlmcp_server\b\|erlmcp_stdio_server\|erlmcp_client\b" examples/`
  → 0 matches (allowing `erlmcp_server_session`/`erlmcp_client_session`).
- **EX-3 — No divergent duplicates.** Reconcile the `test/` example handlers/suites vs.
  the `examples/` runnable demos: the `test/` suites stay the CT feature coverage; the
  `examples/` demos are the runnable user-facing copies. Don't maintain two divergent
  implementations of the same example — share handler modules or make the demos thin
  runnable wrappers. State the decision in EX-1.
- **EX-4 — Demonstrate the headline 0.6.0 features.** Across the example set, *runnably*
  showcase: tools + **discoverability** (`instructions` + the directory tool); resources
  + **templates** + **subscriptions**; prompts + **completion**; **tasks** (long-running
  + cancel mid-flight); **sampling/roots/elicitation** (client callbacks); **batch**;
  **`_meta`**; **icons**; and the example server running over **multiple transports**
  (stdio + tcp at minimum, http if cheap). Map features → examples; fill the gaps (the
  existing demos only cover basic tools/resources). Not every example needs everything,
  but the set as a whole must cover this list.
- **EX-5 — In CI, fully tested.** Examples **compile in CI** (a broken example fails the
  build) **and** each example server has a smoke CT (start → `initialize` → one real
  operation → stop). Fix the broken example profiles (the non-existent
  `erl_first_files`); wire the example build + smoke tests into `ci.yml` (either fold
  examples into the `test` profile's `src_dirs` so `rebar3 ct` covers them, or add
  explicit `rebar3 as <profile> compile` + a smoke suite — your call, but CI must fail
  if an example breaks).
- **EX-6 — Docs aligned.** The main README and each `examples/*/README.md` reference the
  rewritten examples and the new API; no doc links to deleted/stale example code.
  **Verify:** the EX-2 grep, applied to `examples/**/README.md` and `README.md`, is clean.
- **EX-7 — M5b-7 amendment.** Record in the M5b ledger that M5b-7's "all examples on the
  new core" was satisfied only for the `test/` suites; this task extends it to the
  runnable `examples/` tree + CI. (Amendment, not a silent edit.)
- **EX-8 — Gates green.** `rebar3 compile` (zero warnings), `xref`, `eunit`, `ct`
  (incl. the new example smoke suites), `proper`, `dialyzer`, `cover` (still ≥90% per
  module, `cover_excl_mods` `[]`); CI green on the branch.

## Working protocol

- **Branch:** `task/0.6.0-examples`, off `release/0.6.x`; PR into `release/0.6.x`.
- Commit per coherent group (per-example or per-criterion). Raise an amendment if EX-4's
  feature scope balloons — but the headline features all already exist in the code, so
  this is wiring runnable demos, not new functionality.
- House style applies to examples doubly — users read them. No `export_all` hacks bleeding
  into shipped example code; clear, idiomatic, commented where it teaches.
- Closing report: per-criterion disposition (EX-1…EX-8); name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope

New protocol features (the surface is complete — this is demonstration + CI). The M7
roadmap items. Do not modify `src/` behavior to suit an example — if an example needs an
API that doesn't exist, that's a finding to raise, not a silent `src/` change.

## Release gating

**0.6.0 is not tagged until this is green.** The release notes
(`docs/0.6.0/RELEASE-NOTES-0.6.0.md`) stand, but publishing them + the tag waits on
examples that actually compile, run, demonstrate the features, and are CI-guarded.

## Done when

Every example compiles and runs on the 0.6.0 core; the set demonstrates the headline
features; examples are built + smoke-tested in CI (a break fails the build); the broken
example profiles are fixed; docs/READMEs are aligned; M5b-7's amendment is recorded; all
gates green. Submitted for CDC sign-off — the last real blocker before tagging 0.6.0.
