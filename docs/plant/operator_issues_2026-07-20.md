# Operator issues — 2026-07-20

Captured verbatim-in-substance from the operator's report so none of it gets lost
again. Status is honest: BLOCKED means I must not guess, not that it's hard.

## A. Placement — BLOCKED ON OPERATOR (do NOT guess again)

### A1. HMI placement per line/section or per machine
**Operator: "I asked like 5 times to fix it already."** He is right to be angry,
and the reason it never moved is worse than a bad fix:

- There is **no HMI placement code at all**. `src/build/HmiScopes.gd` calls itself
  the single source of truth but contains zero position data — it maps panels to
  the machines they *control*, never to where they *stand*. `src/build/Hmi.gd`
  `_ready()` never sets a transform; a panel sits wherever it was dropped.
- The 13 scoped HMI placeables (`PlaceableCatalog.gd:483-498`) carry `size`,
  `color`, `hmi_id`, `mesh` — **no position, no anchor, no parent machine**.
- No line macro places any of them (`LineMacroStore.gd`: zero `hmi` hits).
- All 8 previous HMI commits (`dfbd218`, `6e7b91e`, `0e970f3`, `3eb0b14`,
  `bb88087`, `445fed3`, `f42b0d1`, `4968185`) changed screen CONTENT, wiring or
  scoping. **Not one of them could have moved a panel in space.** That is why
  five rounds of "fixed" changed nothing he could see.
- `docs/plant/photo_audit.md:149` still carries the open box:
  `☐ operator flagged HMI stand placement`. It was flagged and never closed.
- `f42b0d1`'s own commit body says: *HMI overhaul deferred ("ask me once we get
  there")*.

**CORRECTION 2026-07-20 (external review, and it is right):** filing A1 as
"BLOCKED ON OPERATOR" was only half true, and the wrong half was the excuse.
The operator's DATA is blocked. The ENGINEERING is not — and the engineering is
a *prerequisite* for the data. There is no placement system for markers to feed
into, so if he described all 13 positions right now, nothing could apply them.
That work is mine and it is unblocked today:

1. add `position` / `anchor` / `parent_machine` fields to the 13 catalog entries
   (`PlaceableCatalog.gd:483-498`);
2. make `Hmi.gd._ready()` apply a transform resolved from `HmiScopes`, so that
   file becomes the single source of truth it already claims to be;
3. build F10-marker capture -> catalog-entry export, so a dropped orb becomes
   placement data.

Only after that does asking him cost him ten minutes instead of being a ninth
failed round. **What I then need, per panel:** which machine or wall it mounts
to, and on which face — as F10 markers, not prose.

### A2. Cutter-compactor / PCU location vs the extruder + intake slit
There IS a spec and the code contradicts it:
- `docs/plant/extruder_line_layout.md:10-12` (operator spec, 2026-07-15):
  *"PCU — large unit sitting ABOVE the barrel near the motor end. Feeds material
  DOWN into the barrel through an intake slider (intrek/opzetschuif)."*
- The code puts it on the floor BESIDE the barrel: `PlaceableCatalog.gd:10128`
  `tw_z = -size.z * 0.42`, standing on four `machine_leg` posts with a base
  plate (`:10131-10137`), discharging through a tangential outlet + throat
  (`:10199-10201`).
- **The intake slider does not exist as geometry at all.** It exists only as an
  HMI readout: `ExtruderBluPortScope.gd:129` `ais_pct` / "AIS-positie".
- Same doc, line 60-61, lists `PCU-above-barrel + intake slider` as **DEFERRED
  pending operator photos/decisions** — which is why it was never built.

**Blocked on:** whether "above the barrel" means the drum itself sits on top of
the barrel, or the drum stands on the floor and only its OUTLET/slider is above
the barrel. Those are very different models and the one-line spec doesn't settle
it. A photo or a marked-up render closes it.

### A3. Head-filter mini control panel
No spec anywhere. Grep for `mini panel` / `bedieningspaneel` / kopfilter+panel
across all 417 docs returns only sorteerlijn and shredder hits, never the
kopfilter. The current geometry (`PlaceableCatalog.gd:10285-10288`) was invented
to hang the SWAP/REPACK E-interaction on — note the surrounding kopfilter housing
IS doc-cited (`:10231-10241`) and this one is not. **Blocked on operator.**

## B. Gauntlet bench — reported behaviour

- **B1. FIXED (`3eb1f38`).** Root cause was NOT a per-kind spawn fallback to a
  default origin — that hypothesis was measured and DISPROVEN
  (`src/tests/test_spawn_transform.gd`). `BuildMode._raycast()` aimed along
  whichever camera was `current`, using its forward axis; the mouse never
  entered into it. The O key makes a STATIC ObserverCam current, so the ray was
  one fixed line and every kind landed on the single point it hit. Bench bales
  looked fine because the rig places them directly, never through build mode.
  Fix: `_aim_camera()` always uses the player's camera.
- **B2. Phantom housekeeping tasks.** NPCs get auto-assigned a leaf-blower task
  with nothing to blow, and an exclamation mark shows for it.
- **B3. Wrong verb/tool: "sweep with the shovel".** A shovel SCOOPS; a broom
  SWEEPS. The task name and the tool are mismatched.
- **B4. Assigned NPCs stand still** instead of executing the task. NOTE: B1
  probably contaminates this — an NPC cannot board a clamp that spawned inside a
  shredder, so some "standing still" may be downstream of the spawn bug. B1 is
  fixed (`3eb1f38`); B4/B5 must be re-measured before they are trusted as
  separate faults.
- **B5. Shift leader stuck on "making rounds"** — task shown, no movement.
  (Related to the boarding-walk freeze fixed in `1cf15bf`? Not proven — the
  gauntlet has no vehicles for that path. Needs its own measurement.)

