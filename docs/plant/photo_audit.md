# Reference-photo × docs audit — machine map & ledger (CeDo Simulator)

Systematic reconciliation of the plant model against the written record. Started
2026-07-14.

**PRIMARY SOURCE = the docs, not the photos.** 417 markdown docs: 380 SWIs in
`docs/plant/swi/` (the plant's real Standard Work Instructions) + 29 curated
docs in `docs/plant/`. The spine is the per-line **flow diagrams**
(`lijn_3a_flow.md`, `lijn_3b_flow.md`, `lijn_1_flow.md`) + `titech_tomra.md`,
`hmi_reference.md`, `fixed_equipment_inventory.md`, 4× `water_circuit_*.md`,
`densities.md`, `extruderlijst_3a.md`. Photos ILLUSTRATE; flow docs + SWIs
SPECIFY. **Always pull the machine's flow block + SWI(s) BEFORE reasoning from a
photo or asking the operator.**

## Loop (per machine)
**PHASE (operator-set 2026-07-15): IMAGES FIRST across ALL machines; sim/HMI logic BATCHED LAST.**
Per machine now = get the MODEL matching the photos + capture real spec numbers (throughput, water,
etc.) into the ledger. Do NOT build the functional sim brain yet (the shredder's full sim was the last
one built solo). Once every machine's image is signed off, do the batched sim pass (throughput physics,
water/interlock logic, HMI wiring). Operator: "discuss that logic next, after all images are completed."

1. Pull the machine's flow block(s) + `ls docs/plant/swi/ | grep -i <machine>`
   for its SWI(s), read them.
2. Claude posts photo(s) + a structured read (from docs+photo), what maps to the
   placeable, gaps. Operator confirms/corrects/adds.
3. Render the current model: `Godot --path . res://src/tests/shot_placeable.tscn -- <id> [yaw] [pitch]`
   → `user://shot_<id>.png`. (Whole lines / HMI placement → bench render.)
4. Fix / verify → re-render proof; behaviour proven via regression harness or bench test.
5. Update the row, next machine.

Render tool = `src/tests/shot_placeable.gd` (any placeable, auto-framed).

## Line chains (from the flow docs — the audit order)
- **3A:** vuilsnippersilo → doseerschroef M11a → frictiewasser M1/M2 → C1 → frictiescheider M3 → intrek/uittrek-rol → flotatietank → ontwaterschroef → frictiescheider M4 → mech. droger M8 → V4 → mengsilo (+rondmeng-lus: M11a→verdeelwals m14→V1) → V2→ringleiding→cycloon&windzifter→V2a → verdeelwals → thermische droger → cycloon→V3 → extruder silo → compactorband → compactor → extruder+laserfilter+vacuum → kopfilter&heetafslag → ontwaterzeef+centrifuge → weegschaal → MS/LS silo (+bigbag).
- **3B:** vuilsnippersilo → doseerschroef → **Rafter** → ontwaterschroef v/d rafter → frictiescheider 210 → flotatietank → ontwaterschroef → frictiescheider li/re → mech. droger 310 **+** 311 → ventilator → verdeelwals → thermische droger → ringventilator → extruder silo → …(zelfde extrusie-tail as 3A, geen bigbag).
- **1:** metaaldetectieband → opzetband (Westa) → band 1 onder shredder → magneetband → band 2 → **HPS (SGA)** → 2×(frictiescheider 6a/b→mech.droger 7a/b→ventilator 8a/b) → **Maalmolen 1** → 2×(ventilator 10a/b→intrekschroef 11a/b) → flotatietank → uittrekschroef → frictiescheider li/re → 2×**Kufferath**→MAS buffer→MAS droger→transportventilator (Deltoid) → extruder silo → …(zelfde extrusie-tail).
- **Sorteerlijn (upstream, feeds all):** TITECH/TOMRA AUTOSORT (belt → NIR/VIS scanner → valve block → splitter → 2 bunkers).

## Ledger
Legend: ☐ todo · ◑ read/awaiting operator · ⚙ fixing · ✓ done · ⚠ stub/gap

