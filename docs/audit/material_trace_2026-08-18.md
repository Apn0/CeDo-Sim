# Material trace audit — 2026-08-18

Operator's idea: follow one bale end-to-end. Every stage is input → modification →
output, so every material variable should be both written and read somewhere. Count
how often each occurs; the ones that occur once are broken or dead.

That heuristic came from `_live_pieces`, which occurred **exactly once** in the whole
repo and had blocked every test for three weeks. This audit generalises it.

## Tools built

| tool | what it proves |
|---|---|
| `tools/audit/symbol_flow.py` | every private symbol is declared, written AND read; repo-wide dead constants |
| `tools/audit/material_census.py` | every stage that consumes material also emits it; sub-masses survive each stage |

Both are stdlib-only Python, no Godot needed.

```bash
python tools/audit/symbol_flow.py --root src --all
```

```bash
python tools/audit/material_census.py --root src
```

### symbol_flow was mutation-tested, not just run

Run against the pre-fix `BaleBurst.gd` it reports `_live_pieces … (occurs 1x)` at the
correct line and exits 1. Against current `src/` it exits 0. A checker that has never
been shown a real bug proves nothing, so that pairing is the actual evidence.

Getting to zero false positives took four measured corrections — each one found by
checking a claim against reality rather than trusting the tool:

| FP cause | hits | fix |
|---|---|---|
| apostrophe in a prose comment (`the bale's OWN`) made the string regex eat newlines | line numbers off by 56 | per-line char scanner |
| inheritance (`extends HmiScreenBase`) | 88 | resolve the `extends` chain repo-wide |
| `extends "res://…"` path blanked by string-stripping | 38 | read `extends` from raw text |
| `@onready`, `;`-packed decls, `cm._handling.clear()` | 3 | annotation glob, stmt split, lookbehind |

## Findings

### 1. Mass minting is structurally closed — measured, not assumed
Zero direct writes to `mass_kg` / `volume_m3` / `water_kg` / `contaminant_kg` outside
`MaterialBatch.gd`. Every mass change goes through the conserving primitives
(`split_mass`, `add`, `merge`, `remove_water`, `reject_polymer`). The only way to
create mass is `MaterialBatch.new()`, and all 25 sites are accounted for:

- `BaleDefs.gd` — plant intake, a legitimate boundary (bales arrive from outside).
- `LineFlow.gd:2079` — `draw` is debited from the bale's `remaining_kg`. Conserving.
- `LineFlow.gd:2431` — documented shadow feed to the CutterCompactor model; its
  discharge is explicitly discarded and real accounting stays on LineFlow's in→out path.