## C. Feed belt → shredder (mass appearing from nothing)

- **C1.** Bales ride the opzetband THROUGH the shredder and dump on the far side
  instead of dropping into the shredder's top intake.
- **C2.** Nothing visible is riding the belt (the invisible mass rider carries it
  — see `ShredderFeedBelt._tick_film_pieces`), so the operator cannot see what is
  happening.
- **C3.** A pile of fines forms at floor level — either from nothing, or from
  UNSHREDDED bales. Both are impossible. This is a ledger bug, not a cosmetic
  one, and it is the most serious item in this list: mass is being created.

### C — ROOT CAUSE FOUND (traced 2026-07-20), not yet fixed

**The belt never hands a single kg to the shredder.** `ShredderFeedBelt` runs its
own private, *dimensionless* ledger (`fill` and `rider["mass"]`, both 0..1) and
then invents kilograms from it with a hard-coded constant. The shredder's kg
ledger is a parallel universe nothing upstream writes to: `set_feed_throughput`
is never called from `ShredderFeedBelt.gd` at all — the shredder is used only as
a boolean interlock.

The mass source, exactly:
```
ShredderFeedBelt.gd:783-788   fill -= digest_rate * delta
                              _emit_output(digested * OUTPUT_KG_PER_FILL, delta)
ShredderFeedBelt.gd:93        const OUTPUT_KG_PER_FILL := 350.0
```
A dimensionless fill delta is multiplied into kg with **nothing debited anywhere**.
One bale yields up to 350 kg of pile regardless of what it actually weighed —
`accept_bale` hard-codes `"mass": 1.0` (`:632`) and never reads the bale's
`weight_kg` / `remaining_kg` / `RigidBody3D.mass`.

Why fines appear from **nothing**: `PlaceableCatalog.gd:5162` sets
`require_shredder = false` on every catalog-built opzetband, so `_shredder_ok()`
short-circuits true (`:399-400`) and the digest runs **with no shredder present**.

Why the pile is on the **floor past the shredder** (C1): `_discharge_pos()`
(`:942-943`) returns `y = 0.0` at a z beyond the top of the incline, using the
horizontal `incline_run` instead of the hypotenuse and ignoring `top_flat_m`.

Why **nothing is visible on the belt** (C2): `burst_bale` sets
`bale.visible = false` (`:660`) to make it the invisible carrier, and
`_place_rider` (`:936`) writes `position` every frame on a body left
**non-frozen** (`:625-626`), so physics fights the write.

Other conservation faults found in the same pass:
- `:830-832` — `give` is subtracted from the rider but added into a
  `minf(1.0, ...)` clamp; at the clamp the difference evaporates.
- `:838` — the bale is `queue_free()`d still carrying its `remaining_kg`, and
  `bale_consumed` has no kg payload, so nothing credits it.
- `:978` — `FloorPile.add()`'s refused-kg return value is discarded, so mass
  silently vanishes when the pile hits `max_radius_m`.
- `:681,704` — 4..12 film pieces at 0.3 kg each are spawned and freed, never in
  any ledger.
- Possible DOUBLE-DRAW: a reparented bale keeps its `bale` group and `delivered`
  meta, and `LineFlow._bale_at` (`:2445-2467`) filters on those, not on
  parentage — so LineFlow can draw 8 kg/s off the same bale the belt is riding.

**Bonus, explains "rides through the shredder":** `NpcTaskBench` advances the
chain by footprint centre, but `ShredderFeedBelt` builds all its geometry on the
+Z side of its origin, so the belt is drawn ~9 m further +Z than the layout
assumes and `shredder_1` lands *inside* the belt's span.

**Next step (instrument first, per review):** a mass-ledger assertion summing
bale kg + rider kg + belt fill kg + shredder buffer/overflow + FloorPile +
WasteContainer against the initial bale kg, ticking `belt._process(dt)` and
`sh._physics_process(dt)` directly for determinism, with `require_shredder`
forced true so the test isn't vacuous. It will fail on the first run precisely
because rider/fill **have no kg to read** — the unit conversion happens once, in
the wrong direction, with a made-up constant.

## D. Editor warnings — DONE (`de7c9d1`, `1cf15bf`)

Seven sites fixed. Note for future batches: GDScript warnings are **invisible
headlessly** on 4.6.3 (verified: `--check-only`, runtime `load()`, and
`--headless --editor --quit` all print nothing for a planted unused parameter).
They only surface in the editor, which is why they reach the operator and not
CI. `tools/regression/lint_unused_params.py` now gates the unused-parameter
class in `run.sh`; the other classes still need an editor session.

## E. Operator photos 2026-07-20 — compactor conveyor before the PCU

Two photos supplied in chat: a side view of the compactor conveyor carrying the
finished shred, and a close-up of the same material. **They are not yet in the
repo** — drop them into `docs/plant/photos/` so this entry can cite files rather
than a chat message.

What they establish:

- **Flakes are NOT flat squares.** They are torn, curled, folded shreds at every
  attitude, with lengths from specks to long ribbons. `FilmFlakeField` used
  `BoxMesh(flake_size, flake_size * 0.15, flake_size)` — a flat square, yaw-only,
  identical for every instance. Rebuilt (2026-07-20) as a folded 3-ribbon tuft
  with per-flake tilt/roll/length/size. Before/after: `src/tests/shot_flakes.tscn`.
- **Colour distribution.** The mass is overwhelmingly translucent white-grey with
  a scatter of bright specks (blue, red/orange, green, black print) — roughly one
  in five. The old code cycled the full PALETTE evenly, which read as confetti.
  `_flake_color()` now does 80% varied grey / 20% speck.