### A · Infeed & sorting
| Machine (flow) | Line | Placeable | Photo | Model | Status · notes |
|---|---|---|---|---|---|
| Metaaldetectieband | 1 | `metal_belt` / `metaaldetector` | — | ✓ | ☐ |
| Opzetband (Westa) | 1 | `westa_band_1` / `opzetband_1` | — | ✓ | ☐ |
| Band 1 onder shredder / Band 2 | 1 | `transportband_*` | — | ✓ | ☐ |
| Magneetband (overband magnet) | 1 | `overband_magnet` | — | ✓ | ☐ |
| HPS (SGA) zware-delen scheider | 1 | `vw_trommel` *(ruling 2026-08-28: SAME machine as the voorwastrommel — one drum; `sga_drum` is a deliberately-unplaced spare)* | — | ✓ | ☐ |
| TITECH/TOMRA AUTOSORT | sort | `titech_sort`,`tomra_sort` | machines/titech_tomra_1.jpg *(actually a disc/ballistic screen, NOT the sorter)* | ⚠ | ◑ Doc `titech_tomra.md`+`Werking-Titech-tomra-p1/2/3`: real = belt→NIR/VIS scanner→valve block→splitter→2 bunkers; **not modelled** (stubs only). Photo is a screen. |
| Disc/ballistic screen (in titech photo) | sort? | `ballistic_sep` / `wind_sifter`? | machines/titech_tomra_1.jpg | ? | ◑ Identify: which machine is the striped-roller disc screen in the photo? |

### B · Shredding
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Shredder 1 (coarse) | **Line 1 + 3C/6** | `shredder_1` | — | ✓ | ✓ **DONE 2026-07-15** — big RED (operator: 3C/6 + Line 1 = big red, same model). 4×9×5, full flared two-tier hopper, dirty. Rewired `LINE_3C6_SEQ` shredder_2→shredder_1. |
| Shredder 2 (fine) | 3A/3B | `shredder_2` | machines/shredder_2_input.png (=ram-fed infeed conveyor/baler), _output.png (=discharge belt; real shredder barely visible, dark blue) | ✓ | ✓ **DONE 2026-07-14/15** — remodelled like shredder_1, smaller (3.4×**6.0**×4.2), dark BLUE, wide top tier removed (halved grey top), "SCHINDLER'S" nameplate (was red Lindner Polaris). Photos are the in/out CONVEYORS, not the shredder. |

**Shredder internals rebuilt (2026-07-15, both shredders — shared `_m_shredder_1`):** hopper was a solid block → now a HOLLOW funnel (`_hollow_box`); single rotor → TWIN counter-rotating shafts with interleaving discs; solid base → split with a centre drop-slot so material falls onto the conveyor; stators flank both rotors. (Docstring had wrongly claimed "dual rotors".)

