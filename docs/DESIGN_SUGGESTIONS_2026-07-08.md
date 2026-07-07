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

### P2 — Motor pack-up: visible stall + smoke on drives already running `MotorOverload`  · effort S
- **Now:** `MotorOverload` **is** composed + ticked on mill/shredders/friction separators (`LineFlow.gd:661-671`) — correcting one reader's "test-only" note. But a trip surfaces only as an EventBus alarm + HMI number; nothing stalls or smokes.
- **Do:** on trip, force the `RotatingMechanism` rotor to coast to 0 (reuse its rpm ramp) + a short smoke/heat-shimmer burst at the motor housing.
- **Payoff:** a packed-up friction washer is a headline real-plant failure — makes it a floor event you run toward, not a gauge reading. Very high payoff for the effort; only the visual reaction is missing.
- **Files:** `MotorOverload.gd`, `LineFlow.gd`, `RotatingMechanism.gd`

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

### P6 — LumpCart overflow + end-of-line reject as visible floor mess  · effort S
- **Now:** `LumpCart.receive_lump` hard-caps and **silently drops** extra lumps (`:61-67`, comment admits it). `LineFlow._dump_waste` (`:2461`) silently loses reject past FloorPile max — a counter keeps the ledger balanced, the physical mess vanishes.
- **Do:** when the cart is full, spawn a `FloorPile` under the laser-filter discharge (same mechanism already used for chute overflow) so lumps pile up and demand you empty the cart. Reinforces "can't escape your shift."
- **Risk:** low; watch pile `max_radius` so ignored overflow doesn't wall you off (or make that intended, tunable pressure).
- **Files:** `LumpCart.gd`, `FloorPile.gd`, `LineFlow.gd`

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

### Q1 — Show which save is live + last-autosave time  · effort S · **high**
`save_file_path` is set at boot (`GameState.gd:35-41`) but never shown; autosave silently overwrites every 60 s. With ~18 saves you can't tell which is live. Add "Playing: `<name>` — last autosaved 14:32" to the pause header (+ optional HUD corner). `SaveCoordinator.gd`, `HUD.gd`.

### Q2 — Manual checkpoint / named quicksave before risky actions  · effort M · **high**
Only save paths are 60 s autosave (overwrites) + "save and quit." No way to branch a safe point before a BuildMode edit or wire cut without quitting. Add a pause-menu quicksave writing `<name>_checkpoint_<ts>_save.json` via the existing save path. `SaveCoordinator.gd`, `GameState.gd`.

### Q3 — Delete the paired `_factory.json` when deleting a save  · effort S · **high**
`MainMenu._delete_save_file` (`:135-154`) removes only `<name>_save.json`, never the paired factory sidecar — orphans accumulate and a re-created same-name save inherits a stale layout. Also unlink `SystemsSpawner._factory_layout_path(name)`. This is a hidden cause of the save clutter. `MainMenu.gd`, `SystemsSpawner.gd`.

### Q4 — In-game keybind cheat-sheet overlay  · effort M · **high**
Onboarding is one fixed string (`HUD.gd:207-216`) but the real control surface is huge and scattered (F4 camera, F3 perf, F10 markers, M map, walkie keys, Shift+B wire cut, freecam numpad). Add a hold-H help overlay reading the same keybind config the rebind tab uses. `HUD.gd`, `SettingsMenu.gd`, `CameraRig.gd`.

### Q5 — Map wayfinding: station names + HMI markers + crew names  · effort M · medium
`MapOverlay` labels machines by trimmed id only past `scale_px>3` (`:124-133`); crew are anonymous dots. Mirror the `HmiScopes` station names onto the map, mark machines with a real HMI, label crew dots. All data already on live nodes — draw-layer work. `MapOverlay.gd`, `HmiOverlay.gd`.

### Q6 — Signal real HMIs vs stub tiles  · effort M · medium
~8 stub tiles silently bail (`HmiOverlay.gd:342-347`) vs 5 real scopes — indistinguishable until you walk up and press E (wasted trips). Give real HMIs a world-space glow/[E] hint; make stubs show "not yet available." `HmiOverlay.gd`, `PlayerController.gd`.

### Q7 — Show camera mode on F4 + a reset-camera key  · effort S · medium
`CameraRig.mode_name()` exists but is never shown; `reset()` is only auto-called on vehicle enter. Flash a 2–3 s mode label on F4 (reuse the scanner banner) and bind `reset()` to a key (Home / F4 double-tap). `CameraRig.gd`, `HUD.gd`.

### Q8 — F10 markers: add shift-clock timestamp + a note field  · effort S · low
MarkerTool writes coords but no note (WHY) and no in-game time, so "glitched at 13:40" can't be reconstructed. Add `ShiftClock` time to `context.json` + a short typed note per capture. `MarkerTool.gd`, `ShiftClock.gd`.

---

## 3. Sequencing (tied to the 3B roadmap)

0. **Verify first:** confirm a loaded 3B save populates `LineFlow._nodes/_edges` with non-zero machines/links (regression boot showed 0/0). Nothing telemetry-driven has data until this is true.
1. **Wire the 3B vertical-slice flow chain** so every node has a live `MaterialBatch` `thru`.
2. **P1 (flake skin on belts)** → then **P4 (ballistic hand-off)** which piggybacks on it.
3. In parallel: **P2 (motor stall)** + **P3 (vacuum pot visual)** — both directly serve the "run Extruder 3B" milestone and are low-risk (models already tick).
4. **P8 (particle expansion)** last, starting with the compactor sub-slice.
5. **Q1/Q2/Q3 slot in immediately** regardless — cheap, high-priority, and they kill the save clutter that's slowing every 3B test iteration.