- **Density.** In the photo the shred is a PACKED CARPET with heavy overlap. The
  field is still a scatter; density comes from each machine's `flake_count`/`area`
  and the live LineFlow state, so it needs tuning per machine — NOT done yet.
- **Still to mine from these photos:**
  - brick wall + staircase in the background — relevant to the deferred tex-02
    (building shell walls, previously rendered black and needing operator eyes);
  - the belt itself: tan/khaki rubber with raised cleats and dirty side rails;
  - the black rubber flap at the left of photo 1 is the **chute from the extruder
    silo** (operator). Check what the model currently puts there.
  - the close-up is a good candidate for a tiling albedo texture for bulk shred.

## F. Operator photo set now IN the repo — `docs/plant/photos/extruder_2026-07-20/`

Operator instruction: **"also save images to the project folder always~!!!"** The
photos had been sitting on his Desktop with self-describing filenames the whole
time; nothing was missing, I just never looked there. Eight copied in.

**The filename prefix on the annotated shot IS a colour legend** — he had already
drawn the polygons I asked for:

`gr-HMI_or-laserfilter_bl-vacuumpots_ye-vacuumcatchresiduebin_pu-headfiltercontrol_pi-headfiltercabinetclosed.jpg`

| Colour | Part | What the photo shows |
|---|---|---|
| green  | HMI | separate floor-standing panel, well off to the side |
| orange | laser filter | its own floor unit, NOT on the barrel |
| blue   | vacuum pots | floor-standing pots beside the line |
| yellow | vacuum catch residue bin | small bin under the vacuum pots |
| purple | head-filter control | narrow vertical panel at floor level, beside the cabinet |
| pink   | head-filter cabinet (closed) | LARGE stainless floor-standing cabinet next to the barrel end |

### This contradicts the current model more deeply than the PCU did
- **Vacuum degassing is modelled as two small domes ON the barrel crown**
  (`PlaceableCatalog.gd` SECTION 5b). The photo shows **floor-standing vacuum
  pots with their own residue bin**, off the barrel entirely.
- **The head filter cabinet was missing entirely** (BUILT 2026-07-20). Correcting
  my own first reading: the piston screen-changer in the model is doc-correct and
  is what you see with a door OPEN
  (`head_filter_cabinet_open_top-cylinder_out_breaker-plate-in.jpg`). What was
  missing is the **enclosure** — a large floor-standing brushed-stainless cabinet
  on legs, chamfered top corner, two vertical door latches. Its **control was a
  hand-sized push-button box bolted to the housing (invented); the photos show a
  separate narrow floor-standing post with a green running lamp**, now rebuilt at
  standing height.
- **The pelletizer** (`pelletizer_closed_hatch.jpg`) is a **cylindrical housing
  with a clamped round hatch** on an EREMA-blue body — not the rectangular
  louvered cabinet currently modelled. That hatch is the "lid/latch" the operator
  asked to have outlined.
- `head_filter_cabinet_open_top-cylinder_out_breaker-plate-in.jpg`,
  `cylinder_out_no-breaker-plate*.jpg` and `breaker-plate_with-tool-attached.jpg`
  document the **breaker plate + screen cylinder** and the extraction tool —
  parts that do not exist in the model at all.

**None of this is built yet.** It is a bigger rebuild than the PCU and should be
its own pass, machine by machine, with a render approval per step.

## G. Renders now land in the project

