# CeDo Simulator — Full Runtime-Logic Audit

_2026-07-08. Deep behavioral audit (not compile/style): 9 subsystem reviewers → adversarial verify (25 of 32 raw findings survived; refuted ones dropped) → duplicate scan. Triggered because a file-level "state review" missed that **every save load force-starts the line**. No CRITICAL (crash/corruption) items; 11 HIGH, ~14 MED/LOW, 13 safe dead-code removals._

**Rule for all remediation: `.bak` first, edit, compile, `bash tools/regression/run.sh`, verify greens non-vacuous. NEVER hard-delete.**

---

## The three blast-radius themes

1. **Save/resume asymmetry** — runtime state that isn't persisted then is wrongly defaulted on load. (warm-boot, pre-shift bell, car pipeline, hand-built walls, e-stop.)
2. **HMI-to-sim desync** — panels that show/START/STOP state they never actually write to LineFlow (they *lie*).
3. **NPC spawn wiring** — one omission in `_spawn_npcs` collapses the whole role/zone crew model + autonomy gating.

---

## Bug 0 — Loading any save force-starts the whole line _(found first; the trigger)_
- **Where:** `MainWorld.gd:112` `_is_resumed_save = (not is_new_save)` → `MainWorld.gd:262` `mark_warm_boot()` → `LineFlow._init_plc():1331` `_plc.force_all_powered()`.
- **Failure:** every resumed load powers the entire line RUNNING, unconditionally — never checks if it was running when saved. Log-confirmed (`(resumed)` + `47 machines, 40 links` + `shift running: true`).
- **Fix (DESIGN CHOICE — needs your call):** **A)** cold-start on load, operator presses START (matches real plant); **B)** persist real run-state and only resume what was running.

## HIGH severity (11)

### 1. NPC spawn never sets `npc_id` — autonomy role filter permanently defeated
`NPCSpawner._spawn_npcs` (129+) never assigns `npc.npc_id`, so `NpcAutonomyBoard._role_of()` returns `""`, the role gate short-circuits, and e.g. shift-leader **Romain** gets handed EmptyLumpCart/BlowLeaves tasks that explicitly exclude him. Fix: `npc.npc_id = npc_id` at spawn.

