# CeDo Simulator — Fixed (non-line) equipment inventory & F10 marking checklist

Derived from a documentation study (water circuits, site georeference, reference photos) + adversarial verification against `PlaceableCatalog.gd`. **De-fabricated**: several source docs a study agent cited (`silos_ms_ls.md`, `eop_rafter.md`, `water_small.md`) and an "outdoor silopark coordinate" do NOT exist in the repo and were removed.

## How to use this
The docs describe each installation's location by **area/relationship**, not coordinates — so every item needs a spot pinned in-game before it can be placed. Workflow: **F10-mark** the location (LMB drops an orb, G snaps to a wall edge, RMB saves) → say "check feedback" → I read `markers.json` and write a persistent entry `{id,x,y,z,rot_y,h}` into `user://<save>_factory.json` (round-trips through `BuildMode.build_node`).

**56 items** have a ready catalog model. **5 items** have no model (see bottom — do not invent, needs photo/spec).

## Ready to place (catalog model exists) — mark each spot with F10

### Water circuit
- [ ] **Bezinkafscheider** — `sink_float`  · 3A/3B wash train. Has BezinkTank sim + local BezinkHmi proximity panel. Hal 1 wash section.
- [ ] **EOP — Indaver waterzuivering** — `eop_endpoint`  · External / plant boundary (off the main halls). Non-interactive endpoint; visible via hmi_indaver_water panel.
- [ ] **Flotatietank (3A LA2)** — `flotation_tank`  · 3A LA2 circuit pos 3 (~4:00). Use flotation_tank (1.5x) for line 3A.
- [ ] **Flotatietank (3B)** — `flotation_tank`  · 3B main wash circulation, Hal 1. flotation_tank (1.5x). Distinct instance from 3A.
- [ ] **Kleine LA** — `kleine_la`  · 3B flotation-tank material-exit side toward Hal 0, floor-standing. Size placeholder (F1).
- [ ] **Pomp C1** — `pomp_c1`  · 3A wash train, between glijgoot and frictiescheider M3 (~7:30 on LA1 loop). Hal 1.
- [ ] **Pomp P1** — `water_pump`  · LA1 circuit pos 2, between waterbak LA1 and dosing screw / friction washer. Serves 3A.
- [ ] **Pomp P2** — `water_pump`  · LA2 circuit pos 2, between waterbak LA2 and flotation tank. Serves 3A.
- [ ] **Pomp zeefbocht (3B)** — `pomp_zeefbocht`  · 3B utility cluster near blauwe tank, Hal 0/1. Fed screen not modeled (F9).
- [ ] **Put & pomp was 1** — `water_pump`  · Wash line 1 dirty-water collection pit + pump feeding ZSS proces. Hal 0/1 wash area (approx).
- [ ] **Tankje tussen extruders** — `tankje_tussen_extruders`  · Cooling-water cluster between extruders; one per line (3A + 3B, likely 3C/6). Composite tank + pump under. Dims placeholder (F4/F5).
- [ ] **ZSS water tank** — `zss_water`  · Two instances per floor plan: Hal 0 and Hal 1 (east side, near Hal 0/1 wall). Return side of wash circuit.