`shot_placeable.gd`, `shot_annotate_extruder.gd` and `shot_flakes.gd` write to
`docs/plant/renders/` instead of `user://`. A render in
`%APPDATA%\Godot\app_userdata\` is invisible to the operator and uncitable from
these docs.


## H. Annotation filename convention (operator, 2026-07-20)

`<first 2 letters of the colour>-<description>`, joined by `_`, **ordered LEFT TO
RIGHT as the polygons appear in the image**. The ordering is itself layout data.

For `gr-HMI_or-laserfilter_bl-vacuumpots_ye-vacuumcatchresiduebin_pu-headfiltercontrol_pi-headfiltercabinetclosed.jpg`
that reads, left to right: HMI, laser filter, vacuum pots, vacuum-catch residue
bin, head-filter control, head-filter cabinet — with the extruder barrel + EREMA
drive off the right-hand edge. So the real running order puts the laser filter
and the vacuum pots as FLOOR-STANDING units on the far side of the head filter,
not as a disc and two domes riding the barrel crown. Still to build, and the
axis mapping (which way is +Z) needs confirming before anything is moved.

## I. TL bars "mounted to the air" — root cause + fix (2026-07-20)

Operator: "Explain how TL bars are hanging on a mount, mounted to the air,
without falling."

Honest physics answer first: they can never fall — TL bars are static meshes,
and gravity in this engine only acts on RigidBody3D. A wrongly-drawn mount just
hangs where code drew it, forever. "Physics is present" is only true for rigid
bodies (bales, carts, film pieces), never for building fixtures.

Measured chain (each step forced by the previous measurement):
1. Rod lengths came from hand-typed per-zone roof heights. New harness raycast:
   **38/39 rods ended in mid-air, worst gap 5.67 m.**
2. Stretching rods to a measured roof exposed worse: **28/39 bars had NO shell
   face above their column at all** — the whole bay grid stood outside the arcs.
3. The arcs exist in the mesh (verified in the OBJ: smooth 7.40→10.58 m arc
   verts) and in the collision (452 roof-band tris). The bars were placed via
   the HAND-BAKED affine `BF_PC_O(573.404, 463.647)` from 2026-07-06 — and the
   regression "inside" check used a COPY of the same constants. Two copies of
   one stale mapping validating each other; the mesh disagreed with both.
4. Fix: `InteriorLightingManager._fit_building_frame()` fits the frame to the
   shell's measured collision hull (rotating-calipers OBB + roof-height probes,
   mean err 0.18 m) every boot; bars place through the fit; every rod is then
   stretched to an upward raycast hit. Harness now proves it physically:
   **39/39 under a measured roof face, 39/39 rods reach it, worst gap 0.00 m.**

REMAINING USERS OF THE STALE CONSTANTS (same class, not yet fixed):
- `src/scenes/hud/MapOverlay.gd:226` `_BF_PC_O` — the site-map building outline.
- `src/tests/regression_world_save.gd:31` `BF_O` — still used for MACHINE
  inside-tests and door-on-wall tests (machines pass with margin because the
  operator placed them inside the real walls; the constants are still off by
  metres and should be re-derived or fitted the same way).
- `src/tests/probe_orbs.gd:22`, `src/tests/seed_fixed_equipment.gd:20`.

## J. Audio map status (asked 2026-07-20) — honest numbers, NOT ">90%"

What exists and works:
- 43 clips cut from VID-20250912-WA0011.mp4 in `assets/audio/clips/`, allocation
  in `assets/audio/audio_layout.json` (43 entries, RD-pinned).
- `PlantAudio.gd` spawns all 43 as looping AudioStreamPlayer3D at their pinned
  spots (inverse-distance, unit 4 m / max 30 m, random phase offsets). An earlier
  mirror-bug (all clips 85 m off) was found and fixed; 30/43 sit within audible
  range of the operator's working area. Godot's 3D players give positional
  panning, so basic directionality works by engine default.

NOT done — 0%, not "handled":
- Production-state coupling: clips loop 24/7 regardless of whether the machinery
  at that spot is running. Nothing reads LineFlow/machine state.
- Machine binding: audio_layout.json has NO machine field and every `notes`
  field is EMPTY (checked all 43) — clips are pinned to GPS spots, they do not
  follow a machine that gets moved, and nothing knows which machine a clip
  belongs to. The placer never exported that data; allocating it is operator
  work the pipeline has no input for yet.
- Special-sound extraction: zero clips are tagged; no Merlo reverse alarm was
  extracted. The reverse beeper on every vehicle is a SYNTHESIZED tone
  (BaseVehicle._fill_beeper, AudioStreamGenerator) — not the real recording.

## K. Reverse alarm inverted on forklift/bale clamp — root cause + fix

Operator: "why is the reverse alarm when I go forwards and vice versa?
Forks/clamps and seat position and look direction are forwards."

Measured from the scenes: Forklift (mast z=+1.3, CarryPoint +1.05), BaleClamp
(CarryPoint +0.55), Merlo (+0.4) and MerloP40 all have the working gear on +Z,
and all four cab cameras are yawed 180° — the seat faces the gear. But the
canonical drive convention is forward = -Z, so the code called fork-first travel
"reverse": the forward key drove AWAY from what the operator faces, and the
beeper + reverse beam fired during fork-first travel. Every subsystem had
quietly compensated (camera yawed, NPC "carry-first reverse" legs, light layout)
— the beeper was just where the contradiction became audible.

Fix: `BaseVehicle.operator_forward_sign` (-1 on those four; MastLift/cars stay
canonical) applied at the OPERATOR boundary only: throttle polarity (forward key
now drives gear-first), steering polarity (left stays the seat's left), beeper/
beam gate (alarm on counterweight-first travel), and the light layout mirrored
(work lights on the gear side, reverse beam on the counterweight). NPC autopilot
paths are untouched and stay canonical — NPC counterweight-first legs now beep,
which is what a real forklift does.

Verified: harness 15/0/2, npc bench PASS, feeder sequence PASS, merlo_p40 17/0,
mast_jib 14/0. NEEDS an in-game drive to confirm feel (W = fork-first now).

## L. "Bale clamps won't spawn" + 5th clamp at the F10 marker (session 19:13–19:27)

Operator: placed an F10 marker; tried to spawn multiple bale clamps,
"unsuccessful"; the 5th appeared exactly at the marker.

**What the files say** (before any code was touched): the session's factory
save `allernieuwste_factory.json` holds **five** `vehicle_baleclamp` entries —
every click DID place a clamp. Their recorded positions are two vertical
stacks far from the click point: three at scene (≈0, y, ≈0) with y −0.65 /
1.54 / 3.57, two at (≈332, y, ≈0) with y 0.23 / 1.33. The F10 marker (and so
the click point) was (−197.8, −9.0, 90.4) on the exterior ground.

**Reproduced headlessly** (`src/tests/repro_clamp_spawn.gd`, real MainWorld,
real BuildMode placement path, 5 clicks at the exact marker point):

- Every click places a clamp INSIDE the previous one — there was no clearance
  check. The nested hulls shove each other apart and, worse, upward.
- Under the session's 5-FPS regime (`CLAMPREPRO_STALL_MS=200`), each new click
  boosts the earlier clamps into a vertical ladder within ~1 second — up to
  y +4.26, i.e. 13 m overhead, where they settle ON the building-shell
  overhang (a real static at y +1.09 above that spot — measured by
  `src/tests/probe_landing_spots.gd`). At night, 10 m overhead = invisible:
  "spawning is unsuccessful". Only the newest clamp (no click after it)
  stays grounded — "the 5th was exactly at the marker". The stacked-ladder
  y-spacing (~2.1 m) matches the operator's save exactly.
- The 220 m horizontal relocation to (0,0)/(332,0) did NOT reproduce at
  either tickrate (clamps stay within 3 m XZ of the click). That mover is
  still unidentified — see the tripwire below. One measured lead: any point
  near the player anchor maps to pc≈(500,500), and pc (500,500) read back in
  the wrong frame IS the scene origin — a yaw-in/translation-out coordinate
  roundtrip collapses the whole anchor area onto (0,0), which is exactly
  where the trio sat. No code path doing that roundtrip on placed vehicles
  has been identified yet.

**Fixes (this commit):**

1. `BuildMode._place_current` — vehicle spawn clearance gate: a vehicle can
   no longer materialise inside another vehicle. Refusal is LOUD (status
   line: "SPAWN GEBLOKKEERD — <naam> staat op deze plek"), never silent.
2. `BuildMode` vehicle placements get VehicleSpawner's +0.5 m drop cushion
   (wheels no longer materialise exactly flush in the contact manifold).
3. `BaseVehicle._settle_on_ground` — another vehicle is NOT ground: the
   settle probe skips vehicle hulls (walks past up to 4 stacked bodies), so
   the mutual-climb ladder is impossible; probe reach extended 6 m → 40 m so
   a body stranded high finds the real floor again and glides down.
4. Tripwire for the unexplained relocation: `_arm_vehicle_watchdog` measures
   every placed vehicle 1 s after placement and push_warns with before/after
   coordinates if it moved >10 m. If the 220 m mover ever fires again it
   leaves an attributable trail instead of a mystery save.

**Regression:** `repro_clamp_spawn.tscn` is now a lasting PASS/FAIL check
(1 placed, 4 refused, resting on ground, no >2 m/frame teleports) and runs at
both tickrates.

**Operator save cleanup — NEEDS YOUR OK:** `allernieuwste_factory.json` still
contains the five garbage entries; on the next load of that save they will
spawn as two clamp stacks at (0,0) and (332,0). Say the word and I strip the
five entries (backup kept). Alternatively delete them in-game with the
build-mode delete key.

**Separate find (measured, unfixed):** on a clean boot the MerloP40's
grapple/bucket COLLISION bodies (`GrappleArm_P40`, `BucketTilt_P40`,
AnimatableBody3D + sync_to_physics under Rapier) answer raycasts at the SCENE
ORIGIN, 137+ m from the vehicle. CONFIRMED PERSISTENT: still answering
raycasts at (0, −0.09, 0) / (0, −5.20, 0) ten seconds after boot
(probe_landing_spots.gd, t=0 and t=10 s identical). The plant has standing
invisible phantom colliders parked at (0,0) — and the operator's clamp trio
came to rest exactly on top of them (ladder base −0.65 sits on the arm at
−0.09). Likely mechanism: the sub-bodies only move via ANCESTOR transforms
(boom chain), and the Rapier binding never re-syncs a sync_to_physics body
whose own local transform never changes. Fix deferred — needs its own
measured pass (force-sync in _apply_boom, or drop AnimatableBody3D there).

**Separate find #2 (measured, unfixed — frame audit needed):** the boot
header reports vehicle markers as offsets from player_spawn in the RAW
layout frame ("bale_clamp #1 : 57.2 m away (-33.1, 46.7)"), but the actual
PC-path spawn lands at scene (57.0, 183.2) = R(−130.2°)·marker + anchor —
verified algebraically against the logged spawn. Whether the SPAWN or the
HEADER frame is the intended one depends on what WorldSetup writes into
`vehicle_spawns` (anchor-relative vs scene-absolute); needs a dedicated
audit with the WorldSetup writer before touching either side. Symptom if
the spawn side is wrong: world vehicles stand rotated 130° around the plant
from where their markers were placed.

## M. Correction of the record + the canteen-in-the-void bug (2026-07-21)

**I was wrong about the cars.** In the previous reply I named NPC commute cars
as the prime suspect for placed clamps relocating onto the z~0 axis. A
dedicated forensics pass REFUTED that on three independent axes, with cites:

- *Geometry*: no road runs along scene z~0. The whole road network spans
  x [-248, +94]; the commute-car drive-in polyline spans only x [-244.7,
  -227.7], z [54, 124] (`ShiftLifecycleManager.gd:97-102`). The clamp beads
  sit at x -763 .. +814 — between 45 m and 735 m from anything car-related.
- *Physics*: commute cars are teleported, not driven
  (`ShiftLifecycleManager._position_cars_for_elapsed:136` writes
  `global_position` directly), and BOTH cars and placed clamps are
  frozen-kinematic (`BaseVehicle.gd:269-270`). Kinematic-vs-kinematic
  produces no push — stated in this codebase at `BaseVehicle.gd:618-621`.
- *Budget*: each car is live-moving for 15 s max (~120 m), inside the
  pre-shift window only. An 800 m transport does not fit.

Lesson repeated from the F4/fence and car-marker episodes: name a cause only
after measuring it. The bead pattern (pairs at four x values, z collapsed to
~0, straight line through the scene ORIGIN) points at something targeting or
emitting positions near (0,0,0), not at physical shoving.

### The canteen is 224 m outside the plant, in an open field

Measured, confirmed live in the operator's own boot log
(`[MainWorld] CrewManager ready — 9 workers posted, canteen @ (0.0, 0.0, 25.0)`):

`MainWorld.gd:418` — `var break_pos := Vector3(0.0, 0.0, 25.0)`, commented
"a fixed spot near the factory entrance". That comment is stale: it dates
from when the world was origin-centred. Since the plant became georeferenced
(player spawn scene (-202.66, -8.0, 94.04)), scene (0, 0, 25) is bare
exterior ground ~224 m from the building — the same open-field origin where
the MerloP40 phantom colliders sit and where the clamp beads cluster.

`MainWorld.gd:419-422` looks for a `BreakRoom` / `Canteen` child node first,
but NO code anywhere creates one, so the fallback is always used.
`CrewManager.gd:343` sends every break-taker there via `NPC.go_on_break`
(`NPC.gd:877-881`). Nine workers walk a 450 m round trip for a 30 s break —
which plausibly also explains earlier reports of workers "standing still" or
the shift leader stuck "making rounds": they are mid-trek across the field.

Fix shape (no invented geometry, per the no-build-without-docs rule): the
fallback must be derived from the measured plant anchor rather than a stale
origin constant, and the operator should be able to place a real canteen
marker. Any code that walks or DRIVES crew to a destination must also refuse
an absurd waypoint — see the guard being added to
`BaseVehicle.npc_set_target`.

## N. Clamp transport REPRODUCED — and it is not what either theory said

`src/tests/repro_feeder_drive.gd` reproduced the relocation headlessly in a
single 180 s run, loading the operator's own 8-clamp bead save. What the
measurement shows, and it kills the second theory as well as the first:

- The beads are **NESTED PAIRS** — two clamps at the same XZ within 0.02–0.05 m,
  ~0.8 m apart in Y. They are the ladder stacks from the nested-spawn bug, not
  two separate arrivals.
- Each pair **translates as a rigid pair at constant velocity**, forever. The
  pair at x=814 moved **185.1 m in 150 s** (0.551 m/s pure +X for ~35 s, then
  bending to 1.56 m/s) and was **still moving when the test ended**.
- `rotation.y` stayed **exactly 0.0000** for all 10800 physics frames.
  `occupied=false`, `npc_autopilot=false`, no driver, **zero** >2 m/frame jumps,
  zero reparents.
- Other pairs drifted a few metres and **stopped dead**; one never moved at all.

**Why that kills the self-driving theory** (independently of the exhaustive
claiming-path audit, which found that `npc_set_target` is structurally
unreachable for an operator-placed clamp): all vehicle motion goes through
`BaseVehicle._kinematic_move`, which uses `fwd := -global_transform.basis.z`
(`:1203`) and `motion := fwd * speed * delta` (`:1226`). With `rotation.y == 0`,
`-basis.z` is exactly `(0,0,-1)` — a vehicle **cannot** self-propel along ±X
while its yaw is zero. And `_npc_drive` writes `rotation.y` every frame it runs
(`:925`), so a driven clamp could not have kept yaw at 0.0000.

Remaining mechanism under measurement: **depenetration of overlapping
frozen-kinematic hulls**. `_kinematic_move` runs every frame even when parked
(it must, for the ground probe) and calls `move_and_collide` + a remainder
slide. Two hulls sharing space get recovered apart a little each frame —
constant velocity, zero rotation, pair-coherent, ending when the overlap
finally clears (the stoppers) or never (the forever-drifters). That signature
matches the evidence exactly, but it is not yet ATTRIBUTED to a specific
statement, so it is not yet called fixed.

**Already shipped regardless of that outcome:**
- placement-time clearance gate, so new nesting cannot be created (`276d142`);
- a standing 30 s sentinel on every placed vehicle (placed AND restored from
  save) that reports displacement >10 m with a full diagnostic dump: autopilot
  state, target, owner, yaw, and every body within 5 m with velocities;
- an absurd-waypoint guard on `BaseVehicle.npc_set_target` (non-finite, or
  beyond a 500 m plant radius derived from the 200×200 m apron + anchor
  offset). No caller feeds it garbage today — it is a latent hole closed on its
  own merits.

**Process note (own it):** the agent that produced the reproduction rewrote
`user://world_layout.json` as a side effect (`BuildMode._place_current` ends in
`_save_layout()`). Content was verified afterwards field-by-field against the
copy read earlier in the session — factory_center, player_spawn, floor_plan,
7 yards, 3 line starts, 9 vehicle spawns, satellite georeference all identical,
same 9884-byte size. No harm done, but the test now byte-backups and restores
that file, and any future test touching build placement must do the same.