**Shredder FUNCTIONALISED (2026-07-15, `src/sim/ShredderMachine.gd`, #227):** was a static visual → now a sim brain attached at spawn (build_node). Throughput physics (feed→shred capped at rated 4500/2200 kg/h, motor load %, overfeed buffer + spill, sustained-overload TRIP), relay states (key I/II/III · start · e-stop), rotor-spin gated on run state, SWI procedures as crosshair E (start/stop, e-stop+trip reset, open housing SWI-027/040, block rotor SWI-033, close). Grounded in docs (4500 kg/h feed; SWIs 027/033/034/035/040/042/048). Proven by `test_shredder_machine.tscn` (16/16). **Test stage:** GauntletWorld station #263 — a running unit + an overfed unit that trips, live `ShredderReadout` labels, aim+E controls. **Refinements pending (operator-directed):** wire `ShredderRelayPanel` to the HMI overlay *once the shredder HMI photo comes up in the audit*; deepen open/clean into the full multi-step SWI procedure later (like the laser filter's ~6-session wissel); rated caps (4500/2200) approximate.

**Global:** #226 dirty filter now applied to EVERY machine via `_mat()` (light grime patina) — operator standing rule, see [[feedback-dirty-filter-every-machine]].

### C · Pre-wash
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Voorwas trommel (prewash drum) | 1 | `vw_trommel` / `prewash_drum` | machines/voorwas_trommel_1.png, _2.png | ✓ | ◑ **IMAGE OK 2026-07-15** — operator saw render vs both photos, no visual correction. Model already photo-accurate (bolted flange + bolt ring, AXIAL THRUST ASSEMBLY B-4 plate, solid-rubber cradle tires, yellow peeling weldmesh cage, grated drain tray, TANK-A/50000L stencil, HMI LEDs). Candidate-only tweak (NOT applied, shared mat): drum reads a touch brown via `mat_stainless_weathered` (operator-tuned to flotatietank_3A) — photos are dirtier *silver-grey* w/ rust freckles; leave unless operator flags. |
| Rafter (natte maal/was) | 3B | `rafter` | machines/_rafter_dewatering_screw_frictiescheider_3B.png | ✓ | ✓ **DONE 2026-07-15** — operator: submerged-sieve model OK; added a mill-style maintenance bordes (#231, `_m_rafter`): grated walkway at rafter-bottom level on the -X/outtake side, yellow `_railing` (open +X toward tank), grating `_stair` off the **+Z inlet end** descending away from the tank (operator confirmed stair direction). Brand/merk still UNKNOWN (operator will look it up — leave open). |
| — Friction separator (3B, blue inclined) | 3B | *(separate machine, audit under D)* | machines/_rafter_dewatering_screw_frictiescheider_3B.png | ? | ◑ **CORRECTION 2026-07-15:** the big blue-topped inclined machine in the photo is the **friction separator** (NOT a dewatering screw as I first guessed). Operator flow after the rafter: rafter outlet → **90° turn → HORIZONTAL dewatering screw → friction-sep BOTTOM inlet**. So the inclined unit = friction sep; a separate horizontal dewatering screw feeds its bottom. Model these when frictiescheider/dewatering-screw come up in section D. Also in frame: PRESONA "BALETA MASTER 4008" baler (sorting-line, not wash) + a big-bag on a cart. |

**Voorwas trommel — SPEC captured for the later sim (2026-07-15, operator + SWI-012):** max throughput **1450 kg/h** (operator, real number — NOT the ~4500 I guessed; drum is a bottleneck-class prewash). Wash water from **ZSS witte retour bak @ 95–110 m³/h** (SWI-012 step 10). **Signature interlock (logic deferred):** drum runs but no water out → instant blockage → *"stop the shredder!"* — a cross-machine dependency on `shredder_1`. Start seq (SWI-012 steps 6–10): Kufferaths fault-free @ 3.2 bar → Was-1 PLC [storingen] check → start → confirm water. **Sim/`TrommelMachine.gd` NOT built** — operator: "discuss that logic next, after all images are completed." Build in the batched sim pass.

### D · Wash & separation
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Doseerschroef M11a/b | 3A/3B | `transport_screw`? | — | ? | ☐ verify screw placeable |
| Frictiewasser M1/M2 | 3A | `friction_washer` / `intensive_washer` | — | ✓ | ☐ |
| C1 (unknown block) | 3A | — | — | ✗ | ☐ open Q: what is C1? |
| Frictiescheider (M3/M4/210/li-re/6a-b) | all | `friction_sep` | machines/_dewatering_screw_frictiescheider_flotatietank_inlet_side_notice_2_paddle_motors.png | ✓ | ☐ |
| Flotatietank (+ intrek/uittrek roller) | all | `flotation_tank`,`_wide`,`sink_float` | flotatietank_3A.png, flotatietank_3B_…mechanical_dryer_3B.png, _flotatietank_catwalk_view_1.png | ✓ | ◑ **REWORKED 2026-07-15 (#232), awaiting operator OK.** Operator: HOPPER 4A IS the flotation tank. First pass enclosed it → "not logical"; operator annotated via overlay. Corrected: **TOP OPEN** (water+paddles visible, collar dropped); per-line paddle counts via new `wide` param — **3A/3B `flotation_tank` = 7 paddles** (large 1st under a metal cover plate + 5 small + large last), **3C/6 `flotation_tank_wide` = 11** (large 1st + 9 small + large last, ends ~2× dia); **one motor per paddle IN LINE with the axle** (large motor on end paddles, small on middle); **catwalk lowered 1.2 m** (rim−0.25≈3.85). Placards HOPPER 4A (std only) + MAX LOAD 500KG. Sim comp tags (inlet/transport_*/outlet/scraper), water/film field, rafter water-level link (rim 4.1/surf 4.0) all preserved. Regression 14/0 (line_3a builds w/ flotation, round-trips). GUIDE-CeDo83: density separator — M3 feed+inlaatpaddel → schoepen→uitdraaischroef (floaters SG<1) / ketting schraper→afval (sinkers SG>1). Renders: shot_flotation_tank_3A.png, shot_flotation_tank_wide_3C6.png. |
| Intrek/Uittrekschroef | 1 | `transport_screw`? | — | ? | ☐ |
| Maalmolen 1 (grinding mill) | 1 | `mill` | — | ✓ | ☐ |

### E · Dewatering & drying
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Ontwaterschroef / dewatering screw | all | `dewater_screw` | machines/_dewatering_screw_…png, _rafter_dewatering_screw_…3B.png | ✓ | ☐ |
| Mechanische droger (M8/310/311/7a-b) | all | `mech_dryer` | flotatietank_3B_…mechanical_dryer_3B.png | ✓ | ☐ |
| Thermische droger | 3A/3B | `thermal_dryer` | — | ✓ | ☐ |
| Trilzeef (vibrating sieve, 6-row) | ? | `trilzeef` | machines/_trilzeef.png | ✓ | ☐ |
| Kufferath (ontwateringszeef) | 1 | `kufferath_sieve` | — | ✓ | ☐ |
| MAS buffer / MAS droger | 1 | `mas_bak` / `mas_droger` | — | ✓ | ☐ |
| Ontwaterzeef | all | `ontwaterzeef` | — | ✓ | ☐ |
| Centrifuge | all | `centrifuge` | — | ✓ | ☐ |

### F · Mixing & pneumatic transport
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Mengsilo (mixing silo) | 3A | `mengsilo` | — | ✓ | ☐ |
| Verdeelwals (distribution roller) | 3A/3B | `verdeelwals` | — | ✓ | ☐ |
| Ventilatoren V1–V4 / 8 / 10 / ring / Deltoid | all | `blower` (generic, unnumbered) | — | ⚠ | ☐ no numbered-fan model |
| Ringleiding (pneumatic ring main) | 3A | `ringleiding` | machines/_ringleiding_1..4.png | ✓ | ☐ |
| Cycloon & windzifter | 3A | `cyclone`,`cyclone_tower`,`wind_sifter` | — | ✓ | ☐ |

### G · Extrusion
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Extruder silo | all | `extruder_silo` | machines/_extruder_silo.png | ✓ | ☐ |
| Compactorband | all | `compactor_belt` / `compactorband` | machines/_compactor_belt.png, _2.png | ✓ | ☐ |
| Compactor (PCU) | all | `compactor` / `cutter_compactor` | machines/_extruder_start_and_PCU.png | ✓ | ☐ operator: PCU E-kast |
| Extruder | all | `extruder_3a/3b/1/3c/6` | machines/_extruder_start_and_PCU.png | ✓ | ☐ |
| Vacuum degas (op extruder) | all | `vacuum_degas` | machines/_vacuum.png | ✓ | ☐ |

### H · Filtering
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Laserfilter + lump discharge | all | `laser_filter`,`lump_cart`,`lump_platform` | _laserfilter.png, laserfilter_lump_cart_discharge.jpg, ~/laser_filter_3B.jpg | ✓ | ✓ **DONE 2026-07-14** (twin nozzles ±X, carts on bordes, fork channels) |
| Kopfilter & heetafslag (diekop) | all | `kopfilter` / `heetafslag` | machines/_kopfilters.jfif | ✓ | ☐ operator: head-filter **change tool + its safety box** |

### I · Pelletizing & back-end
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Heetafslag (hot die-face pelletizer) | all | `heetafslag` | machines/pelletizer.png (+ instructions/pelletizer_instructions.png) | ✓ | ☐ |
| Weegschaal (weighing scale) | all | `weegschaal` | — | ✓ | ☐ |
| Bigbag station | 3A | — | — | ✗ | ☐ gap |

### J · Silos & storage
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Vuilsnippersilo (dirty-shred silo) | 3A/3B | `vuilsnippersilo` | — | ✓ | ☐ |
| VSS silo | 3A/3B | `vss_silo` | — | ✓ | ☐ |
| MS / LS silo buiten | all | `ms_silo_buiten`,`ls_silo_buiten` | — | ✓ | ☐ |
| Voorraad silo (indoor) | 1 | `voorraad_silo` | — | ✓ | ☐ |
| Doseersilo | 3C/6 | `doseersilo` | — | ✓ | ☐ |

### K · Utilities & water
| Machine | Line | Placeable | Photo | Model | Status |
|---|---|---|---|---|---|
| Vacuum unit (cabinet) | extr | `vacuum_unit` | machines/vacuum_unit_2pots.png, _vacuum.png | ✓ | ☐ note: 2-pot variant |
| Vacuum pump (liquid-ring) | extr | `vacuum_pump` | machines/vacuum_pump.png | ✓ | ☐ |
| Small pump | water | `water_pump` / `pomp_c1` / `pomp_zeefbocht` | machines/_pump_small.png | ✓ | ☐ |
| Compressors A/B | air | `compressor_a`,`compressor_b` | — | ✓ | ☐ |
| Water circuit (P1/P2/LA1/LA2/blauwe tank/ZSS/EOP/koeltoren/zandscheider) | all | see `fixed_equipment_inventory.md` + `water_circuit_*.md` | — | mixed | ☐ zandscheider = gap |

### L–N · HMI · building · people (batch later)
| Group | Placeable | Photo | Status |
|---|---|---|---|
| HMI panels + stand placement (13 scoped) | `hmi_*` | hmi/ (22 photos) + `hmi_reference.md` | ☐ operator flagged HMI stand placement |
| Building: V-beams, racks, ladders/railings, extinguisher | `concrete_v_beam`,`riveted_steel_column`,`fire_extinguisher`… | building/ (4) | ☐ |
| Instructions boards (feeder, pelletizer) | — | instructions/ (2) | ☐ |
| Worker outfit | player/npc wardrobe | people/worker_outfit.png | ☐ |
