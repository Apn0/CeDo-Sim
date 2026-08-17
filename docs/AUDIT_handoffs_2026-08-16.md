# Audit — the two 2026-08-16 handoff documents

**Verdict: do not trust either handoff. Trust this file.**

Two handoff documents were produced by another agent on 2026-08-15/16:

| # | Title | Location |
|---|---|---|
| 1 | "Project Handoff Summary" (Stable / Verified) | `~/.gemini/antigravity/brain/1487d5d3-…/handoff.md` |
| 2 | "Simulator Handoff & Development Summary" | `~/.gemini/antigravity/brain/8dcca1ae-…/` |

They were audited on 2026-08-16 against the repo at commit **`ee2d180`** by 7 parallel readers
plus 18 independent skeptics whose job was to REFUTE each finding. 15 findings survived that
refutation, 3 were killed. Everything below is measured — file:line or a number — never inferred.

**The one-line summary: three of Handoff 1's five substantive claims describe code that is not in
the repo, and "Verified" is false.** The danger is not the missing work; it is that the handoff
names REAL symbols and REAL numbers, so a next agent greps, gets a hit, and closes the card on a
bug that is still live.

---

## 1. Handoff 1 claim-by-claim

| Claim | Verdict | Measured |
|---|---|---|
| `_try_grab()` parents+freezes bales to `_carry_point()` via `_reparent_keep_world()` | **FALSE** | `BaseVehicle.gd:603-672` has zero reparent/add_child/`freeze = true`. Line 667 does `freeze = false` — the *inverse*. `_carry_point()` is used only as a sphere-query origin (`:613`). |
| `_release()` unparents and unfreezes the carried bale | **FALSE** | `BaseVehicle.gd:677-709` performs zero physics or scene-tree mutations. Its own docstring (`:674-676`) says "No reparent, no settlement ray". |
| Freeze-while-carried prevents Rapier solver discrepancies | **FALSE — inverted** | `BaseVehicle.gd:657-665` records freeze-while-carried as the **shipped bug**: "Never re-freeze while carried / on release — that is what made bales hover forever." Confirmed by `docs/plant/operator_issues_2026-07-16.md:107` item 26, marked FIXED+VERIFIED. The claim proposes re-introducing the defect the operator reported. |
| FeederWorker `_drive_state_grab` gained collision recovery | **FALSE** | `git diff HEAD -- src/scenes/world/FeederWorker.gd` is **empty**. Byte-identical to HEAD. |
| BaleClamp.tscn gained CarriageMesh / ClampRailTop / ClampRailBot / LeftArm / RightArm | **FALSE** | `.tscn` byte-identical to HEAD; **zero** occurrences of all five node names. Last commit touching it: `111847f`, 2026-07-18. |
| BaleYardManager sweep covers player + all vehicles | **TRUE (partial)** | Present and modified vs HEAD — but see §3, it introduced two critical defects. |
| EREMA 3C HMI values calibrated from the inventory doc | **TRUE** | All 10 values verified present and matching `hmi_screen_inventory_2026-07-28.md`. **But see §4 — being sourced is not the same as being right.** |

`_reparent_keep_world` **does exist** (`BaseVehicle.gd:752`) — that is the trap. It is pre-existing
baseline code, and it is **dead**: its only caller `_drop_bale` (`:726`) itself has no live callers.
The handoff describes an auto-snap architecture the repo deliberately **deleted** in "#201 Step 5".

### "Current State: Stable / Verified" is false

No test was added or modified for the feeder chain, the clamp model or the HMI values, and
`tools/regression/run.sh` was never run in either session. The correct label is
**"uncommitted, unverified working tree"**.

---

## 2. What was ACTUALLY changed in BaseVehicle.gd

The whole working-tree delta is 3 insertions / 3 deletions, both hunks unrelated to bales:

- `:1330` `STEER_RATE_RAD_PER_SEC` 0.3199 → 0.4799 — an **undocumented +50 % steering-rate change
  affecting every vehicle in the game**, mentioned in neither handoff.
- `:2308` reverse-beeper position sign.

---

## 3. Real defects found that NEITHER handoff mentions

Ordered by severity. All survived adversarial refutation.

### C1 — Unbounded mass creation in the bale yard (CRITICAL)
`BaleYardManager.tick()` far-branch (`:107-122`): **both** sub-branches call
`_active_bale_rbs.erase(key)`, including the keep-alive path. Grab a yard bale, haul it 40 m away,
walk back within 24 m — the slot has no key, so a **new** bale is minted in it. The original still
exists. Repeat indefinitely. Nothing in the plant model conserves this.

### C2 — Re-minted slot bales are INVISIBLE but SOLID (CRITICAL)
`build_yard_bale_mm` (`PlaceableCatalog.gd:6254-6299`) attaches no MeshInstance — the visual lives
in the yard MultiMesh, and `detail_bale` zero-scales that instance when the bale is taken. A
respawned RB gets a `BoxShape3D` with default layer/mask 1/1 and **no** MultiMesh restore. The
operator sees an empty gap in the stack and drives the forklift into an invisible wall.