## O. #5 answered — NPCs conjured tools, and also stole yours

Operator: *"are the NPC's wizards or they have some kind of godly telekinesis
power? they create scanner and scissors when assigned to feed area?"*

No physics was involved — it was plain instantiation:

- `CrewManager.gd:749` `WireCutter.new()`, positioned at `:751` **at the
  feeder's feet**, holstered on the next line.
- `CrewManager.gd:755-757` the `BarcodeScanner`, same.
- `CrewManager.gd:739-744` an entire **BaleClamp materialised from nothing**
  on assignment — same violation class, and that is the clamp population the
  relocation evidence concerns.
- Re-fired on **every world load** for saved feeder pins (`:1028`).

The codebase already had the honest pattern and the feeder path just never used
it: `BlowLeavesTask` walks to an EXISTING leaf blower and reparents it,
`HoseSweepTask` the same for nozzles, and `NpcAutonomyBoard:618-619` refuses to
emit a refuel task when no jerrycan exists ("no can = nowhere to refuel").

**Fixed:** tools are now either borrowed from real world tools (claimed, with a
25 m walkability limit, and returned to their exact original parent+transform at
shift end) or laid out at a resolved pickup point on real furniture — the
shift-leader desk, QA bench, locker, else the bound feed belt's frame. The
feeder then WALKS there and picks them up. The pickup is split into two poses:
`rest` (hand height, the tool visibly lies ON the surface) and `stand` (a
floor-level standing spot, ray-dropped and clearance-validated, so the worker
is never parked inside a belt deck or on a machine roof).