- `LineFlow.gd:2796` — the reject side stream.
- `PlantResume.gd:127` (added 2026-09-26) — the save/load boundary: `batch_in()`
  re-creates the batches a save wrote. The census flagged it twice (MINTS and
  DROPS_SUB), and the full harness stopped at `== material census ==` on `main`
  from `dde61eb` (#324, the first merge carrying it) to `7e37741`: measured,
  census exit 0 at `c1dabb7` and exit 1 at `dde61eb`. MINTS is right, and a
  load is a boundary like the bale intake.
  DROPS_SUB is a blind spot of the census, not of the file: `strip_comments()`
  blanks string literals, so a sub-mass carried by dict key
  (`d.get("water_kg", 0.0)`) counts as 0, and `Dictionary.merge()` counts as an
  emit. It is now a `BOUNDARY` entry, and the carry the census cannot see is
  proven at runtime by `test_plant_resume` A11 (per-body water and contaminant
  before the save and after the resume, mutation-proven). A boundary for a
  string-key blind spot needs such a runtime check; a boundary alone would stop
  the census watching the file and prove nothing.
  `docs/audit/plant_resume_2026-09-25.md` §8.

### 2. The invariant already exists AND is asserted — but only on line 3C
`LineFlow.ledger_residual()` is exactly the operator's formula:

```
residual = fed_mass + water_added
         − gran_mass − waste_mass − contam_removed − water_removed − poly_rejected
         − in_transit
```

It is asserted in `src/tests/test_line3c_identity.gd:550` (real MainWorld boot) and
`test_cutter_compactor.gd:206`.

**Gap:** macros exist for `line_3a`, `line_3b`, `line_1`, `line_sort`,
`line_intake_3a3b` — none of them assert the ledger. Conservation is proven for 3C
and nothing else.

### 3. ShredderFeedBelt handles mass OUTSIDE the accounting system
`src/scenes/world/ShredderFeedBelt.gd` contains **zero** references to `MaterialBatch`.
It carries mass as bare floats (`_throat_kg`), which is precisely why a minting bug was
possible there: `MaterialBatch`'s invariant cannot protect a stage that never uses it.

The bug itself is fixed — `kg_out` is now drawn proportionally out of `_throat_kg` and
debited — and `_emit_output()` pushes refused mass back into the throat rather than
dropping it. But the stage remains outside the type that enforces conservation.

### 4. `OUTPUT_KG_PER_FILL` — the operator's heuristic, confirmed twice
`ShredderFeedBelt.gd:119` declares `OUTPUT_KG_PER_FILL = 350.0`. It occurs **once** in
the entire repo. It is the dead residue of the mass-minting bug whose fix comment reads:

> `digested * OUTPUT_KG_PER_FILL` turned a dimensionless fraction into 350 kg per unit
> fill with nothing debited, so one bale of any weight produced the same invented amount.

Same signature as `_live_pieces`: occurs once, and that fact alone was the tell.

## Not defects — deliberately left alone

- `ProcessModel.gd`'s ~30 unreferenced consts are **captured operator knowledge**
  (training binder + HMI screenshots), not dead code. Marked `# audit: spec-anchors`
  so the dead-constant pass skips the file. Do not delete them.
- 38 remaining single-occurrence constants are informational only.
- All 140 `.bak*` files are gitignored and never doubled a grep hit; they are the
  operator's own backup convention.

## Harness state after the unused-param renames (2026-08-18)

`bash tools/regression/run.sh` → **552 ok, 3 fail, exit 1**.

Passing and relevant here: `test_line3c_identity` (the conservation ledger, real
MainWorld boot), `test_bale_yard_mass_conservation`, `test_feeder_fetch` (one of the
three that the `_live_pieces` parse error had blocked), and
`test_belt_discharge_geometry` — 27/27 ok, the test the stray `temp.gd` was breaking.

Still failing, all pre-existing:

| check | failure |
|---|---|
| `test_nav_connectivity` | 6 broken post↔canteen routes (Kevin, Emrah, Yassine, Abdellilah, Mohammed) |
| spawn clearance NOLINE | `0 bale bodies exist` — check would be vacuous |
| spawn clearance LINE | same |

None of them reference anything changed here (0 matches for `BaleBurst`,
`_update_animation_blend`, `DayNightCycle`, `InteriorLighting`, `ProcessModel`), and
`BaleBurst.open()` is reachable only from `WireCutter.gd:265`, which neither test
exercises. The renamed parameters were unused by definition — that is why the lint
flagged them — so they cannot alter behaviour.

Caveat, stated plainly: there is no clean pre-fix baseline to A/B against, because
before the `_live_pieces` fix the repo did not parse at all and the harness stopped at
the gate. The attribution above rests on non-reference plus the inertness of the
renames, not on a green-to-red comparison.

Likely origin is the merge at HEAD (`88e19f3`, "Redo the merge resolution properly —
the first one did not parse", 58 commits).

Also observed: Godot exits with a **segmentation fault** after
`test_belt_discharge_geometry` completes. Every check in it passes first, so the crash
is on shutdown, but it swallows the harness's per-test verdict line. Unexplained.

## Fixed: spawn clearance was gating on a check that could never pass

`test_spawn_clearance` failed in both configs on `at least one bale body exists to
test — 0 would make this check vacuous`. The guard was right; the check behind it was
unreachable.

Yard bales are **streamed**. `BaleYardManager.tick()` materialises a slot's RigidBody
only while a player or a `"vehicle"`-group node is inside the 24 m NEAR radius
(`BaleYardManager.gd:112`). This test parks its vehicles on their save markers, and
those are nowhere near the yards — computed from the test's own logged coordinates:

| | |
|---|---|
| nearest vehicle → nearest yard centroid | **58.7 m** (BaleClamp → yard #4) |
| NEAR spawn radius | 24.0 m |
| shortfall | **34.7 m** |

So `yard_bale_rb` was always empty and the check had failed on every run since it was
added in `94c685b` (2026-07-22) — roughly four weeks red, gating the harness.

Fix: park one probe per yard (7), give the time-sliced drain queue 180 frames, run the
existing overlap pass unchanged, then free the probes before check D sweeps the
`"vehicle"` group.

Measured after the fix:

| config | before | after |
|---|---|---|
| NOLINE | FAIL (11 ok, 1 fail) — 0 bales | **PASS (12 ok, 0 fail)** — 3234 bales |
| LINE | FAIL (10 ok, 1 fail, 2 advis) — 0 bales | **PASS (11 ok, 0 fail, 2 advis)** — 3234 bales |
| `SPAWNCLEAR_PLANT=1` mutation | 3 checks red | **3 checks red** (detection intact) |

This is coverage gained, not silenced: 3234 real bale bodies are now shape-queried
against machines, shell and vehicles, and none is embedded.

Backup: `src/tests/test_spawn_clearance.gd.bak_streamprobe`.

## Open

`test_nav_connectivity` still fails — 6 broken post↔canteen routes, ending 3.68 m to
40.45 m short (Kevin, Emrah, Yassine, Abdellilah, Mohammed). Not investigated yet.

Line 3A / 3B / line_1 have no conservation assertion. The 3C test is the template.
