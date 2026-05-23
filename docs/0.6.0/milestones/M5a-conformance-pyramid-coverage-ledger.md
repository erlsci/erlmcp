# Milestone M5a: Conformance scorecard, test pyramid, specs & coverage

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`).

**Branch:** `task/0.6.0-m5`, cut from `release/0.6.x`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M5a-1 | Dated, versioned scorecard artifact committed. | Artifact exists at `conformance/results/`; lists each scenario. | serious | dev plan M5a | done | `d0d4e12`; `conformance/results/erlmcp-0.6.0-2026-05-23.txt` committed. `publish_scorecard/0` writes dated file with server+client+transport scores, L0–L4 scenario detail, reference figures. `erlmcp_conformance_tests:publish_scorecard_test` verifies file creation + content. | |
| M5a-2 | Discoverability surfaces scored; directory tool excluded (DISC-6). | Scorecard includes discoverability; no directory entry. | serious | dev plan M5a | done | `d0d4e12`; 3 discoverability scenarios added to server scorecard: `instructions_present`, `meta_wayfinding`, `annotations_present` (all L4). The directory tool is not in the scenario list (DISC-6). `grep "directory" conformance/results/*` → 0 matches. | |
| M5a-3 | Scores ≥ rmcp reference (87.5%). | Scorecard shows ≥ reference. | serious | dev plan M5a DoD | done | `d0d4e12`; Server: 100% (27/27), Client: 100% (16/16), Transport: 100% (9/9). All exceed rmcp reference of 87.5%. Reference cited in artifact. | |
| M5a-4 | Full test pyramid CI-enforced: EUnit + CT + PropEr. | CI runs all three; all pass. | serious | dev plan M5a | done | `d0d4e12`; EUnit: 363 tests. CT: 89 tests (7 suites). PropEr: 8/8 properties (envelope + session lifecycle). All in CI workflow (`rebar3 eunit`, `rebar3 ct`, `rebar3 proper -c`). | |
| M5a-5 | Every exported function has `-spec`; every exported type has `-type`/`-opaque`. | Script reports zero unspecced exports; Dialyzer clean. | serious | dev plan M5a | done | `d0d4e12`; Python script check across all `src/*.erl` reports 0 missing specs (excluding gen_server/gen_statem callbacks which have framework-defined contracts). Dialyzer succ-typing clean. | |
| M5a-6 | Coverage ratcheted toward 95%; every module ≥90% or named-line amendment. | `cover` passes at raised gate; per-module numbers reported. | serious | dev plan M5a | done | `d0d4e12`+`8ebf079`+`cae4883`+`87eb693`; **Aggregate: 94%. Every module ≥90%; no amendments.** Per-module: erlmcp 97%, client_session 91%, server_session 93%, erlmcp_sup 92%, server_sup 100%, transport_sup 100%, session_sup 100%, tcp 95%, http 99%, streamable_http 96%, registry 93%, schema 93%, json_rpc 93%, ctx 95%, **stdio 98%**. The earlier stdio "structural ceiling" was disproven (`87eb693`): the `io:get_line` dependency was hardcoded, not unreachable — dependency injection (`read_fun`) + extracted pure functions (`process_raw_input/1`, `prepare_line/1`, `trim_trailing_crlf/1`) took it 71%→98% with no mocking. Gate at 90% (94% aggregate clears with margin); only the M6 task modules remain excluded. | The 95% aggregate target is 1pt shy at 94%, but the per-module floor is universally met with zero exceptions — the substantive coverage goal. |
| M5a-7 | Dialyzer clean + xref clean, in CI. | `rebar3 dialyzer` exit 0; `rebar3 xref` clean. | serious | dev plan M5a | done | `d0d4e12`; Both clean. Both in CI workflow. | |
| M5a-8 | Full CI pipeline green. | CI green on branch. | serious | dev plan M5a DoD | done | `d0d4e12`; 363 EUnit + 89 CT + 8 PropEr = 460 tests, 0 failures. Dialyzer clean. xref clean. Coverage: 90%. | |

## Closing walk

| ID | Disposition | Evidence summary |
|----|-------------|------------------|
| M5a-1 | done | Scorecard artifact at `conformance/results/erlmcp-0.6.0-2026-05-23.txt` |
| M5a-2 | done | 3 discoverability scenarios scored; directory tool excluded |
| M5a-3 | done | Server 100%, Client 100%, Transport 100% — all ≥ 87.5% reference |
| M5a-4 | done | 363 EUnit + 89 CT + 8 PropEr, all CI-enforced |
| M5a-5 | done | 0 unspecced exports; Dialyzer clean |
| M5a-6 | done | 94% aggregate; every module ≥90%, no amendments (stdio 71%→98% via DI) |
| M5a-7 | done | Dialyzer + xref clean in CI |
| M5a-8 | done | 460 tests, 0 failures |

**Uncertainty:** None. The one prior exception (`erlmcp_transport_stdio`) was disproven and fixed — `87eb693` took it 71%→98% via dependency injection. Every module is now ≥90% with no amendments; aggregate 94%. (The 95% aggregate target is 1pt shy, but that is not an amendment — no module is below floor and nothing is unreachable.)

## What Worked

1. **The conformance harness grew incrementally.** M2b landed server scenarios, M3b added client, M4 added transport. M5a just formalized the output into a committed artifact — no new test infrastructure.

2. **Discoverability scoring leveraged existing protocol-native surfaces.** `instructions`, `_meta`, and `annotations` are all part of the normal protocol — scoring them required 3 small scenarios, not a new test framework.

3. **Specs were already complete.** The house style's "spec every exported function" rule (enforced since M1) meant M5a-5 was a verification pass, not a backfill.

## Carry-forward to M5b/M6

- **Scorecard artifact** links from M5b's docs.
- **Coverage debt: cleared.** The earlier sub-90 modules were all resolved — server_sup 66%→100% and erlmcp_sup 70%→92% (dead code deleted + two real supervision bugs fixed, `cae4883`); stdio 71%→98% (dependency injection, `87eb693`). No coverage amendments remain.
- **Task modules** (`erlmcp_task`, `erlmcp_task_sup`) remain the only `cover_excl_mods` entries, until M6.

## Closure

Closed at commit `d0d4e12` on 2026-05-23 (coverage resolution `8ebf079`/`cae4883`/`87eb693`).
CDC verification: **signed off 2026-05-23 (Claude/CDC session).** Verified: the dated
scorecard artifact exists and is committed with the directory tool excluded (DISC-6);
discoverability surfaces scored; `-spec`/`-type` completeness; and the coverage
resolution — the stdio refactor (`read_fun` DI + exported pure functions
`process_raw_input/1`/`prepare_line/1`/`trim_trailing_crlf/1`) is sound and confines
`io:get_line` to a one-line `default_read/0`, disproving the prior "structural ceiling."
**Every implemented module is now ≥90% with zero coverage amendments** (aggregate 94%,
1pt shy of the 95% aspiration but with a universally-met per-module floor).
Toolchain-gated figures (94% aggregate, 460 tests, Dialyzer/xref) rest on CI green;
verified structurally from the code. The CDC note for the M5b docs: link the scorecard
artifact and reflect this final coverage state.
Total rows: 8. Done: 8. Deferred: 0. No-op: 0.
