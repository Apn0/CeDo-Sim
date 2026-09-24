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

### ~~P1~~ — Film on the belts — **DONE 2026-09-23 (belt half); wet stages queued**
- **Operator input first (Rule 1):** two AskUserQuestion rounds, recorded in `docs/plant/operator_rulings_2026-09-23.md` — mixed sizes ("small flake to long strips"), colour order white > blue (many shades) > other > black, bed depth "varies per belt" (3A/3B intake carries ~2× line 1's material at 1.5× speed; the compactorband is heaped 20 cm+ and creeps at ~4 cm/s), wet flake is "the same flake, wet and darker", and on the look: "flakes only — but is that too heavy? Then use the method Gold Mining Simulator uses for the soil, with film as the texture".
- **Now:** every BeltBuilder deck (transport_belt, transportband 1-12, switch_belt, and — through `attach_film_field` — the compactorband and inclined_belt_8m) carries a `FilmFlakeField` in **belt mode**. The bed's depth is DERIVED: kg/m = LineFlow's `thru` ÷ the deck's `belt_speed`, depth = kg/m ÷ (bulk density × width). It is drawn as a rounded, lumpy HEAP mesh (unit height, scaled to the depth) wearing a procedural film texture (cellular noise coloured in his shares, normal-mapped, scrolling downstream) plus a dense flake layer (~120 per m²) that a vertex shader scrolls, wraps and lifts by the live depth — instance transforms are written once, so the CPU does nothing per flake. A stopped deck holds its bed; a moving starved deck drains over its transit time. LineFlow drives it from the PLC step (`set_belt_state`); the flotation raft keeps the old CPU path. Guard `test_belt_film_field` (142 checks, in `run.sh`); renders `docs/plant/renders/shot_belt_bed_*.png`.
- **Found on the way:** `inclined_belt_8m`'s 11 m deck was rotated +45° about X, which in Godot sends the +Z end DOWN — it ran the opposite diagonal to its own rollers and A-frames (`shot_belt_bed_inclined_belt_8m_before.png`). Fixed to −angle, rails on the deck's normal; the suite pins it. And the compactorband ran at the generic 0.4 m/s; it now creeps at `COMPACTORBAND_SPEED_MPS` = 0.04 (carry, rollers, bed).
- **Cost, measured** (`probe_belt_field_cost`, 24 intake belts, headless = no distance cull): bare 37 µs/frame for all 24 fields, thin beds (6404 flakes) 78 µs, full beds (14259 flakes) 75 µs, stopped 24 µs — ~3 µs per field per frame; the first draft's CPU-animated flakes had cost 1020 µs for 3567.
- **Still open:** the wet side he named (scheidingsgoot, Kufferath sieve, dewatering screw trough — same textured method, queued as the next slice); which transport screws are open ("differs per screw"); the belt-speed CONFLICT (his 1.5 m/s for the intake belts vs the catalog's "operator-confirmed 0.4–0.6" — not applied, needs one explicit answer); the ShredderFeedBelt-scene belts (`drum_feed_belt` carries snippers, no bed); `metal_belt` / `scraper_conveyor` / `compactor_belt`. P4's hand-off can now piggyback on the beds.
- **Files:** `FilmFlakeField.gd`, `BeltBuilder.gd`, `PlaceableCatalog.gd`, `LineFlow.gd`, `test_belt_film_field.gd`, `probe_belt_field_cost.gd`, `probe_deck_orientation.gd`, `shot_belt_bed.gd`

### ~~P2~~ — Motor pack-up: the trip really stops the drive — **DONE 2026-09-23 (both halves: the stall in the morning, the smoke in the evening)**
- **Smoke (evening, operator ruling §5):** "Visible smoke sometimes" — "Heavy smoke, people react". On a MotorOverload trip edge, with `LineFlow.smoke_chance` (0.35, a stated assumption for "sometimes"), the machine's `SmokePlume` — installed on demand at its first motor housing (`PlaceableCatalog.install_smoke_plume`, the dark/dense variant of the steam plume) — emits for `SMOKE_S` = 25 s and a `SMOKE` alarm (severity 3) goes out; `CrewManager` radios it and dispatches a responder, and the autonomy board's storing-fixen path picks it up as a storing. Guard `test_trip_smoke` (21 checks, in `run.sh`).
- **What was actually wrong was worse than "no visual":** measured with `test_motor_trip_stops_conveying` before the fix, a tripped drive kept **conveying at its full design rate** (shredder-2: 0.061 kg per 0.1 s tick, 1.894 kg over 3.1 s "tripped"), its rotors stayed commanded at 45 rpm, `spin` stayed 1.0, and the bunker/shredder-2 interlock moved 31 kg in the same window. Only `powered` (read at the END of a tick) and the 0 A readout showed the trip. Cause: `_tick_plc_power_downstream` wrote `powered=true` from the PLC at the top of every tick and ran the spin/mechanism ramp from it; the trip only dropped `powered` in `_tick_advanced_systems`, which runs AFTER `_tick_process_machines` has conveyed.
- **Fix:** `LineFlow._apply_trip_latches()` runs inside the PLC step, after the PLC/HAND-mode writes and before the ramp: any node whose `mol.is_tripped()` gets `powered=false`, and the bunker/shredder-2 interlock is applied there too. A latched relay is a dropped-out contactor — HAND mode bypasses the PLC, not the motor protection. The rotor now coasts to 0 through `RotatingMechanism`'s existing ramp (no new visual code needed — the ramp was always there, it was just never told to stop), the machine node's own `set_running(false)` is called while latched, material backs up in the buffer (conserving), and `reset()` restores everything. 28 checks, wired in `run.sh`; pre-fix run 20 ok / 8 fail.
- **Smoke / heat-shimmer: not built, on purpose.** A thermal-overload relay dropping out does not make a motor smoke; modelling smoke would be Rule 1 (no build without docs) — there is no operator photo or statement of what a packed-up drive looks like beyond "it stops". If the operator says the real ones smoke, that is a 20-line particle burst on the housing; until then the floor event is the rotor stopping plus the existing alarm + 0 A.

### P3 — Extruder vacuum pots — **stage A DONE 2026-09-23 (visible fill, lid pop, gunk); stage B is an operator MINI-GAME, not a hold-E**
- **Operator 2026-09-23 (rulings §14):** "I have never held any E's inside the factory." The cleaning is a mini-game: pull the lid (stuck harder the longer the vacuum has been off), clear every inner plane with a plamuurmes (top, bottom, left, right; the tool is narrower than a plane; a push may only go halfway), ≥ 90 % per plane for now, then the melt block drops a centimetre and comes out BY HAND to be placed or thrown anywhere; laser-filter trouble clogs the primary pot, head-filter trouble the secondary; lid back, seal good, restart; within ~2 minutes of the alarm the extruder keeps running, past it everything on the extruder shuts down and a different HMI alarm names the laser-filter error. `ExtruderModel`'s 120 s cascade already matches the two minutes.
- **Stage A (built):** on the domes his 2026-07-20 photos gave the model, each pot has a `VacPot_<primary|secondary>` root: the sight glass is now a proud witness port (the flat disc showed nothing — same lesson as the silos), a `Lid` disc that lifts 12 cm and tilts when the pot is at capacity (the model's own "vacuum_lid_pushed_open" trigger), a `Gunk` deposit at the riser scaled by `vacuum_line_gunk_kg` over the dismantle threshold. `PlaceableCatalog.set_vacuum_pot_state` drives it; `ExtruderMachine._drive_pot_visual` calls it every frame from the model (roots cached; a bench body without pots switches the drive off). Guard `test_vacuum_pot_visual` (22 checks, in `run.sh`); renders `docs/plant/renders/shot_vacuum_pots_*.png`. EREMA process facts and sources in the rulings doc.
- **Stage B (queued; designed):** `docs/DESIGN_vacuum_pot_minigame_2026-09-23.md` — the lid grab, the plane-clearing mini-game with the plamuurmes as a hand tool, the block as a carryable, the re-lid/seal check, the two-minute race, with his parameters separated from placeholders and a headless test strategy.
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

### ~~P5~~ — Silo/buffer level as a visible level — **DONE 2026-09-23 (both halves), on the windows the operator described**
- **Docs check first (Rule 1):** the compactor's kijkglas is SWI-012 p7 step 6 (built 2026-09-23 morning). The silos were asked in the interactive session (`docs/plant/operator_rulings_2026-09-23.md` §3/§9): the VSS has nothing; the **doseersilo** has two ~30 × 30 cm square windows 90 cm apart, centred along the tank, on both long sides; the **mengsilo** one 15 × 15 cm window a third of the way up on one side; the **extruder silo** four vertical windows per LONG side, each in the inner sub-quadrant of its quadrant, not touching. All built to those numbers; guard `test_silo_level_windows` (50 checks, in `run.sh`); renders `docs/plant/renders/shot_silo_level_*.png`.
- **How a level shows through an opaque shell:** it does not — rendered at 33 % pot load the morning's kijkglas showed a grey door plate, and the mengsilo's old vertical strip never showed anything. Every sight glass is now a proud port (`PlaceableCatalog._level_window`): a steel ring 7 cm off the wall, the transparent gauge glass at its outer end, a dark back plate, and a `LevelWitness` slab in between that `set_silo_fill()` sizes from the window's bottom edge up to the live level (kept horizontal on the doseersilo's sloped trough wall by a per-window y-scale). `SiloFill` roots carry the silo's level range; LineFlow drives them every tick from the node's input batch against `SILO_FULL_KG` (= the VSS's 150 kg "full" convention — the sim's silos are kg-scaled, not the real m³). The compactor's `set_pot_fill()` drives its port the same way.
- **Also on the extruder silo:** the #98/#99 windows on the SHORT faces are gone (his ruling: long sides), ribs 1 and 2 with them (they cut through the new rows), and the #89 static "flake pile" glued behind the old ports is gone — a level that never moved was the invented visual Rule 1 forbids.
- **Files:** `PlaceableCatalog.gd` (`_level_window`, `_silo_fill_root`, `set_silo_fill`, `_window_port`, the three silo builders, the compactor kijkglas), `LineFlow.gd` (`silo_fill` per node, `SILO_FULL_KG`), `test_silo_level_windows.gd`, `shot_silo_level.gd`

### ~~P6~~ — LumpCart overflow as visible floor mess — **DONE 2026-09-23 (cart half); the `_dump_waste` half is still open**
- **Measured before:** `LumpCart.receive_lump()` returned at `is_full()` and dropped the kg; its own comment claimed "the upstream filter will see is_full() and stop pushing" — nothing in `LaserFilter` ever read `is_full()`. `lumps_kg_this_shift` counted kg that existed nowhere. The cart also never showed its load: settled chunks were freed on absorption, so a 90 kg cart looked empty.
- **Now:** `receive_lump()` returns the refused kg (accepting up to `CAPACITY_KG` = 100 — the operator's "small heap over the rim" past the 90 kg `is_full` point); `LaserFilter._disc_advance()` puts refused kg — and the kg of a nozzle with no cart under it — into ONE soft `FloorPile` per nozzle straight under the nozzle, i.e. around the cart's base. Conservation is asserted: shed == voor cart + floor + lost. A visible heap (`LumpHeap`, a box measured from the cart's own collision plate and walls, never from the catalog's constants) rises with `lumps_kg`, reaches the rim at 90 kg, stands over it at 100, and is tinted hot→cool on the cart's own cool-down clock. A full cart no longer swallows settled chunks (they stay as overflow, litter-capped). `LumpCart._now_sim_s()` also stopped running a whole-tree `find_child` per call (it is polled per cart by the autonomy board) — the ShiftClock is cached once.
- **Why the mound is SOFT and sits under the nozzle:** the first draft put a solid pile beside the cart; `test_lump_cart_overflow` S9's shape query found the achter side of lines 1, 3A and 3B entirely inside the extruder's 14 m collider (the cart stands on its bordes between filter and extruder), and a solid pile there would also have walled off the forklift's approach to the cart. Lumps that overflow a cart heap over the rim and slide down its sides, so the mound now grows around the cart's own footprint with its collider off (`FloorPile.solid = false`) — a StaticBody3D inside a RigidBody3D cart's footprint ejects the cart. Its 400 kg/m³ bulk density is a stated assumption (solid LDPE ~920 kg/m³, ~40 % packing of 70 mm rope chunks). Not persisted across save/load — the same gap LineFlow's chute piles have.
- ~~Still open — `LineFlow._dump_waste` past a maxed FloorPile~~ — **DONE 2026-09-23 (evening), on the operator's ruling §4: "The machine chokes and stops" — "Shovel, then reset on the HMI".** `_dump_waste` returns the refused kg; the caller puts it back into the machine (ledger closed, incl. the wash water a washer takes on) and the node CHOKES: latched like a trip (`_is_trip_latched`), power off, rotor down, one `CHUTE-BLOCKED` alarm, the refusing pile remembered. `CrewManager._relieve` on a choked node shovels that pile (`SHOVEL_KG`); `LineFlow.reset_choke(id)` refuses while the pile is over `CHOKE_CLEAR_FRAC` and takes after; the HMI's RESETTEN calls it for its scope. A choke survives a LineFlow rebuild. Guard `test_chute_choke` (24 checks, in `run.sh`). Measured on the way: a rebuild gives the line a fresh idle PLC, so a machine that was off at rebuild time needs the line started again after its reset — as on the real HMI.
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

### ~~Q2~~ — Manual checkpoint / named quicksave before risky actions — **DONE 2026-09-23**
`SaveCoordinator.save_checkpoint()` (pause card → **Checkpoint** button, between Save and Save & Quit; `MainWorld.save_checkpoint()` forwards like the other two). It saves the live slot first, then copies `<stem>_save.json` and the `<stem>_factory.json` sidecar to `<stem>_cp_<YYYYMMDD-HHMMSS>_save.json` / `_factory.json` through `AtomicFile`, so the main menu lists the checkpoint as its own loadable save with its own `saved_at`. Same-second stamps get `-2`, `-3` … instead of overwriting; a failure (no GameState, live save unreadable, copy error) returns `""`, writes nothing and never touches the live slot; the HUD banner names the copy or says it was NOT written. The original proposal's `_checkpoint_<ts>` naming became `_cp_<stamp>` so the stem stays readable in the menu's list. Guard: `test_save_checkpoint` (22 checks — byte-equal copies, stamp collision, no-GameState negative, no-sidecar case, cleanup proven), wired in `run.sh`. Not verified in a live session: the button's placement on the pause card (see the audit doc's operator list).

### ~~Q3~~ — Delete the paired `_factory.json` when deleting a save — **DONE** (landed before 2026-09-22, verified that date)
`MainMenu.gd` (commit `091b231`, tagged `#audit-Q3`) now deletes the paired `_factory.json` sidecar right after the save, via `AtomicFile.delete()` (also strips `.bak`/`.tmp`).

### ~~Q4~~ — In-game keybind cheat-sheet overlay — **DONE 2026-09-23, on F1 (not H)**
`src/scenes/hud/KeybindSheet.gd`, built by HUD, toggled with the new `help_overlay` action (F1; ESC or F1 closes). H — this entry's first pick — is the vehicle handbrake and the marker tool's clear key; F1 was bound nowhere (grepped). Content is `KeybindSheet.build_rows()`: every action in `SettingsManager.ACTION_GROUPS`, in group order, with the Controls-tab label's first line and the LIVE InputMap binding formatted as the tab does (`F4`, `Left mouse`, `Pad btn 3`), rebuilt on every open so a rebind shows without a restart. Does not pause the shift or take the mouse. **Found on the way:** the six actions `PlayerController` registers lazily in its own `_ready` (`sprint`, `fast_run`, `feedback_capture`, `opening_capture`, `debug_fill_silo`, `debug_force_fault`) did not exist in the InputMap until a player spawned, so the main menu's Controls tab (and the sheet) showed "—" for keys that work; they are now registered in `SettingsManager._ensure_aux_actions` with the same physical keycodes (Alt for `fast_run` stays debug-build-only, as before). Guard: `test_keybind_sheet` (24 checks — one row per tab action, keys == InputMap, every tab action bound at boot, F1 owned by `help_overlay` alone, 150 rendered Labels for 69 actions in 10 groups, follows a runtime rebind), wired in `run.sh`. Not verified in a live session: the sheet's layout at real window sizes (the scroll panel clamps to 90 % × 75 % of the viewport).

### ~~Q5~~ — Map wayfinding: station names + HMI markers + crew names — **DONE 2026-09-23**
`MapOverlay` now labels machines with the catalog's display name (the Dutch operator vocabulary — `machine_label_for("lump_cart")` → "Lumpenwagen", cut at the first " (" / " — "; an id the catalog does not know falls back to the trimmed id as before), names each crew dot (`crew_label_for`: `NPC.npc_name`, capitalised) in the dot's own colour, and draws every placed HMI panel (group "hmi") as a violet diamond with its scope label (`Hmi.scope_label()`, e.g. "Shredder lijn 1"; an inert panel reads "HMI"), plus an "HMI panel" legend row. Labels obey the existing zoom gate (`scale_px > 3`) and the overlap-dropping label collision list, so the 2026-07-20 "unreadable pile of text" cannot come back. Guard: `test_map_labels` (real MainWorld boot for the crew, two real catalog HMI panels, a zoomed redraw), wired in `run.sh`. Not verified live: legibility of the violet on the panel and whether crew names should show at the default 90 m radius (they show from ~28 m in).

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