### Air / vacuum
- [ ] **Compressor A (vertical)** — `compressor_a`  · Utility cluster (not yet placed). Near pneumatic/ring-main. No documented coordinate.
- [ ] **Compressor B (cabinet screw)** — `compressor_b`  · Utility cluster (not yet placed). No documented coordinate.
- [ ] **Ringleiding (pneumatic ring main)** — `ringleiding`  · Plant-wide high-level horizontal loop. Line-3A-specific caged variant removed; use generic ringleiding.
- [ ] **Vacuum pump (liquid-ring)** — `vacuum_pump`  · Extruder degas + wash-line dewatering (#208b). No single coordinate.
- [ ] **Vacuum unit (cabinet)** — `vacuum_unit`  · Extruder areas (3A/3B/3C/6) degas zones; mounted on/near extruders.

### Silos
- [ ] **Doseer silo** — `doseersilo`  · Feed-prep area for extruder infeed (3C/6 or line 1). No documented coordinate.
- [ ] **Extruder feed silo (elevated, 2 cyclones)** — `extruder_silo`  · Above each extruder (3A/3B/3C/6); Hal 7/Hal 2-3 extruder clusters. Multi-instance.
- [ ] **Gate/door Hal 0 south wall (to silopark)** — `gate_roller`  · South wall of Hal 0, opening toward outdoor silopark. Surface/wall-opening (SHARED layer).
- [ ] **Laadsilo buiten (LS)** — `ls_silo_buiten`  · Outdoor silopark SW (part of same 10-silo cluster), truck lanes below. Per-silo coords needed.
- [ ] **Mengsilo buiten (MS)** — `ms_silo_buiten`  · Outdoor silopark SW of Hal 0/1 (10 silos, 2 rows of 5). Cluster world approx (-211,+53); per-silo coords needed.
- [ ] **Mixing silo (mengsilo, indoor)** — `mengsilo`  · Line 3A flake recirc loop, near laadsilo (indoor, Hal 8 region). NOT the outdoor MS.
- [ ] **Silo level sensor (overbruggebaar)** — `silo_level_sensor`  · On/near VSS silos (3A/3B), extruder silos, dosing silos. Multi-instance, per-silo.
- [ ] **Voorraad silo (indoor)** — `voorraad_silo`  · Extrusion back-end near 3C/6 tail (Hal 8). No exact coordinate.

### HMI / control
- [ ] **HMI — Extruder (alle lijnen)** — `hmi_extruder_all`  · Central extruder area or Hal 7/8 boundary.
- [ ] **HMI — Indaver water (wall-mount)** — `hmi_indaver_water`  · Control room / visible spot in Hal 0, linked to EOP. Wall-mounted.
- [ ] **HMI — Shredder 1 lijn 3A/3B** — `hmi_shredder1_l3ab`  · Shredder 1, lines 3A/3B sorteerlijn area, Hal 7.
- [ ] **HMI — Shredder 2 lijn 3A/3B** — `hmi_shredder2_l3ab`  · Shredder 2 (fine) climb-belt area, lines 3A/3B.
- [ ] **HMI — Shredder lijn 1** — `hmi_shredder_l1`  · Shredder 1 location, Line 1 (Hal 7 north).
- [ ] **HMI — Shredder lijn 3C/6** — `hmi_shredder_l3c6`  · Shredder intake, lines 3C/6, Hal 8.
- [ ] **HMI — Sorteerlijn 3A/3B** — `hmi_sorting_l3ab`  · Sorteerlijn bunker pedestal, Hal 8 north.
- [ ] **HMI — Transportbanden 3A/3B** — `hmi_transport_l3ab`  · Transport-belt cluster head, Hal 7/8 intersection.
- [ ] **HMI — Transportbanden 3C/6** — `hmi_transport_l3c6`  · Lines 3C/6 intake conveyor cluster, Hal 8.
- [ ] **HMI — Waslijn (alle lijnen)** — `hmi_washing_all`  · Wash hall, Hal 0/Hal 1 boundary.
- [ ] **HMI — Water extruder 1/3A/3B** — `hmi_water_extr_l1_3ab`  · Shared water supply cluster, Hal 7-8 region.
- [ ] **HMI — Water lijn 3C/6** — `hmi_water_l3c6`  · Lines 3C/6 cooling-water cluster, Hal 8.
- [ ] **PCU control cabinet (E-kast)** — `pcu_cabinet`  · Head of each extruder line (3A/3B/3C/6/1). Multi-instance.
- [ ] **Quality-control bench (QA)** — `qa_bench`  · QA lab area (Hal 0 / office region).
- [ ] **Shift-leader PC / Bedrijfsleider desk** — `shift_leader_desk`  · Control room / office (Hal 0 area). NOTE: also code-seeded today by LegacyPropsSpawner._spawn_shift_leader_desk at anchor+(-9,0,-14) via ShiftLeaderDesk.gd (...

### Safety / utility
- [ ] **Air hose hook (20 m)** — `hook_air_hose`  · Near pneumatic equipment (compressors, ring main). Wall-mount.
- [ ] **Dirt hot-spot (procedural)** — `dirt_hotspot`  · Under chutes, dryer areas, forklift lanes across Hal 0-8. Game-mechanic zone, multi-instance.
- [ ] **Drainage grating section** — `drainage_grating`  · Under wash machines / flotation tanks / drain troughs, Hal 1. Modular, multi-instance.
- [ ] **Fire extinguisher (wall-mount)** — `fire_extinguisher`  · Multiple entrance/utility zones across halls. Multi-instance.
- [ ] **Fire-suppression riser** — `fire_riser`  · Central in halls, routed to ceiling nozzles. Multi-instance.
- [ ] **High-pressure washer (mobile)** — `washer_hp_mobile`  · Utility alcove / equipment bay (mobile prop).
- [ ] **Hose reel — fire red (10 m)** — `reel_fire_red`  · High-traffic/assembly areas near extinguishers. Wall-mount, multi-instance.
- [ ] **Hose reel — water black (10 m)** — `reel_water_black`  · Utility areas (unspecified). Wall-mount, multi-instance.
- [ ] **Hose reel — water yellow (10 m)** — `reel_water_thick_yellow`  · Various utility areas across halls. Wall-mount, multi-instance.
- [ ] **Overhead crane (PPE gantry)** — `overhead_crane`  · High-ceiling hall (Hal 8 or central), 4+ m overhead.
- [ ] **Scissor lift (yellow)** — `scissor_lift`  · Service/maintenance zone, likely Hal 7 or 8.

### Structure
- [ ] **Concrete V-beam** — `concrete_v_beam`  · Structural bracing throughout halls. Multi-instance; part of building shell.
- [ ] **Poort 4/5 gate (west facade Hal 4)** — `gate_roller`  · West facade of Hal 4; main entry gate. Placed via surface/wall-opening (SHARED WorldLayout.structure_items), not per-save.
- [ ] **Riveted steel column** — `riveted_steel_column`  · Structural support throughout halls. Multi-instance; part of building shell.

### Other
- [ ] **Compactor feed belt** — `compactor_belt`  · Extruder back-end, mounted above compactor (PCU) unit.
- [ ] **Water pump (generic Wilo-style)** — `water_pump`  · Water clusters throughout (Hal 0,1,7,8), one per major water zone. Multi-instance.

## Needs modeling — NO catalog model (do not invent; needs operator photo/spec)
- **Waterbak La 1** () — Wash line 3A, head of LA1 closed loop; fed by blauwe tank. Line-scoped, no coordinate.
- **Waterbak La 2** () — Wash line 3A, head of LA2 closed loop (12:00 on LA2 diagram); fed by blauwe tank.
- **Blauwe tank** () — Hal 1, next to 8m3 and 5m3 tanks; central ~3 m3 extruder-cooling hub (Q10). Candidate reuse: zss_water or new entry.
- **Vers kanaalwater supply** () — Entry from cellar (kelder) main line; pipeline infrastructure, not a discrete placeable. Location of kelder inlet undocumented.
- **Riool naar EOP** () — Dirty-water collection main from 3A/3B + extruder vacuum/centrifuge to EOP. Pipeline infrastructure, not a discrete placeable.

## Open architectural decision
Line-scoped water gear (waterbak LA1/LA2, pumps P1/P2/C1, flotation, bezinkafscheider, zeefbocht pump) arguably belongs **inside the LINE_3A/3B macro sequences** (so it moves/persists with the line) rather than as standalone marked drops. Decide before placing those.