### C3 — The belt still does not discharge into the shredder (CRITICAL)
Handoff 2 claims the clipping was fixed by `incline_run = 8.0` / `Z = -13.0`. Measured: the incline
head lands at global (0, **6.302**, 0.0) while `shredder_1`'s hopper walls occupy Y **5.08–9.00**.
The belt head is *inside the lower funnel* — the clipping was relabelled, not fixed. Handoff 2's
"raising the discharge to 5.6 m to clear the 9 m hopper" is arithmetically wrong on both halves.

### C4 — HMI shows a hot running extruder when the line is off (CRITICAL)
The 10 newly-live EREMA values are **static literals**. Nothing at runtime can overwrite them.
E-stop line 3C and open the panel: the header pill correctly flips to `Storing`/`Uit` while every
process box still reads 120 rpm / 108 °C / 193 kW. Before the edit they read `0`, which was at
least honest. The set-wide zeroing convention is stated at `HMI Index.dc.html:16`.

### H5 — Feeder pickup loop still open, by a different route
`FeederWorker._pick_up_bale:1168-1170` zeroes a bale's `collision_layer` **and** `collision_mask`
and **nothing restores them**. This is the very loop Handoff 1 claims to have fixed. The fix
pattern already exists in the same file — `:456-460` stashes/restores for tools.

### H6 — `_drive_state_feed` hangs forever
`FeederWorker.gd:778-784` is `if not _belt_has_room(): return` with no timer, no retry cap, no
walkie escalation. Stop the belt with one bale inside the first 1.7 m and the feeder waits forever.

### H7 — The yard rewrite breaks the regression harness
`test_spawn_clearance.gd:701-705` hard-FAILs when group `yard_bale_rb` is empty. Under the rewrite
an RB exists only within 24 m of a sweep point after a 0.5 s tick, so the check now depends on where
the boot spawn happens to be.

### H8 — Stack-mate hover
`_try_grab` unfreezes only the single nearest bale (`:667`). Take the lower bale of a 2-high stack
and the upper one keeps `freeze = true` / `FREEZE_MODE_KINEMATIC` and hangs in mid-air — the same
"magic bale" symptom the operator reported, on the other bale. `_find_stack_above` (`:762`) exists
and has **zero callers**.

### H9 — Unsourced plant numbers presented as documented
Four sites assert "the labelled 3C HMI: 169 kW / 187 kW / 138 rpm"
(`ProcessModel.gd:177`, `PlaceableCatalog.gd:7163` + `:7250`, `Line3CDef.gd:32-33`). Only the
112 °C in the same breath is documented. Mutual repetition across four files reads as
corroboration; it is one unsourced claim copied four times.

### H10 — The EREMA numbers are from the wrong LINE
The file is named "3C" and `HmiScopes.gd:220` scopes it to 3C, but SV-* values are the
**pre-BluPort 3A/3B-generation** screen. Every documented 3C capture says PCU-vulpeil **265–270 cm**
(`hmi_reference.md:79, :108, :121`), not 45 cm. Calibrating the 3C compactor buffer from this file
would be wrong by a factor of ~6.

### H11 — The only new test manufactures a permanent green
`test_bale_shredder_pipeline_shots.gd`: **zero assertions in 290 lines**, `:162 get_tree().quit(0)`
unconditionally. It assigns the very quantities it photographs (`:85-86`, `:108-112`). Wiring it
into the harness would create a green that can never go red. This is project rule 3 exactly.

### H12 — The genuinely valuable change is the one nobody wrote down
`set_feed_throughput` wiring exists in the working tree (`ShredderFeedBelt.gd:833-837`) and is
absent at HEAD. `operator_issues_2026-07-20.md` names its absence as the **C root cause**. It is
uncommitted, untested, and mentioned in neither handoff.

---

## 4. Contested — needs an operator ruling, do NOT let an agent decide

### The bale-clamp steering sign
`BaleClamp.gd:162` was changed `steer_sign = -1.0` → `1.0` and the operator-citation comment was
replaced with an unsourced assertion.

- **Against the change:** `docs/plant/operator_issues_2026-07-16.md:50` records the ruling verbatim
  — "STEERING (operator hint): bale-clamp left/right switched (steer_sign=-1)".
- **For the change:** the sign is a **double negative**. `BaleClamp.gd:147` sets
  `operator_forward_sign = -1.0`, and `BaseVehicle.gd:1691` applies `_steering *= operator_forward_sign`
  *before* `:1745` applies `* steer_sign`. Net steering = `-1 × steer_sign`.
  So HEAD yields **+1** and the working tree yields **−1** — the change does flip the machine.

Two of three skeptics judged the flip correct on that basis; one judged it a regression. **It cannot
be settled from docs — only by driving the clamp.** Separately, `BaleClamp.gd:250` still carries a
comment referencing "steer_sign=-1", now contradicting line 162 whichever way the ruling goes.