### The bug found while proving it: NPCs were robbing the operator

`_tool_is_held` rejected ancestors in groups `feeder_worker` / `npc` / `player`
— but **nothing in the codebase ever joins the group `"player"`** (the node is
class `PlayerController`). So tools **in the operator's own hands read as "loose
in the world"**, and the feeder happily claimed them: the measured pickup point
(-202.44, -7.54, 93.64) was the player's **Head anchor**, 1.46 m above the
floor and moving with the player. The feeder was walking over to take the
scissors off your body, and could never arrive because the target moved and sat
behind the belt deck. Fixed with an explicit `is PlayerController` test.

### Walking, not teleporting

The first cut passed every "no conjuring" assertion but the feeder stalled
**6.3 m short** and a 20 s watchdog force-completed the leg — a teleport in a
smaller coat. Straight-line steering wedged it against the belt deck (slide
normal exactly opposing the heading) and, on another run, against the building
shell 1.1 m from spawn. A NavigationAgent3D would NOT have helped: the baked
navmesh is **2 polygons / 4 vertices** — only floor planes are tagged
`navmesh_source`, so no machine, belt or wall is an obstacle and
`map_get_path` returns a straight line through the belt. (That navmesh is a
separate latent problem worth its own pass.)

Fix: a wall-follow side-step (tangent of the first slide normal, side committed
for 3 s so it cannot rock in place). The watchdog stays as a deadlock guard but
is now an ERROR path that logs the residual distance loudly — it is no longer
how the leg normally ends. Verified 3/3 runs: arrival earned on foot, **0
force-completions**, and the test was TIGHTENED (arrival 3.0 m -> 2.0 m) with
anti-cheat asserts that the standing spot is within arm's reach of the kit and
>3 m from the feeder's spawn, so the target cannot be moved to buy a green.

