# erlmcp 0.6.0 — Release checklist

**Gating sequence for the one-way operations.** Walk every item in order. Do not
tag until every item in sections 1–3 is green. Do not publish the GitHub release
until section 4 is complete.

Status: ☐ not started · ◐ in progress · ☑ done (with evidence below)

---

## 1. Pre-tag: feature completeness

These items close the Phase 6 milestones and the P6-M7 howto arc. Each must be
done before the 0.6.0 tag.

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1.1 | **M1–M5 merged to `release/0.6.x`** — the core spine, stdio transport, discoverability machinery, Streamable HTTP, and strict validation are all on the integration branch. | ◐ | M1–M5 on `release/0.6.x` at d49b9cb (P6-M5 iter 3). |
| 1.2 | **M6 merged to `release/0.6.x`** — examples rehabilitation + Claude Desktop acceptance procedure. | ☐ | Pending PR merge of `task/0.6.0-p6m6`. |
| 1.3 | **Claude Desktop acceptance verdicts landed** — all three examples (`simple`, `calculator`, `weather`) have a `pass` / `partial` / `fail` verdict in `docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`. Any `partial` or `fail` is accompanied by a tracked follow-up issue. | ☐ | Requires human execution against a running Claude Desktop. See the acceptance procedure in the acceptance doc. |
| 1.4 | **Howto acceptance test** — following `docs/creating-an-mcp-server.md` literally on a fresh checkout produces a working server. Verdict documented in `docs/0.6.0/acceptance/phase6-howto-acceptance.md`. | ☐ | Requires human execution. |
| 1.5 | **Howto exists and is complete** — `docs/creating-an-mcp-server.md` exists, all code blocks compile, discoverability section and validation-at-edge section present. | ◐ | File created in P6-M7 branch (this commit). Acceptance verdict (1.4) pending. |
| 1.6 | **Release notes finalized** — `docs/0.6.0/RELEASE-NOTES-0.6.0.md` has no `TODO` / `TBD` / `<placeholder>` markers; all claims grounded in ledger evidence. | ◐ | Updated in P6-M7 branch. CDC spot-check pending. |
| 1.7 | **Migration guide finalized** — `docs/0.6.0/MIGRATION-0.5-to-0.6.md` has no `TODO` / `TBD` / `<placeholder>` markers; before/after code for all major API deltas. | ◐ | Updated in P6-M7 branch. |

---

## 2. Pre-tag: gates green

Run these in order. All must exit 0 before tagging.

| # | Command | Status | Evidence |
|---|---------|--------|----------|
| 2.1 | `make compile` — zero warnings | ☐ | |
| 2.2 | `rebar3 xref` — clean | ☐ | |
| 2.3 | `make check` — all suites pass, coverage ≥90% per-module, PropEr properties pass | ☐ | |
| 2.4 | `make dialyzer` — clean on OTP 27 and 28 | ☐ | |
| 2.5 | `make compile-examples` — clean | ☐ | |
| 2.6 | `! grep -rnE "nowarn\|-dialyzer\(" src/` — no new suppressions | ☐ | |
| 2.7 | **CI green across OTP 25–28** on the version-bump commit on `release/0.6.x` | ☐ | CI URL: |

---

## 3. Version bump

The version bump is its own focused commit. It and the tag land at the same commit
on `release/0.6.x`.

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 3.1 | `src/erlmcp.app.src` `vsn` field updated from `0.5.1` to `0.6.0` | ◐ | This commit (`task/0.6.0-p6m7`). Lands on `release/0.6.x` after PR merge. |
| 3.2 | Version bump is a single commit, message `release: 0.6.0` | ◐ | Commit SHA: (to be filled after merge commit on `release/0.6.x`) |
| 3.3 | `grep -nE '\{vsn,\s*"0\.6\.0"\}' src/erlmcp.app.src` returns one match | ☐ | |
| 3.4 | All gate commands in §2 pass on the version-bump commit | ☐ | |

---

## 4. Tag and publish (one-way operations)

**Do not execute these until §1–3 are complete and CI is green on the bump commit.**

The order is: tag → push tag → verify CI on tag → publish GitHub release.

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 4.1 | `git tag 0.6.0 <bump-commit-sha>` | ☐ | Tag SHA: |
| 4.2 | `git push origin 0.6.0` | ☐ | |
| 4.3 | CI green on the tagged commit (`git ls-remote --tags origin 0.6.0` confirms tag on remote; CI passes) | ☐ | CI URL: |
| 4.4 | GitHub release created at tag `0.6.0`, body sourced from `docs/0.6.0/RELEASE-NOTES-0.6.0.md`, marked **Latest** | ☐ | Release URL: |
| 4.5 | Release body renders cleanly (check for broken links, missing sections, rendering artifacts) before marking Latest | ☐ | |

---

## 5. Post-release

| # | Item | Status |
|---|------|--------|
| 5.1 | `release/0.6.x` merged to `main` | ☐ |
| 5.2 | 0.6.1 milestone opened with carry-forward items from M6/M7 closing reports | ☐ |

---

## Carry-forward items for 0.6.1

These are not blockers for the 0.6.0 tag, but must be tracked:

- **Per-tool `inputSchema` validation on `tools/call`** (P6M5 deferred)
- **`weather_app.erl:18:22` dialyzer gap** — typed `server()` accessor needed in
  `erlmcp_stdio_sup` (P6M6-10 named ceiling)
- **`erlmcp_transport_tcp` and `erlmcp_transport_http` coverage** — excluded from
  the gate; re-entry when client transport test suite is written
