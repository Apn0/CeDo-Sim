# The world suites' building frame was rotated twice — fixed (2026-09-25)

Found while ruling on the operator's 3A/3B gate (`jam_baseline_layout_leak_2026-09-24.md`,
"Operator ruling 2026-09-25"): the six typed wall lines the old door check used
did not line up with the 3D shell. This is that frame, measured, replaced and
re-measured.

Everything below ran in an **isolated APPDATA** (a copy of the operator's
`app_userdata`, `world_layout.json` md5 `e046af7d…`). His real file was checked
by md5 before and after every batch and never changed.

## 1. What was wrong

The world suites place line fixtures in a building frame ("bf": metres along the
halls' long axis, 0..150.7, and across them, 0..71.5). 17 files under
`src/tests/` (12 suites, 3 probes, 2 tools) carried their own copy of the same
three constants:

```
BF_O  = (573.404, 463.647)   BF_XU = (-0.64279, 0.76604)   BF_ZU = (-0.76604, -0.64279)
```

and mapped them to the scene with `Plant.pc_to_scene`. The constants were
written when Plant Coordinates were aligned with the scene. Plant now applies
the operator's world yaw (`Basis(UP, +130.2°)`), so the frame was rotated a
second time.

Measured against the shell's own triangles (the pre-carve set `WallOpenings`
caches; `src/tests/probe_bf_sets.gd` and the earlier frame probes):

| What | Measured |
|---|---|
| Direction of the shell's walls in scene XZ (mod 90) | **40.00°** |
| Direction of bf +x after `Plant.pc_to_scene` | **−0.2°** |
| Outline corners within 1 m of a wall | 4 of 10; the other 6 were 3.6–39.8 m from any wall |
| Line 3A from bf(4,22), as five suites build it | **8 of 39 machines outside** (the vss_silo 21 m out) |
| The same constants mapped with NO yaw | all 10 corners 0.0 m from a wall |

So the typed geometry was right and the mapping was wrong. `regression_world_save`
reported "ALL placed machines inside building footprint (39/39)" throughout: it
mapped each machine back through the same frame that placed it, which cannot
disagree with itself.

## 2. The fix

**`src/tests/building_frame.gd`** (preloaded, no `class_name`) uses the frame the
game already FITS from the shell at runtime,
`InteriorLightingManager.get_building_frame()` (oriented box over the hull,
orientation chosen by measured roof heights; the TL bars and the map overlay
already use it). On the operator's world:

```
o = (-129.1563, 57.59375)   x = (-0.642858, 0.765985)   z = (-0.765985, -0.642858)   mean roof err 0.18 m
```