## P. The clamp drift — ATTRIBUTED to one statement, and fixed (2026-07-21)

Root cause, measured to the single line:

```
BaseVehicle.gd:1267   var hit := move_and_collide(motion)
```

reached every physics frame on every parked vehicle via the unconditional
`_kinematic_move(delta)` at `:1185`. When a vehicle is parked, `motion` is
**exactly `Vector3.ZERO`** — and Rapier3D 0.8.34's contact-recovery pass inside
`move_and_collide` **still translates an overlapping hull, and returns null**.
The displacement is therefore invisible to the calling code: `if hit != null`
at `:1268` never fires, the slide never runs, the wall-bleed never runs,
`_current_speed_mps` stays 0.0, and no existing guard can even observe the
motion. 100 % of the horizontal drift comes from that one statement.

Proven in a MINIMAL scene — one static floor plus paired BaleClamps, no
MainWorld, no BuildMode, no NPCs, no save files. Per-statement attribution
(temporary instrumentation, since removed): the `move_and_collide` call carried
the entire XZ step; the remainder-slide, `rotate_y`,
`_clamp_carried_against_obstacles` each contributed exactly (0,0,0), and
`_settle_on_ground` contributed **Y only**. A direct out-of-band
`move_and_collide(Vector3.ZERO)` moved a nested clamp up to 0.047 m and returned
`false` every time.

Why the pairs behaved differently: recovery persists only while a contact
manifold exists. A near-symmetric manifold pushes BOTH hulls the same way, so
the pair translates as a rigid unit and the overlap **never resolves** — that is
the forever-drifter (measured 23 m in 15 s, still accelerating; separation
constant to 0.02 m). An asymmetric or partial manifold has a net separating
component, so contact clears after a few metres and motion stops in one frame —
the stoppers. Poses that are merely close but not intersecting have no manifold
at all — the pair that never moved.

**Fix** (`BaseVehicle.gd:1266-1363`): a displacement-budget clamp. Capture the
pose before the sweep; leave the sweep, slide and wall-bleed block byte-
unchanged; afterwards, undo any XZ travel exceeding what the caller actually
asked for (`|motion| * (1 + 0.001)`), proportionally. Y is untouched, so
vertical depenetration and `_settle_on_ground` still own ride height. A parked
vehicle's budget is exactly 0, so recovery-only drift is cancelled; a driven
vehicle never exceeds its own sweep, so collision and sliding are bit-identical.

The first attempt used an ABSOLUTE 1e-4 m per-frame slack and **failed
honestly**: drift fell from 23 m to 0.36 m but the tail was exactly 1e-4 every
frame in a fixed direction — bounded but never converging, the same bug 250×
slower. An absolute slack is just a budget the recovery spends. Relative slack
gives a parked vehicle zero budget.

**Complementary hardening:** `BuildMode.load_layout` now de-nests restored
vehicles (deterministic ring search, 8 rings × 12 angles at 1.5 m), warns naming
both vehicles and the offset applied, and **never drops a saved vehicle** — old
saves can no longer re-create the nested entry condition.

**Verified:** `test_nested_vehicle_drift` PASS — 6 nested clamps over 3600
frames: total XZ 0.0000 m, tail 0.0000 m, yaw 0.0000; a driven clamp still
collides with a wall at 0.000 m penetration; 4/4 saved vehicles restored with 0
overlapping pairs. Harness 15 ok / 0 fail / 2 skip.

**Behaviour change to know about:** a parked vehicle can no longer be shoved
aside by another vehicle driving into it — that shove was happening *through*
this recovery pass. Defensible for a braked machine, but it is a real change.

**Still open, logged not guessed:** something in a live BuildMode reaches
`_save_layout` -> `WorldLayout.save()` and bumps `world_layout.json`'s mtime
during tests; content stayed byte-identical and tests now backup/restore it,
but the trigger is unexplained and deserves its own pass — a BuildMode with
`load_shared_structure=false` would save an EMPTY structure list.

### P2. The unexplained `world_layout.json` write — found, and it was a live footgun

The drift fix flagged an unexplained writer of `world_layout.json` during
headless tests. Traced: `SaveCoordinator`'s 60 s autosave routes
`save_game` -> `BuildMode._save_layout` -> `WorldLayout.save()` (`:2664`).
Nothing mysterious — but what it exposed is:

