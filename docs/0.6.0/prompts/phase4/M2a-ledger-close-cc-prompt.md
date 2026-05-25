# CC Prompt — erlmcp 0.6.0, M2a ledger closing pass

> Imperative brief for **CC**. No code changes — this fills in the ledger and writes
> the closing walk. CDC has independently verified the implementation at `c0e697a`
> (static Verify + code read of the DISC derivation); the remaining gate is the
> ledger's own bookkeeping. Continue on `task/0.6.0-m2a`.

## Why

All 25 rows are implemented and CI is green, but every row's `Status`/`Evidence`
column in `docs/0.6.0/milestones/M2a-tools-ergonomics-discoverability-ledger.md`
still reads `open`. Per `priv/ai/LEDGER_DISCIPLINE.md` a milestone does not advance
until the ledger is fully closed with a per-row disposition and evidence. Do that.

## Tasks

1. **Fill `Status` + `Evidence` for all 25 rows** (M2a-1..16, DISC-1..9). For each
   row, `Status` = `done` (or `deferred`/`no-op` with reason if you now judge
   otherwise — raise it, don't force `done`). `Evidence` = the commit SHA
   (`458e97c` for M2a-1; `c0e697a` for the rest) **plus** the actual Verify-command
   output or test name that proves it — e.g. for M2a-3, `grep -c "^-callback"
   src/erlmcp_server_handler.erl` → `2` and `rebar3 xref` clean; for the DISC rows,
   the passing EUnit test name from `erlmcp_disc_tests`. Evidence is what was *run*,
   not a restatement of the criterion.

2. **Write the closing report — a per-row walk**, not a prose summary. One line per
   row: final disposition + evidence. No "deviations: none." Name any uncertainty.
   (This is the same format you used for M1.)

3. **Fill the `What Worked` section.** Record honestly, including the two design
   characteristics CDC surfaced so they're not lost:
   - DISC metadata is a **verified** invariant (the `erlmcp_disc_tests` suite
     against the registry), **not a structural one** — `add_tool/2` accepts a tool
     lacking `category`/`when_to_use` (they are optional map keys per M2a-2). This
     matches the design (§3: "verify completeness as a ledgered invariant"). Note it
     so M2b/M5 can decide whether a strict registration mode is ever wanted.
   - `instructions` is **frozen at `initialize`** (computed once, stored in
     `#data.instructions`); `tools/list` and the directory are the live surfaces.
     A runtime-added *new category* therefore won't appear in `instructions` until
     re-initialize — the intended tradeoff (design §6).

4. **Fill `Carry-forward to M2b+`.** At minimum: modules still in `cover_excl_mods`
   and their target milestone (the sups + `erlmcp_registry` → M2b; `erlmcp_client` →
   M3; `erlmcp_transport_stdio`/`_tcp` → M4); and the patterns M2b must **reuse, not
   reinvent** — opaque-cursor pagination (`paginate/2`), `list_changed` notification,
   the `erlmcp_schema` builder + boundary `jesse` validation, and the capability-map
   derivation.

5. **Fill the `Closure` block.** `Closed at commit <SHA> on <date>. CDC
   verification: <name/session>. Total rows: 25. Done: <n>. Deferred: <n>. No-op:
   <n>.` Leave the CDC-verification name for CDC to confirm, or mark it pending CDC
   sign-off — do not self-certify the CDC line.

6. **Commit** as the M2a closing commit (e.g. "M2a: close ledger — Status/Evidence,
   closing walk, carry-forward").

## Out of scope

No source changes. If filling Evidence surfaces a row that doesn't actually hold,
**stop and raise it** rather than papering the ledger — but CDC's read at `c0e697a`
found all 25 substantively satisfied, so this should be bookkeeping only.

## Done when

All 25 rows carry `Status` + real `Evidence`; the per-row closing walk, `What
Worked`, and `Carry-forward` sections are written; the `Closure` block is filled
(CDC line left for CDC); committed on `task/0.6.0-m2a`; submitted for CDC sign-off.