It agrees with the typed constants mapped without the yaw to 0.14 m and 0.01°,
and puts all 10 outline corners within 0.03 m of a wall. The helper also
measures the frame instead of trusting it: `outline_off_wall_m` and
`under_roof` (a ray up from the floor against the shell's non-wall faces).

**17 files migrated** (12 suites, 3 probes, 2 tools). Each drops its copy of
the constants and places its lines through the helper. A suite with no fitted
frame FAILS ("building frame FITTED from the shell") instead of building
somewhere else.

**`regression_world_save`** keeps its inside-footprint check and adds three:
the frame is fitted, the outline corners sit on the shell's walls (≤ 1.0 m),
and every placed machine has a measured roof face above it.

**`seed_fixed_equipment`**'s containment check mapped each spot back through
the same affine it was placed with, so no spot could ever fail. It now needs
the bf rectangles AND a measured roof.

## 3. Line positions that had to move

Each set measured with `probe_bf_sets` in the fitted frame: machines under the
roof, and footprint overlaps between the lines of one suite.

| Suite | Old | Fitted frame at the old start | Now |
|---|---|---|---|
| regression, jam, nav, spawn clearance, identity 3A (3A @ bf(4,22)) | 31/39 roofed | 39/39 | unchanged |
| identity 3B (3B @ (4,42)) | 27/32 | 32/32 | unchanged |
| identity 3C (3C @ (4,22)) | 29/37 | 37/37 | unchanged |
| tag snapshot, L3C unit screens, waslijn 3C (3C @ (4,62) + 3A @ (4,22)) | 18/37 + 31/39 | 3C 28/37 | **3C @ (4,44)**: 37/37 + 39/39, 0 overlaps |
| QA loop (3C @ (0,0), the building's corner) | 22/37 | 29/37 | **3C @ (4,22)**: 37/37 |
| lump-cart coverage (1 @ (4,82), 3A (4,22), 3B (4,42), 3C (4,65)) | 11 overlaps | 30 overlaps | **3A/3B/3C @ bf y 10/31/52**, all roofed; **line 1 @ (175,92)**, clear of the shell; 0 overlaps |

Lines 3A/3B/3C are about 20 bf-m wide. Line 1 folds across 85 m and fits
nowhere in this shell. The operator's own line-1 start is 2.5 m outside it too,
so the lump-cart suite stands it outside rather than overlapping the others.

## 4. Before and after, suite by suite

Same isolated userdata, same engine (4.6.3 console). Before = `84952d2`
(helper committed, no suite migrated). After = the migration.

| Suite | Before | After | What changed |
|---|---|---|---|
| parse sweep | 465 ok | 465 ok | |
| `regression_world_save` | 20 ok, 1 skip ("39/39 inside") | **23 ok**, 1 skip | + frame fitted, + outline on walls (worst 0.03 m), + 39/39 under the roof |
| `test_line3a_identity` | PASS (5 ok) | PASS (6 ok) | + frame fitted |
| `test_line3b_identity` | PASS (5 ok) | PASS (6 ok) | + frame fitted |
| `test_line3c_identity` | PASS (26 ok) | PASS (27 ok) | + frame fitted |
| `test_nav_connectivity` | 12 ok | 13 ok | + frame fitted |
| `test_lump_cart_coverage` | PASS (40 ok) | PASS (44 ok) | + frame fitted ×4 |
| `test_qa_loop` | PASS (16 ok) | PASS (17 ok) | + frame fitted |
| `test_l3c_unit_screens` | PASS (121 ok) | PASS (123 ok) | + frame fitted ×2 |
| `test_tag_snapshot` | 30 ok, 1 skip | 32 ok, 1 skip | + frame fitted ×2 |
| `test_waslijn3c_overzicht` | PASS (16 ok) | PASS (18 ok) | + frame fitted ×2 |
| `test_jam_baseline` | 19 ok, 0 skipped | 20 ok, 0 skipped | + frame fitted; navmesh 283 → 543 polygons; jam1 158.6 → 159.3 s, jam3 94.1 → 105.3 s, both arrived 2.19 m from target |
| `test_spawn_clearance` (LINE) | 13 ok, **2 advisory** | **16 ok, 0 advisory** | + frame fitted; both advisories cleared (below) |

Every suite: 0 fail, 0 `^SCRIPT ERROR`. Every check the before-run printed is
still printed after (diffed with the numbers normalised). The only changes are
the additions above and the two spawn-clearance advisories. Those were a parked
vehicle embedded in the synthetic line 3A (94 %) and a vehicle perched on its
Ringleiding. Both came from the part of the line that stood in the vehicle yard.

## 5. Mutation proofs

Each on the migrated tree; files restored from copies and md5-checked after.

| Mutation | Result |
|---|---|
| **M1**: the old frame (typed constants through `Plant.pc_to_scene`) handed to every regression check | 21 ok, **2 fail**: outline worst **39.75 m**, roof **31/39**. "Inside footprint" stays **39/39 green**: the old check could never see this |
| **M2**: line 3A anchored at bf(4,−8), across the long wall | 21 ok, **2 fail**: inside **0/39**, roof **0/39**; outline check green (the frame is right) |
| **M3**: no fitted frame (`fitted()` returns `{}`) | regression 16 ok, **2 fail** (frame fitted; line cannot be anchored). `test_line3a_identity` **FAIL**: frame fitted, plus the feed and mass-ledger checks that need a line |

## 6. The first after-run hit a full disk

The first run after the migration went red in two suites. `test_l3c_unit_screens`
and `test_tag_snapshot` each failed "LEAK GUARD: a forced world save … went to
user://…_world_layout.json (0 save signalled, scratch NOT written)". The log above
each said `[AtomicFile] …tmp is 8192 bytes on disk, expected 10554 — existing file
untouched`. **C: had 0.00 GB free.** AtomicFile did its job (a short write never
replaced a file), and the leak guard correctly reported that no save had landed.

Other damage: SettingsManager's boot write left a **0-byte `settings.cfg`** in the
isolated copy. It was restored from an identical copy (md5 `6ec5c246…`, the same as
the operator's real one) before the re-run, and the 0-byte file was kept aside.

The run was stopped, and 2.4 GB of this session's userdata copies were moved
(not deleted) to `D:\cedo_archive\userdata\session_clever-hypatia_2026-09-25\`.
C: went to 2.86 GB free, with no further growth measured over 15 s. The re-run in
§4 used the copy on D:. Session scratchpads under `%TEMP%\claude` held 10.4 GB at
the time.

**Reading:** a LEAK GUARD "scratch NOT written" next to an AtomicFile
"bytes on disk" error is a disk problem, not a suite problem. Check free space
before chasing it.

## 7. Open

- Line 1 has no position inside this shell. The lump-cart suite parks it
  outside; whether the shell or the macro is wrong is for the operator.
- `probe_bf_sets` is a probe and is not in `run.sh`.
- Of the migrated probes and tools, `seed_fixed_equipment` and
  `probe_tagsnap_mech` were run (§8). `probe_orbs` needs feedback markers;
  `probe_tick_cost` and `probe_world_soak_growth` are long runs. Those three are
  proven only to parse.
- The inside-footprint check is still self-consistent by construction. It now
  stands beside two measured checks rather than alone.

## 8. Tools run after the migration

- `seed_fixed_equipment` (`--main-scene`): `Result: PASS (56/56 inside, 56
  built)` under the new containment rule (bf rectangles AND a measured roof),
  0 `SCRIPT ERROR`. It wrote its `fixed_equipment_entries.json` into the
  isolated copy only. Exit 139 is the known teardown segfault, after the verdict.
- `probe_tagsnap_mech` (mode A, line 3C at the new bf(4,44)): ran to its
  verdict (`estop=false`, doseersilo buffer 217.4 kg), 0 `SCRIPT ERROR`.

## 9. Re-measured on `main`

`main` moved while this was measured (#305 merged the helper, and #306–#310
landed), and three files overlapped: CLAUDE.md, `test_line3c_identity.gd` and
`test_tag_snapshot.gd`. Both suites now count only flow entries, after #307. The
merge of `9b97864` was clean, and it added no duplicate `var`s in either suite.
Measured after `--import`:
- parse sweep: 476 ok, 0 fail;
- all 12 suites: the same ok counts as §4, 0 fail, 0 `SCRIPT ERROR`;
- `test_line3c_identity`: "32 LineFlow machines for 32 flow SEQ entries (37
  SEQ entries in all)";
- jam: jam1 159.0 s, jam3 96.0 s, 543 polygons.

No full `run.sh` was run: the change touches only the 17 files above, and
every suite among them is in this table.