### 2. NPC spawn never sets `npc_role` — zone posting + jam coverage collapse
Same site. Every worker has `npc_role==""` → `_zone_for("")=[]` → all posted with `sid=""` at spawn spot, jam responder tiers 1&2 never fire. **No worker mans its station at shift start.** Fix: `npc.npc_role = data["role"]` (same line as #1).

### 3. `NpcAutonomyBoard._find_main_world()` resolves null in-game — tasks go nowhere _(from the NPC deep-dive)_
`NpcAutonomyBoard.gd:315` returns null at runtime → `BlowLeavesTask`/`HoseSweepTask` waypoints fall back to raw plant-local coords (near-origin) → the NPC walks nowhere useful and times out after 120 s. **This is the "Pascal does nothing" you saw.** Fix: resolve MainWorld via `get_tree().current_scene` or a group tag.

### 4. Pre-shift resume never rings the shift bell
`ShiftClock.gd:440` — autosave (60 s, unconditional) inside the ~75 s pre-shift window persists negative `elapsed_seconds` but NOT `_pre_shift_bell_pending`. On reload the bell guard is false → `shift_started` never fires → crew stays idle in the canteen, player never gets boots/PPE. Fix: persist/restore `_pre_shift_bell_pending`.

### 5. Shift-car pipeline runs unconditionally on resume
`ShiftCarSpawner.gd:77` + `MainWorld.gd:140` — no `is_pre_shift()` guard. Mid-shift reload spawns a fresh Swift ~440 m south, **yanks Yassine out of his post**, spawns a duplicate player Swift, and hijacks the CabCamera. Fix: guard the drive-in on `is_pre_shift()`/`elapsed<0`.

### 6. One `occupied` flag → player keyboard drives every NPC vehicle
`BaseVehicle.gd:311` `on_npc_entered` sets the same `occupied` flag as the operator. Your WASD/forks/handbrake drive **both** your vehicle and any NPC-seated one in lock-step. (Also starves the NPC autopilot branch — #M5.) Fix: separate `npc_occupied` flag; gate human input on operator-occupancy only.

### 7. Hand-built walls vanish on reload
`PlaceableCatalog.build_wall():804` never sets `placeable_id` meta → `_save_layout` skips the wall → gone on next load. Fix: `body.set_meta("placeable_id", _active_id)`.

### 8. HANDBEDIENING per-section START/STOP is cosmetic
`HmiOverlay.gd:1112` `_on_manual_toggle` only flips a local dict used to color a lamp; never written to LineFlow. STOP the wash section in HAND mode → label flips, **line keeps running.** Fix: route to a LineFlow section setter.

### 9. Sorting-line startup force-starts feed belts on EVERY line
`SorteerlijnScope.gd:187` — `startup_completed` does a scene-wide `request_start()` on all `shredder_feed_belt` with no line filter. Commissioning 3A/3B also starts 3C/6. Fix: filter by scope's line.

### 10. CutterCompactor softstarter trip is permanently unrecoverable
`CutterCompactor.gd:326` — the only clearer `reset_breaker()` has **zero callers**; `reset()` restarts the disc but never clears the flags, so SCADA stays alarm-red "SOFTSTARTER TRIP" forever. Fix: wire `reset_breaker()` into the HMI reset (or clear flags in `reset()`).

### 11. EremaFaultRegistry reads fields that don't exist on ExtruderModel
`EremaFaultRegistry.gd:97` gates on `melt_temp_c`/`motor_overload_tripped`/`hopper_level_pct` etc. — real names are `melt_temp`/`melt_temp_setpoint`, others absent. Every guard is permanently false → EREMA-4001/4002/4003/5503/4101 **can never fire.** Fix: correct names + add missing model members.

### 12. Walkie→VoiceService voice connect fails on autoload order
`Walkie.gd:57` connects `voice_done` to VoiceService, but VoiceService is autoload #12 (after Walkie #6) → node doesn't exist yet → never retried. **All real TTS crew voice is dead every launch.** Fix: `call_deferred` the connect, or wire from `VoiceService._ready`.

## MEDIUM / LOW (latent or self-healing)
- **M1** E-stop auto-clear sets `feed_enabled=true` with no memory of operator's pre-estop STOP (`LineFlow.gd:1668`).
- **M2** MechDryer `residual_moisture_pct` is a one-way ratchet — drum stuck "dry" after first cycle (`MechDryerModel.gd:26`).
- **M3** `SiloLevelSensor` overflow signal fires ~60×/s (unused debounce var) (`SiloLevelSensor.gd:102`).
- **M4** Failed autonomy task never evicted from `_open_tasks` → target permanently unserviceable (`NpcAutonomyBoard.gd:145`).
- **M5** NPC-seated vehicle can't run its own autopilot (`occupied=true` starves it) — fixed with #6.
- **M6** Merlo ride-height stays elevated after dismount mid-lever → parked Merlo hovers (`Merlo.gd:119`).
- **M7** AUTOMAAT/HAND mode is local-only, never gates LineFlow feed/START (`HmiOverlay.gd:1108`).
- **M8** ShiftCarSpawner player-boarding call silently no-ops (the "wake in the Swift" intro never happens) (`ShiftCarSpawner.gd:111`).
- **M9** LaserFilter keeps loading from stale `lump_feed_rate` after extruder leaves RUNNING → phantom ΔP on a stopped line (`ExtruderMachine.gd:191`).
- **M10** WorldSetup point-undo doesn't clear `staff_parking`/`player_swift` in WorldLayout (`WorldSetup.gd:1187`).
- **L1** MerloP40 door E-handler may consume the boarding press (order-dependent) (`MerloP40.gd:720`).
- **L2** `reset_yard_bales` hard-writes layer/mask=1 ignoring stored meta (benign today) (`BaleYardManager.gd:459`).
- **L3** ShiftClock persists `is_active` but load discards it + unconditionally re-activates (write-only dead data) (`ShiftClock.gd:452`).
- **L4** Commissioning `save_game()` runs before SaveCoordinator exists → silent no-op (self-heals from autosave) (`MainWorld.gd:180`).

---

## Duplicates / dead code — 13 safe removals (`.bak` first, one at a time, compile+harness after each)

**Dead whole files** (grep-proven unreferenced): `src/data/surfaces/PhysicalSurface.gd`, `src/scenes/world/GeometryUtils.gd`, `src/scenes/world/FloorDetector.gd`, `src/scenes/world/OSMTerrainLoader.gd`, `src/scenes/vehicles/cars/FordStreetka.gd` **+** `.tscn` (as a pair).

**In-file dead logic (KEEP file, excise funcs):** `PlayerController.gd` orphaned `_capture_feedback_at_crosshair()` + `_feedback_timestamp` (~1648–1719) — superseded by MarkerTool.

**Loose-root scratch/artifacts:** `test_shredder_belt_updated.gd`, `benchmark_test.gd` + `benchmark_mock_container.gd`, `cache_test.gd`, `parse_check.log` + `parse_check2.log`, `line_connection_audit.csv` + `.import` + 8 `.translation` files, `test_gemini.py` + empty `python` file.

**Duplicate logic to merge (not delete):** 3 parallel "find extruder for line" resolvers in `HmiOverlay.gd` (473/2020/426); 2 hand-copied "nearest-in-group" loops (`HmiOverlay.gd:454` vs `ExtruderMachine.gd:81`).

**Do NOT remove** (`safe_to_remove=false`): `probe_cars.gd` (may be hand-run), root `test_conservation/test_crew/test_scada/test_settings_wiring` (name-dropped by newer tests).

---

## Remediation order (each = `.bak` → edit → compile → regression → manual check)

1. **NPCSpawner** `npc_id` + `npc_role` (one site, fixes #1 & #2) — do first, unblocks crew model.
2. ShiftClock pre-shift bell (#4) + is_active asymmetry (L3).
3. ShiftCarSpawner resume guard (#5) + boarding no-op (M8).
4. BaseVehicle occupancy split (#6 + M5).
5. Merlo ride-height (M6), MerloP40 door (L1).
6. build_wall placeable_id (#7).
7. HmiOverlay HANDBEDIENING (#8) + AUTOMAAT gating (M7).
8. SorteerlijnScope cross-line start (#9).
9. CutterCompactor reset (#10).
10. EremaFaultRegistry field names + model members (#11) — heaviest, isolate.
11. LineFlow e-stop clobber (M1), Mechdryer moisture (M2), Silo overflow (M3), Autonomy eviction (M4), LaserFilter stale lump (M9).
12. Walkie voice connect (#12).
13. WorldSetup undo (M10), BaleYard meta (L2), commissioning save (L4).
14. **Warm-boot (#0)** — pending your A/B design choice.
15. **_find_main_world (#3)** — do alongside the NPC cluster (step 1) since it gates task waypoints.
16. **Dead-code cleanup** last, one `.bak`+removal at a time with compile+harness between.