`_save_layout` rebuilt the SHARED site structure (walls, doors, gates,
windows) from its own `_placed_root` children and wrote that list back
unconditionally. A BuildMode instance created with
`load_shared_structure = false` — test benches, the ExtruderGauntlet — never
instantiates those nodes, so its `shared` list is empty for reasons that have
nothing to do with the operator deleting anything. Combined with the autosave
timer, **any booted bench would have silently wiped the site's walls and doors
from `world_layout.json` on a timer, unattended.**

Note `structure_items` in the operator's current `world_layout.json` is already
`[]`. Whether that is because he never placed shared structure, or because this
already fired, cannot be told from the file alone — flagged rather than assumed.

Fixed: the shared write is now gated on `load_shared_structure`, so an instance
that never loaded the structure can never overwrite it.

## Q. Regression coverage added this session

`bash tools/regression/run.sh` now runs, on top of the existing 15 world/save
checks and the clamp-spawn gate:

| test | asserts the exact defect the operator hit |
|---|---|
| `test_map_frame` | player standing at the shell centroid renders INSIDE the drawn CEDO outline; a vehicle at the player's position projects onto the You marker (shared projection); outline mapping is rigid |
| `test_nested_vehicle_drift` | 6 nested clamps travel 0.0000 m over 3600 frames; a DRIVEN clamp still stops at a wall with 0.000 m penetration; de-nest on load leaves 0 overlapping pairs |
| `test_npc_target_guard` | absurd + non-finite waypoints refused, valid ones accepted, prior waypoint intact |
| `test_feeder_fetch` | tools never spawn at the worker's feet, rest at the pickup, the worker ARRIVES on foot (0 force-completions), holds the SAME instances, idempotent on re-pin |

Each keys off the printed verdict rather than the process exit code — Godot can
segfault in teardown after a clean PASS (observed exit 139 with every check ok),
and an exit-code gate would have reported that as a failure.

The point of writing these as harness steps rather than one-off runs: every
defect in this document was invisible to the previous harness, which is exactly
why they kept coming back.

## R. npc-05 was marked DONE on a vacuous green — corrected 2026-07-21

The backlog listed the container-emptying chain as **DONE** on the strength of a
bench printing **31/31 PASS**, including the headline
`S5 ledger balanced: 95 kg emptied == 95.00 kg received`.

That green was the test's own stub handing a number to itself. Verified by
running the chain in a REAL MainWorld boot — three independent stages, identical
result:

```
bin  275.00 -> 275.00 kg   (removed 0.00)
skip   0.00 ->   0.00 kg   (received 0.00)
```

**Nothing ever moved.** Four measured causes:

1. **Boarding deadlock.** `OperatorContext` called `npc.set_physics_process(false)`
   on board, but `OverflowDumpTask.tick()` is only reachable from
   `NPC._physics_process`. The task froze the instant it boarded — permanently,
   with `_phase_t` stuck at 0.0 so even the 90 s phase timeout could never fire.
   The forklift stayed `occupied` forever, jamming the idle-forklift gate for
   every future dump run in that session (`open=0 active=2` observed live).
2. **No vehicle could carry bulk.** `load_bulk` / `unload_bulk` existed ONLY in
   the task's `has_method` guards and in the bench's own stub — zero production
   implementations. Real session: source bin empties, skip gets `add(0.0)` which
   returns immediately. **Mass destroyed** — the mirror of §C's mass creation.
3. **Prune deleted in-flight tasks** — the generator returned before marking bins
   `seen`, so any occupied forklift erased the live task.
4. **Refused boardings still advanced the phase** (`NPC.gd` discarded the bool).

**Fixed and re-verified:** bench **81 ok / 0 fail**, and MUTATION-TESTED —
reverting each individual fix turns specific greens red, so no fix is unguarded.
Real world now moves **275.00 kg removed == 275.00 kg received**, twice
(autonomous claim, and the operator's own CrewPanel `force_task`). The boarding
guard measured 8970 of 8979 seated frames advancing the task clock.

**Still failing, stated not hidden:** with the shipped layout the forklifts park
205 m away and the autopilot jams against the perimeter fence at a repeatable
coordinate (-79.90, 157.14) — that is npc-06/npc-07 navigation work, already in
the backlog, and it was NOT papered over.

**Operator decision needed:** the npc-05 outdoor skip is measurably INDOORS
(up-ray hits roof 7.9 m above it) despite `ContainerGuide.gd` claiming "~7 m
outside the east-wing facade" — that comment is now corrected to the measurement.
Moving it to the geometrically correct yard position was A/B tested: the forklift
gets outside but wedges 6.95 m short and nothing moves, because navigation cannot
route it yet. It therefore stays indoors as a labelled assumption; one constant
(`ContainerGuide` offset) flips it back once npc-06 lands.

**The lesson, again:** a bench that mocks the thing under test proves the mock.
The bench now includes controls that FAIL when production code is stubbed —
including a static read of the real Forklift script chain, which is the check
that would have caught this on day one.

### R2. The harness could also report a FALSE RED

Found while wiring the npc-05 step: `run.sh` took the MAIN regression's process
exit code as the harness verdict (`code=$?`). Godot can segfault in **teardown**,
after every check has already passed — observed live as `done (exit 139)` on a
run whose own log read `Result: 15 ok, 0 fail, 2 skip`, with all six sub-steps
PASS.

That is the mirror of the vacuous-green problem and just as corrosive: a harness
that randomly reports red on a clean run teaches you to stop reading it, which is
how a real red gets ignored. The sub-steps were already verdict-based; the main
step now is too, and a post-verdict crash is reported as a `note  :` line rather
than a failure, so it stays visible without lying about the result.
