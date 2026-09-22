# CeDo Simulator — State Audit + Improvement Suggestions

_Generated 2026-07-08. Grounded in a full read of `src/sim`, `src/scenes`, `src/build`. Every item cites real files._

---

## 0. State check (measured, not asserted)

| Check | Result |
|---|---|
| Headless compile | **Clean** — 0 `SCRIPT ERROR` / `Parse Error` |
| Regression harness (`tools/regression/run.sh`) | **15 ok / 0 fail / 1 skip** |
| — non-vacuous? | Yes: 33/33 machines inside footprint, fence 0-crossing **/ 3 segments**, 39 TL bars inside+rod-mounted, round-trip worst 0.000 m |
| Corrupt line_3a macro | Gone — no `macros/` dir; rebuilds from clean seed |
| Boot | `9 NPCs, shift running: true`; 3234 bales / 7 yards, 1 draw call each |

**Two housekeeping flags:**
1. **A full session is uncommitted** on branch `physics-vehicles-and-npc-autonomy`: 22 modified + 37 untracked (MarkerTool, the new floor/overflow tasks, the whole `tools/regression/` harness, F10 tests). It works, but commit it before more changes.
2. **Saves reappeared** (~18 pairs) after the 2026-07-07 wipe — mostly junk dev names. See QoL items below for the cleanup fixes.

---

## The one big insight

**The physicalization you're asking for is mostly already written — it's just never spawned/called.** Four systems exist in code and do nothing today:

- `FilmFlakeField.gd` has a **DRIFT mode + dunk paddles** and its own docstring says "attach to any wet/transport stage (belts, flotation, sink separator)" — but it's instantiated on **exactly one** machine (the flotation tank, `PlaceableCatalog.gd:4347`). Every other belt/washer/dryer shows invisible numbers.
- `BeltSurface.gd:120-186` has a **full ballistic arc + scatter model** for flake thrown belt-to-belt — **zero callers**. Transfers teleport.
- `CutterCompactor.gd` computes a **real, mass-conserving discharge** of crumb — then `LineFlow.gd:2206` **discards it** (`# discard`).
- `MaterialBatch.gd:8-10` promises a discrete-hybrid **particle expansion at cyclones/shredders/compactor** — **no code implements it.**

So a lot of the "make it physical" work is wiring, not inventing.