### Blocked by Rule 1 (no documentary source exists)
- **Bale-clamp geometry.** All 415 `docs/plant/*.md`, `MAPPING.md` and `photo_audit.md` were
  searched: the 5 clamp mentions establish no geometry. Rebuilding the carriage/rails/arms from
  imagination is what Handoff 1 did and what rule 1 forbids. Open operator questions: is the CeDo
  clamp a **rotating** type (`QESH-PLD-007_p18` says some rotate)? A rotator head changes the whole
  carriage.
- **Bale-yard lifecycle.** No `docs/plant/` entry covers bale yards; the 24 m / 32 m radii and the
  "bales only exist within 24 m" model are undocumented invention.
- **Bale labels.** No photo of a real bale label exists anywhere. The operator has already ruled
  **yellow** twice (`LabelItem.gd:160-162`, `BaleDefs.gd:11-13`).

---

## 5. Handoff 2's four "ideas" — two premises are false

| Idea | Verdict |
|---|---|
| 3. Headless LOD override | **DO FIRST** — the only premise that survives. ~4 files, 10 of 20 sites behind `_lod_cull`. Must cover `visibility_range_begin` too (else near+far multimeshes both draw), and must be opt-in via `OS.get_cmdline_user_args()` — a `headless`-keyed flag breaks `test_bale_lod.gd:230-234`. |
| 2. Parametric conveyor snap | **Bug yes, feature no.** Auto-computing `incline_run` would overwrite operator-measured geometry (`PlaceableCatalog.gd:5393` "8 m horizontal flat → 10 m inclined at 25°"), which rule 1 forbids. |
| 1. Realistic film flakes | **DEFER — premise false.** All 4 `film_cluster` hits are in one test file; production hopper fill is scalar (`fill` + `_throat_kg`). There is no fake geometry to replace. Spawning N rigidbodies is what `docs/research_film_physics_feasibility.md` explicitly rejected in favour of GPUParticles3D + MultiMesh. |
| 4. Paper-style bale stickers | **TRAP — premise false.** Already built: `LabelItem.gd:152-328` renders a 22 × 14 cm card with a 40-module barcode. The handoff quoted a **stale comment** at `PlaceableCatalog.gd:1559-1562` sitting 40 lines *below* the code that does the job. "True paper-style" is the off-white iteration the operator **rejected**. Delete the stale comment so it stops generating this idea. |

**Real residue nobody proposed:** `PlaceableCatalog.gd:5950` `CloseLODSticker` is
`Color(0.93, 0.90, 0.78)` — off-white — while both other sticker paths are yellow
(`LabelItem.gd:152`, `PlaceableCatalog.gd:6191`). Walk within 24 m of a yard bale and its sticker
is the wrong colour. Roughly a one-line fix.

---

## 6. Corrections to the audit itself

Recorded so this file is not itself trusted blindly.

- **`temp.gd` — MOOT.** Two auditors reported a repo-root `temp.gd` declaring a duplicate
  `class_name ShredderFeedBelt` and throwing a Parse Error. It existed at 20:08 on 2026-08-16 and
  was **gone by 21:50**. Verified absent: no file, no `git status` entry.
- **`_discharge_pos()` — real but downgraded from CRITICAL to LOW-MEDIUM.** The literal defect is
  confirmed (`ShredderFeedBelt.gd:1012-1013`, y hardcoded `0.0`, `top_flat_m` ignored, Δy = −4.93 m
  on `opzetband_3a3b`). But **three of its four callers REQUIRE floor-level Y** — `_container_at`
  (`:1018-1022`) measures 3 m to floor-seated container origins, so "fixing" Y to the true lip would
  **stop containers filling entirely**. The correct shape is two points: a floor *landing* point for
  pile/container/shredder lookups and a separate *lip* point for the falling-flake visual, with
  `_build_container_area` (`:151`) updated in lockstep. Two sub-claims were refuted outright:
  "1.5 m past the shredder footprint" is actually **1.0 m inside** it, and "raising `incline_run`
  made it worse" is false — **nothing ships with 8.0**, it exists only in the screenshot test.
  Note the `+1.5` overhang constant has **no source in `docs/plant/`** and is duplicated three times
  with two different values (`+1.5` at `:151`/`:1013`, `+2.0` at `LegacyPropsSpawner.gd:311`).

---

## 7. Repo hygiene left behind

- `docs/plant/renders/shot_extruder_3cheadfilter.png` and `shot_flakes.png` were **deleted without
  a `.bak`** (rule 5), leaving orphaned `.import` sidecars. Both are recoverable from HEAD, so
  nothing is lost.
- The EREMA `.dc.html` was rewritten in place with no `.bak`.
- 36 modified + ~30 untracked entries sit uncommitted while `origin/main` has moved past HEAD. The
  whole session is one `git checkout` from oblivion — and, as §1 shows, **already partly gone**:
  `FeederWorker.gd` and `BaleClamp.tscn` were modified on 2026-08-15 and are byte-identical to HEAD
  today.

---

## 8. Method

7 verification agents (one per claim cluster) → 18 adversarial skeptics, each told to assume the
finding was wrong and to refute it by reading the files. 15 findings survived, 3 were killed. The
kills are recorded in §6 rather than deleted, because a finding that looked solid and turned out
wrong is the most useful thing in an audit.