**Caveat to verify first (measure, don't assert):** the regression boot logged `[LineFlow] 0 machines, 0 links`. That may just be the regression world not registering the flow graph — but **confirm a loaded 3B save actually populates `LineFlow._nodes/_edges` with live `thru` telemetry** before building any skin on top, or the skins will have no data to read.

---

## 1. Physicalization / simulation (ranked)

### P1 — Reuse `FilmFlakeField` DRIFT mode on belts + wet stages  · effort M
- **Now:** flake visible only in the float tank; `LineFlow._find_film_field` (`LineFlow.gd:1256`) returns null everywhere else.
- **Do:** spawn a `FilmFlakeField` (DRIFT) child in group `film_field` on each conveyor/wet placeable, driven by the node's existing `thru` via the already-wired `set_live_state` (`LineFlow.gd:1822`). No new conservation math — flakes are a read-only skin like the float raft.
- **Payoff:** converts the entire belt network from "spinning rotors only" to visibly flowing film, using code that already renders.
- **Risk:** MultiMesh cost across many belts → reuse the float field's instance cap + distance cull. DRIFT mode has never run in prod; expect first-use orientation bugs.
- **Files:** `FilmFlakeField.gd`, `PlaceableCatalog.gd`, `LineFlow.gd`

### ~~P2~~ — Motor pack-up: the trip now really stops the drive — **DONE 2026-09-23 (stall half); smoke deliberately NOT built**
- **What was actually wrong was worse than "no visual":** measured with `test_motor_trip_stops_conveying` before the fix, a tripped drive kept **conveying at its full design rate** (shredder-2: 0.061 kg per 0.1 s tick, 1.894 kg over 3.1 s "tripped"), its rotors stayed commanded at 45 rpm, `spin` stayed 1.0, and the bunker/shredder-2 interlock moved 31 kg in the same window. Only `powered` (read at the END of a tick) and the 0 A readout showed the trip. Cause: `_tick_plc_power_downstream` wrote `powered=true` from the PLC at the top of every tick and ran the spin/mechanism ramp from it; the trip only dropped `powered` in `_tick_advanced_systems`, which runs AFTER `_tick_process_machines` has conveyed.
- **Fix:** `LineFlow._apply_trip_latches()` runs inside the PLC step, after the PLC/HAND-mode writes and before the ramp: any node whose `mol.is_tripped()` gets `powered=false`, and the bunker/shredder-2 interlock is applied there too. A latched relay is a dropped-out contactor — HAND mode bypasses the PLC, not the motor protection. The rotor now coasts to 0 through `RotatingMechanism`'s existing ramp (no new visual code needed — the ramp was always there, it was just never told to stop), the machine node's own `set_running(false)` is called while latched, material backs up in the buffer (conserving), and `reset()` restores everything. 28 checks, wired in `run.sh`; pre-fix run 20 ok / 8 fail.
- **Smoke / heat-shimmer: not built, on purpose.** A thermal-overload relay dropping out does not make a motor smoke; modelling smoke would be Rule 1 (no build without docs) — there is no operator photo or statement of what a packed-up drive looks like beyond "it stops". If the operator says the real ones smoke, that is a 20-line particle burst on the housing; until then the floor event is the rotor stopping plus the existing alarm + 0 A.

### P3 — Extruder vacuum pots: visible fill + lid-pop + gunk + `clean_vacuum_lines()` as hold-E  · effort M
- **Now:** `ExtruderModel` fully models `pot_fill_kg` → 18 kg cap → lid open → the signature **120 s VACUUM_ALARM cascade**, plus `vacuum_line_gunk_kg` → a `clean_vacuum_lines()` hook that's **unwired**. All HMI numbers.
- **Do:** real pot vessels with a rising level + a lid mesh that pops on alarm; a growing gunk deposit; wire `clean_vacuum_lines()` to a hold-E maintenance interaction (mirror `PelletizerKnifeReplace`).
- **Payoff:** the extruder is your 3B milestone machine and this is its signature failure — turn it from a number into a level you watch climb.
- **Risk:** low technically (model already drives it); needs real pot geometry (photo/spec — no-build-without-docs).
- **Files:** `ExtruderModel.gd`, `ExtruderMachine.gd`, `PelletizerKnifeReplace.gd`

### P4 — Belt-to-belt ballistic hand-off (wire the zero-caller helper)  · effort S
- **Now:** `BeltSurface.compute_belt_to_belt_landing` + `apply_belt_spread` (`:120-186`) — full projectile + scatter — has no callers.
- **Do:** at each belt→belt edge, emit a few arcing flake instances using these functions so material leaves one deck and lands on the next. Piggybacks on P1.
- **Payoff:** removes the "material teleports at transfers" feel — exactly where the eye looks. Math is done.
- **Files:** `BeltSurface.gd`, `LineFlow.gd`, `MachineFlow.gd`

### P5 — Silo/buffer level as a visible rising column  · effort M
- **Now:** `SiloLevelSensor` reads `level_pct` and drives the bridge/surge mechanic (`LineFlow.gd:2122`) but the flake inside the silo isn't drawn. FloorPile cones + WasteContainer mounds are the only visible accumulation.
- **Do:** a single scaled heap/MultiMesh inside each silo whose height tracks `level_pct` (reuse FloorPile cone growth). Tint/animate past `HIGH_LEVEL_PCT` so surge risk is readable across the floor.
- **Risk:** low — one mesh on an existing 0..1 signal; may need a cutaway/gauge window if silo bodies are solid.
- **Files:** `SiloLevelSensor.gd`, `FloorPile.gd`, `MachineFlow.gd`

### ~~P6~~ — LumpCart overflow as visible floor mess — **DONE 2026-09-23 (cart half); the `_dump_waste` half is still open**
- **Measured before:** `LumpCart.receive_lump()` returned at `is_full()` and dropped the kg; its own comment claimed "the upstream filter will see is_full() and stop pushing" — nothing in `LaserFilter` ever read `is_full()`. `lumps_kg_this_shift` counted kg that existed nowhere. The cart also never showed its load: settled chunks were freed on absorption, so a 90 kg cart looked empty.
- **Now:** `receive_lump()` returns the refused kg (accepting up to `CAPACITY_KG` = 100 — the operator's "small heap over the rim" past the 90 kg `is_full` point); `LaserFilter._disc_advance()` puts refused kg — and the kg of a nozzle with no cart under it — into ONE soft `FloorPile` per nozzle straight under the nozzle, i.e. around the cart's base. Conservation is asserted: shed == voor cart + floor + lost. A visible heap (`LumpHeap`, a box measured from the cart's own collision plate and walls, never from the catalog's constants) rises with `lumps_kg`, reaches the rim at 90 kg, stands over it at 100, and is tinted hot→cool on the cart's own cool-down clock. A full cart no longer swallows settled chunks (they stay as overflow, litter-capped). `LumpCart._now_sim_s()` also stopped running a whole-tree `find_child` per call (it is polled per cart by the autonomy board) — the ShiftClock is cached once.
- **Why the mound is SOFT and sits under the nozzle:** the first draft put a solid pile beside the cart; `test_lump_cart_overflow` S9's shape query found the achter side of lines 1, 3A and 3B entirely inside the extruder's 14 m collider (the cart stands on its bordes between filter and extruder), and a solid pile there would also have walled off the forklift's approach to the cart. Lumps that overflow a cart heap over the rim and slide down its sides, so the mound now grows around the cart's own footprint with its collider off (`FloorPile.solid = false`) — a StaticBody3D inside a RigidBody3D cart's footprint ejects the cart. Its 400 kg/m³ bulk density is a stated assumption (solid LDPE ~920 kg/m³, ~40 % packing of 70 mm rope chunks). Not persisted across save/load — the same gap LineFlow's chute piles have.
- **Still open — `LineFlow._dump_waste` past a maxed FloorPile:** reject is still "silently lost at this layer" with only the counter. The honest model is that the machine cannot discharge and backs up (a maxed pile stops the line until shovelled), which changes the throughput every conformance suite measures — deliberately not done unattended.
- **Guard:** `src/tests/test_lump_cart_overflow.tscn`, 45 checks, wired in `run.sh`. Two of its early reds were the suite catching the change itself: a 1.25 cm rim error (the catalog's wall boxes overlap the floor plate by half its thickness) and the beside-the-cart placement above.

### P7 — Physicalize the sellable output (pellets at the pelletizer + weigh-batch)  · effort M
- **Now:** the whole pelletizer train turns melt → granulaat purely as `MaterialBatch` mass arriving at `role='sink'` nodes. No pellets, no weigh batches, no big-bag fill.
- **Do:** a pellet stream at the die (short-lived granules / MultiMesh fall) driven by sink throughput; the weegschaal as a fill-to-target-then-tip weigh batch — the number your shift is measured by. Pelletizer already has a knife-wear model, so good vs defective pellets could be tinted.
- **Files:** `MachineFlow.gd`, `ProcessModel.gd`, `PelletizerModel.gd`

### P8 — Discrete-hybrid particle expansion at shredder / cyclone / compactor  · effort L
- **The core promise of `MaterialBatch.gd:8-10`, currently unimplemented.** Biggest scope item.
- **Do:** LOD-gated (near-operator only) — shredder discharge bursts flake/chips scaled to `thru`; cyclone splits light-fines-updraft vs heavies-fall matching its airsep coefficients; compactor shows loose flake in → dense crumb out. Re-snapshot into the numeric batch on exit so conservation is untouched.
- **Start with the compactor** — `CutterCompactor` already computes the conserving discharge that's being discarded; reusing it is the safest first slice.
- **Files:** `MaterialBatch.gd`, `MachineFlow.gd`, `CutterCompactor.gd`, `LineFlow.gd`

---

## 2. Quality of life (ranked)

### ~~Q1~~ — Show which save is live + last-autosave time — **DONE** (landed before 2026-09-22, verified that date)
Closed via a HUD toast (`HUD._on_autosave_completed`, commit `091b231`), not the pause-header line this item originally proposed — "✓ Opgeslagen — `<name>` HH:MM" on every save, fades after 2.5 s. The pause-menu card itself still shows no save name/time, so if the operator wants to check after the toast fades they still can't — a real but much smaller residual gap than the original "never shown at all."

### Q2 — Manual checkpoint / named quicksave before risky actions  · effort M · **high**
Only save paths are 60 s autosave (overwrites) + "save and quit." No way to branch a safe point before a BuildMode edit or wire cut without quitting. Add a pause-menu quicksave writing `<name>_checkpoint_<ts>_save.json` via the existing save path. `SaveCoordinator.gd`, `GameState.gd`.

### ~~Q3~~ — Delete the paired `_factory.json` when deleting a save — **DONE** (landed before 2026-09-22, verified that date)
`MainMenu.gd` (commit `091b231`, tagged `#audit-Q3`) now deletes the paired `_factory.json` sidecar right after the save, via `AtomicFile.delete()` (also strips `.bak`/`.tmp`).

### Q4 — In-game keybind cheat-sheet overlay  · effort M · **high**
Onboarding is one fixed string (`HUD.gd:207-216`) but the real control surface is huge and scattered (F4 camera, F3 perf, F10 markers, M map, walkie keys, Shift+B wire cut, freecam numpad). Add a hold-H help overlay reading the same keybind config the rebind tab uses. `HUD.gd`, `SettingsMenu.gd`, `CameraRig.gd`.

### Q5 — Map wayfinding: station names + HMI markers + crew names  · effort M · medium
`MapOverlay` labels machines by trimmed id only past `scale_px>3` (`:124-133`); crew are anonymous dots. Mirror the `HmiScopes` station names onto the map, mark machines with a real HMI, label crew dots. All data already on live nodes — draw-layer work. `MapOverlay.gd`, `HmiOverlay.gd`.

### ~~Q6~~ — Signal real HMIs vs stub tiles — **CLOSED BY ELIMINATION** (verified 2026-09-22)
Not fixed by the suggested UI change — closed instead by the 2026-08-15 HMI retirement (`CLAUDE.md`'s "exactly 12 HMI panels" section): the two generic/cosmetic stub ids that used to open a plant-wide "generic" scope were deleted outright, so there is no stub tile left to be fooled by — every placeable HMI is now one of the 12 real, fully-scoped panels. Residual, lower-stakes gap: no world-space glow/beacon exists for real HMIs at a distance, so discovery still means walking into the ~4×3×4 m proximity box.

### ~~Q7~~ — Show camera mode on F4 + a reset-camera key — **DONE 2026-09-22**
`CameraRig.cycle_mode()` now flashes "Camera: `<mode>`" via the scanner banner (through a `/root`-lookup helper, not a bare `EventBus` reference — this file is loaded standalone by `test_camera_rig_*.gd`, which has no autoloads). Reset is bound to **F4 double-tap** (350 ms window), not Home — Home is already `BuildMode`'s Sequential Line Builder toggle (`BuildMode.gd:1517-1518`, an unconditional `_input` that runs before `_unhandled_input` and would have silently eaten the key). Verified via the existing `test_camera_rig_active`/`test_camera_rig_set_first_person_camera` suites (still green) plus a full-tree parse sweep; not verified in a live play session (no in-game visual confirmation of the banner text/timing).

### Q8 — F10 markers: add shift-clock timestamp + a note field  · **half done 2026-09-22**
Shift-clock time landed: `MarkerTool._shift_time_string()` writes `shift_time` into both `markers.json` and `context.json` (lazy `/root` lookup, null-safe — `ShiftClock` is not an autoload and genuinely doesn't exist in bench/probe scenes). **The typed-note field is still open by design choice, not oversight**: it needs a focus-grabbing text-input UI layered onto a tool that otherwise owns all keyboard/mouse input for 3D placement (LMB/G/H/RMB), and that interaction can't be verified without a live play session — shipping it unverified would be exactly the "bench green proves the mock" mistake this repo's Rule 3 warns about. `MarkerTool.gd`.

---

## 3. Sequencing (tied to the 3B roadmap)

0. **Verify first:** confirm a loaded 3B save populates `LineFlow._nodes/_edges` with non-zero machines/links (regression boot showed 0/0). Nothing telemetry-driven has data until this is true.
1. **Wire the 3B vertical-slice flow chain** so every node has a live `MaterialBatch` `thru`.
2. **P1 (flake skin on belts)** → then **P4 (ballistic hand-off)** which piggybacks on it.
3. In parallel: **P2 (motor stall)** + **P3 (vacuum pot visual)** — both directly serve the "run Extruder 3B" milestone and are low-risk (models already tick).
4. **P8 (particle expansion)** last, starting with the compactor sub-slice.
5. **Q1/Q2/Q3 slot in immediately** regardless — cheap, high-priority, and they kill the save clutter that's slowing every 3B test iteration.
