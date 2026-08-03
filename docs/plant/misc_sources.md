# Miscellaneous CeDo sources — sweep + digest

Extracted 2026-07-05. This file accounts for the **miscellaneous / best-effort** source
list (Desktop artefacts, F:/Citizen office files, and the three relevance-sweep dirs) that
sits outside the two already-digested corpora (`README.md` = the 22 SWI/photo PDFs and the
379 PROD-SWI set; `cedo_data_manifest.md` = the F:/Citizen/**Documents**/CeDo measurement
archive). **NO DATA LOSS** rule applies: full transcriptions, photos described line-by-line,
constants mined, every listed file dispositioned. `[unsure: ...]` marks best-effort reads.

Tabular deliverable: `src/data/plant/stresssheet_line6.json` (from the Big StressSheet).

---

## 1. C:/Users/arnod/Desktop artefacts

### 1a. CeDo127.pdf, CeDo48.pdf — DUPLICATES of the D: SWI set
Byte-identical to the D:\ drive-download SWI set (verified by MD5):

| Desktop file | MD5 | D:\ counterpart |
|---|---|---|
| `CeDo127.pdf` (1,545,010 B) | `fd20416bd8af8f2687d5ca2af844a8cb` | `D:\drive-download-20251124T130330Z-1-001\240_CeDo127.pdf` |
| `CeDo48.pdf` (1,232,937 B) | `4b4c3ddcaa0a8b21f25f025d060e4e5e` | `D:\drive-download-20251124T130330Z-1-001\174_CeDo48.pdf` |

Disposition: **duplicates**, digested under the D:\ SWI corpus (see `swi/`). Not re-digested here.

### 1b. cedo_transportbanden_info.txt — conveyor / switch-belt logic (FULL transcription)
Operator's own notes correcting the sim's 3D building/conveyor model. Verbatim (blank lines collapsed):

> building can be lower still; lower by twice with what you lowered it in the previous iteration
>
> I placed the 3A/3B intake
>
> the U is built using stacked concrete - building code says you build walls like these with 1/2 overlap
>
> the U has to be 2.5 times higher
>
> the U has to have the 2 outer ends removed (so more like a small u, but keeping the same width)
>
> all conveyors are rotating in the wrong direction
>
> I can't see transportation belt 8.5
>
> the U is placed after conveyor 12 / next to the VSS (?); should be after conveyor 8.5 (which is on one side of conveyor 8, and conveyor 9 is on the other end))
>
> there is a VSS at the end; unclear if it is A or B line, also --> VSS is first machine in the washing line; not to be included in the transportation section
>
> switch belt = conveyor 12
>
> switch belt should be below conveyor 11 so that material from 11 falls on to 12, then 12 normal position is center (it can move 1.5m left and 1.5m right from the center), only conveys material towards silo 3A, the mechanism jogs the entire belt 12 along the axis it conveys material, e.g. at 1.5m left it feeds 100% to line 3A VSS and at 1.5m right it only feeds 3B VSS, at the center it feeds 3A and 3B (practically) equally. It switches (hence switch belt) between left-center-right positions depending on the VSS's levels. jogging speed is about 10cm/s I'd say.
>
> conveyor 7 is slightly above 8 --> material from 7 lands on the center of 8. 8 can spin in both directions. Lets say 'normal' direction is towards 9. But if VSS 3A + VSS 3B are both sending a FULL signal --> the conveyor 8 ramps down in like 2 seconds, then it ramps up the other direction in like 2 seconds. This other direction discharges the material to the slightly lower conveyor 8.5; which feeds the U (stortvak). This prevents excess film to overfill both the VSS's. Also at the time that both VSS's tell that they are FULL --> the Bunker pauses, every conveyor up to the trilzeef pauses in 1s sequence from the bunker per conveyor, the trilzeef keeps shaking causing the material that was still present to go down and through Titech/Tomra 1+2, allowing material to keep moving to Shredder 2. This causes a slowing rate of material coming to Shredder 2 which causes a slowing rate of small flakes to enter the transportation belts system. This prevents the U to overflow with material quickly.
>
> Shredder 2 FULL signal:
> wrong:
> Shredder 2 pauses at the FULL signal, so slight accumulation of material in the Shredder 2 hopper occurs, but it can handle that

**Load-bearing facts for the sim (glossary + logic):**
- **VSS** = *voorsilo* / buffer silo, "first machine in the washing line" — one per line (3A, 3B). NOT part of the transportation (conveyor) section. This is the same silo the HMI screen (1e) calls "silo 3A/3B."
- **U** / **stortvak** (dump bay/overflow bin) = stacked-concrete U-shaped bin, walls laid with ½-brick overlap; must be 2.5× taller than currently modelled, with the two outer end-walls removed (open small-u). Fed by conveyor **8.5** (a branch off conveyor 8), located after 8.5 (NOT after 12).
- **Conveyor 12 = "switch belt" (wisselband)**: sits below conveyor 11, travels ±1.5 m about center on its conveying axis at ~10 cm/s. Left 1.5 m → 100 % to 3A VSS; right 1.5 m → 100 % to 3B VSS; center → ~50/50. Position driven by the two VSS level signals.
- **Conveyor 8** is bidirectional. Normal direction → conveyor 9. If BOTH VSS 3A and 3B send FULL: belt 8 ramps down ~2 s, reverses ~2 s, discharges to lower **conveyor 8.5 → U/stortvak**.
- **Both-VSS-FULL cascade**: Bunker pauses; every conveyor up to the *trilzeef* (vibrating screen) pauses in a 1 s-per-conveyor sequence starting from the bunker; the trilzeef keeps shaking so residual material still flows through **Titech/Tomra 1+2 → Shredder 2**, giving a decaying flake rate into the transport belts so the U doesn't overflow fast.
- **Shredder 2 FULL**: (operator flags the "pauses / slight hopper accumulation" model as *wrong* — correct behaviour is left as an open note, not yet specified).
- All conveyors were rotating the wrong way in the model; belt "8.5" was missing.

Cross-ref: the flow docs (`lijn_3a_flow.md`, `lijn_3b_flow.md`) and `floor_plan_edits.md`. This is the authoritative source for the **switch-belt / dump-bay overflow interlock** — not previously captured with this jogging/ramp detail.

### 1c. extruder_live_graph.py — root live-graph script
Matplotlib `FuncAnimation` (500 ms interval) plotting 4 stacked axes from a `simulator_service.simulator` singleton (imports `simulator, register_listener`). Sets motor speed 42 on start. **Y-axis ranges (the mined constants — the operator's own sense of plausible ranges):**

| Axis | Signal (attr) | Y-range |
|---|---|---|
| ax1 | Amperage (A) — `sim.amperage` | 0 – 100 |
| ax2 | Melt Pressure (bar) — `sim.melt_pressure` | 0 – 150 |
| ax3 | Output (kg/h) — `sim.output_kg_h` | 0 – 200 |
| ax4 | Vacuum (mbar) — `sim.vacuum_pressure_mbar` | -250 – 10 |

`maxlen=100` rolling deque. It expects a companion `simulator_service.py` (NOT present on Desktop — it's the ExtruderSim stack, see §1f). Note the 0–200 kg/h axis is a *single-extruder* range, an order of magnitude below the whole-line ~1000+ kg/h (§2a).

### 1d. _lumbs_cart.jpg — laser-filter "lump cart" photo (described)
Photo (1080×~900): a **blue steel tub cart** ("lump_cart" in the sim) parked on skids under a black discharge chute. A thick grey-black extrudate "worm" / sludge string of **melt-filter contaminants ("lumps")** is being pushed over the chute lip and coiling into the tub; splatter and pale flakes coat the rim and floor grating. Two pictograms on the tub's blue side: a yellow **hot-surface warning triangle** (radiating-heat symbol) and, right of it, a yellow **hot-liquid/molten-splash hazard** pictogram (drips off a hand/surface). Floor grating and a wet concrete floor at left; steel structure behind. Confirms: the corrugated discharge chute drops lumps into a cart parked underneath — exactly the geometry the sim macros currently miss (per memory `project_laser_filter.md`).

### 1e. HMI_sorteerlijn_bunker.jpg — bunker-speed HMI screen (described EXHAUSTIVELY)
Blue Siemens-style HMI touch panel (photographed at an angle, some glare/dust). German + Dutch (flag toggles top-right: 🇩🇪 / 🇳🇱). This is the **sorteerlijn bunkersnelheid (bunker-speed) setpoint screen.** Layout top→bottom, left→right:

- **Header row (left block):** `speed autom.` | col `setpoint.` | col `limit`.
- **Setpoint ladder (left column), 10 rows** each with a `setpoint` field and a `limit` field, all reading `0` / `0`:
  `setpoint 1 empty`, `setpoint 2`, `setpoint 3`, `setpoint 4`, `setpoint 5`, `setpoint 6`,
  `setpoint 7`, `setpoint 8`, `setpoint 9`, `setpoint 10 full`.
  (So the ladder maps VSS/bunker fill from "empty" (1) to "full" (10) onto a bunker speed — currently all zero = table not programmed in this snapshot.)
- `Bereken Snelheid` (calculate speed) toggle: **on / off**, shown **off** (green button).
- `bunkersnelheid berekend ..` (calculated bunker speed) = **875**.
- **Right panel `bunkersnelheid setpoint`** (bunker-speed setpoints), a grid:
  - `Beide` (both) = **875** | `Zonder 3A` (without 3A) = **875** | `Zonder 3B` (without 3B) = **875** | `Vertraging` (delay) = **30 sec.**
  - second sub-row under those: `0 sec.`
  - `Pers alleen` (compactor/press only) = **200** | `Pers omschak` [omschakel = switchover] = **75 sec.** | `Vertraging` = **30 sec.** | `Vert. terug` (delay back) = **30 sec.**
  - trailing `0 sec.` fields on both delay columns.
- **`filling setpoint`** block: `actual value` = **258**; button `diagram`.
- **Lower-left conveyor mimic** (a drawn belt with arrow →, a gear/sun icon = motor):
  left readout `66 actual value` / `125 setpoint`; right readout `actual value 108` / `setpoint 70`. Below the belt, a filling-bar graphic and a vertical blue level indicator next to the `filling setpoint 258`.
- **Bottom button bar:** `Auto` (green) | `Hand` | 📢(horn) | `I` | `0` (red) | `Nummer richtlijnen` | `0` | `Enkeling-Stop` | `reset` | `Overzicht` (overview) | `Start scherm` (start screen).

**Load-bearing values:** bunker speed setpoints all **875** (Beide / Zonder 3A / Zonder 3B); **Pers alleen = 200**; switchover delays **30 s** and **Pers omschak 75 s**; calculated bunker speed **875**; filling setpoint actual **258**; belt setpoints 125/70 vs actuals 66/108. Answers **Q16** context: the "Bunker speed 200–800" range on FORM sheets is this **bunkersnelheid** field — a unitless HMI speed number (the compactor-only "Pers alleen" floor = 200, normal running = 875), consistent with a 200→~875 span, **not** kg/h or rpm. Confirms the German/Dutch bilingual HMI and the "Zonder 3A / Zonder 3B" (running one wash-line silo out) operating modes.

### 1f. ExtruderSim-main/ — PRIOR extruder-sim attempt (inventory + mined constants)
A ~611 KB Python repo: an earlier, physics-based single-screw EREMA extruder simulator with PCU (cutter-compactor) model, Tkinter HMI, matplotlib/pygame/3-D views, a Flask web bridge serving an `EREMA CCE 3D Simulation.html`, a `filamentSim/` sub-project, and a full `tests/` suite. Superseded by the Godot CeDo Simulator but carries **tuned constants and, most importantly, a machine-variant → CeDo-line mapping worth porting.**

**Inventory (top-level):** `extruder_simulator_v2.py` (current clean core), `pcu_simulator.py` (cutter-compactor 0-D model), `barrel_screw_model.py` (screw/die physics, Carreau-Yasuda + Arrhenius, `solve_ivp`+`root_scalar` shooting method), `erema_model.py` (state machine + variant map), `simulation_config.json`, `extruder_launcher.py`, `hmi.py`, `web_bridge.py`, `extruder_live_graph.py` (= §1c), `extruder_graph.py`, `extruder_visualization.py` (pygame 2-D), `extruder_3d_visualization.py`, `unified_simulation.py`, `validation_framework.py`, `validation_run.py`, `generate_plots.py`, sensor bridge/source/sink, `extruder_realworld_input_template.xlsx` (blank; schema only, see below), `legacy/ExtruderSim.py` (deprecated redirect stub → launcher), `filamentSim/` (1-D filament cooling+drawing, Flask+VPython), `_newnew_additions/` (an `EREMA CCE 3D Simulation.html` + `PCU_schematiccally_accurate.py`), 40+ tests.

**★ erema_model.py — machine-variant → CeDo line map (PORT THIS):**
```
V1_HEAD_NO_PUMP   -> lines 1, 3A, 3B   (laserfilter, head filter, NO melt pump)
V2_HEAD_PUMP      -> line 3C           (adds a melt pump)
V3_BRITAS_PUMP    -> line 6            (Britas rotary melt filter + melt pump)
```
Barrel segment order (feed→die): feed_interface, solids_conveying, compression, melting,
melt_stabilization, filtration_interface, **Laserfilter**, homogenization_plus_zone,
**vacuum_zone_1**, **vacuum_zone_2**, metering_discharge, die_interface; downstream filter =
`HeadFilter` (V1/V2) or `Britas` (V3). MachineState enum (11 states):
OFF, PREHEAT, VACUUM_READY, MATERIAL_PRIME, MELT_BUILD, FILTER_STABLE, PRODUCTION,
FILTER_CLEANING, SCREEN_CHANGE, PURGE, SHUTDOWN, ALARM_HOLD, E_STOP.
This directly answers/confirms **Q15** (two vacuum zones + laserfilter placement: laserfilter
sits between melt_stabilization and the homogenization/vacuum zones, i.e. **early**, before the
degassing zones — so the low zone-3 temp 175 °C is a pre-filter/feed-side zone) and the
per-line downstream architecture behind the ExtruderSim/erema variants.

**Mined physics constants (`simulation_config.json` / DEFAULT_CONFIG):**
- Geometry: barrel_diameter 0.150 m, channel_width 0.130 m, helix_angle 17.7°, flight_clearance 0.0002 m, section_lengths [1.5, 1.0, 1.0, 0.5] m, channel_depth feed 0.02 m / metering 0.005 m.
- Physics: density **780 kg/m³** (melt), cp 2300 J/kg·K, mu0_ref 1.545 Pa·s, T_ref 463.15 K, Ea/R 4570.6 K, Carreau `a`=0.8, `n`=0.4, λ=1.0 s, h_barrel 100, h_loss 10 W/m²·K.
- Zone setpoints (°C, generic — NOT the operator's real profile): Z1_Feed 100, Z2_Transition 195, Z3_Metering 210, Z4_Degassing 210, Z5_Pump 255.
  → The real per-zone profile (200-235-175-240-245-250-255) is NOT in this repo; it lives in the extruderlijst (`extruder_3a_setpoints.json`). ExtruderSim's zones are placeholders.
- Die model: `P = K·Qⁿ`, K_die 2e-5, n_die 0.4. Amperage ≈ screw_torque/150. Vacuum baseline -940…-960 mbar; degrades to ≈ -700 at >3 % moisture, alarm if > -800 mbar.
- **PCU / cutter-compactor** (`pcu_simulator.py`): setpoint_temp 100 °C, loose-film bulk density starts **50 kg/m³** and rises to a cap **500 kg/m³** as knife_rpm ramps (film→crumb densification — relevant to **Q24**: pre-compactor film is loose/low-density, post-compactor crumb is dense); knife rpm clamp 120–3000; drive power ≈ (flow_kg_h/1000)·250 kW + moisture·50; latent heat water 2.26 MJ/kg; water injection 0.5 kg/s; AUTO feed refills at 1000 kg/h to a 100 kg target mass.
- **_newnew_additions/EREMA CCE 3D** UI defaults: cutterSpeed **1200 rpm**, extruder max **200** (rpm/units), maxParticles 1200 — these are that HTML's own animation defaults, not measured CeDo data.

**extruder_realworld_input_template.xlsx** — single header row, no data. Real-world logging schema (10 cols) operators were meant to fill:
`Extruder RPM (Hz) | Melt Temperature Avg (°C) | Melt Pressure (bar) | Amperage (A) | Output Rate (kg/h) | Screw Torque (Nm) | Vacuum Pressure (mbar) | Melt Filter 2 Clog (%) | Backflush Triggered? (Yes/No) | Time Since Last Backflush (s)`.
Relevant to **Q33**: a *blank* template exists; no FILLED-IN Extruderlijst with real hourly values was found in this repo.

### 1g. laser_filter_3B.jpg — Britas-style rotary disc melt filter (described)
Close-up of a heavily-fouled **rotary disc melt filter** (line-3B laser/Britas filter). A large perforated/studded circular disc (the screen carrier, studded with dozens of cylindrical bolt heads / filter posts) is caked in charred black polymer and grey sludge. A **corrugated flexible metal discharge hose** (the "corrugated bottom hose") arcs down from top-left into the filter housing — this is the contaminant/lump discharge that feeds the lump cart (§1d). Tie-wire and cabling wrap the housing; molten-sludge drips at the bottom. Confirms the corrugated-hose → lump-cart discharge geometry (memory `project_laser_filter.md`) and that line 3B ran a Britas-type rotary melt filter (supports the erema V3/Britas association, though §1f maps Britas specifically to line 6 — 3B's device here is visually the same disc-filter family).

---

## 2. F:/Citizen/CeDo office files

### 2a. Performance Overview_ CeDo Recycling (Dec 2023 – Jul 2025) (1).docx — FULL extract
**Actual path: `C:\Users\arnod\Desktop\Performance Overview_ CeDo Recycling (Dec 2023 – Jul 2025) (1).docx`** (Desktop, en-dash in filename — NOT in `F:/Citizen/CeDo/` as a prior draft assumed). An AI-assisted performance/reference document (a "getuigschrift"-substitute) about the operator. Not a plant spec, but it contains **hard plant numbers and confirmations** (citations [1]–[9] point to a CV, Google-Calendar events, `CEDO.xlsx`, and `frictie_drain_test_data.xlsx`):

- **Role/dates:** Procesoperator B (Extruder Operator), CeDo Recycling B.V. Geleen, NL, **Jan 2024 – Jul 2025**. 24/7 rotating shift; built/refined **Ignition** SCADA/HMI dashboards.
- **Shift schedule:** **5-ploegendienst** (5-team continuous), morning 07:00–15:00 / afternoon 15:00–23:00 / night 23:00–07:00, then four days off. Calendar labels like "Werken (3/10)", "Werken (1/10)"; extra shift 9 Apr 2024. (Confirms 5-ploegen + a 10-slot cycle labelling; NOT the sim's fictional "2-2-2-4".)
- **★ Line capacity (Q9/Q21):** *"design capacity is about **4,500 kg per hour** (approximately **7.5 large bales of plastic film input per hour**)"* [7]. Steady extruder **output ~1,050 kg/hour**, *"slightly above the nominal **1,000 kg/h** goal"* [8]; ~30+ tonnes per 8-h shift. → **1200 kg/hr "budget speed" and the 1000/1050 figures are per-extruder-line output; 4,500 kg/h is the whole plant/washing feed design capacity** (≈7.5 bales/h in).
- **Material/quality:** recycled **LDPE**; QA checks incl. **melt flow index** and density; two parallel extrusion lines (3A/3B).
- **★ Friction-washer spike (Q32):** On **21 Jan 2025** the operator logged a friction-washer motor load every second and captured a spike to **~196 A** on one washer motor before it stabilised [9] (source `frictie_drain_test_data.xlsx`). → A **real** friction-washer power/current export DOES exist (the frictie_drain_test); the GUIexport softstarter files remain the synthetic placeholders.
- SCADA note: custom Ignition overview screen (extruder amperage, zone temps, conveyor status, alarms); "feedbackloop verkort en scrap gereduceerd."
- **Referenced files — status corrected:** `CEDO.xlsx` (Google-Drive id `1KiE9Us2...`), the source of the capacity/output numbers, **IS on local disk** at `F:\Citizen\___tmp desktop\all\CEDO.xlsx` — now fully digested in **§2e below** (a prior draft wrongly called it off-disk). `frictie_drain_test_data.xlsx` (id `1bVcJsIl...`) is genuinely **not** on local disk (no `es` hit anywhere); still flagged for the operator.

### 2b. Randstad overwerk uren bij CeDo.xlsx — OVERTIME log (date range only)
Two sheets (Sheet1 fuller, Sheet2 trimmed). It is a personal **overwerk (overtime)** payroll tracker, **NOT** the 2-2-2-4 / 5-ploegen base shift calendar. **23** dated overtime entries starting **21 Jan 2024** (re-verified by openpyxl 2026-07-05; earlier draft said "20 … → 22 Dec 2024"). Columns (14): Datum, Dag, Start tijd, Eind tijd, Weeknummer, **Maps Location**, Uitbetaald, 28 % vervalt, Naar 50 %, Naar 100 %, Feestdag, Opgebeld, Uurloon, Teveel ontvangen (plus derived netto). Hourly rate **€15,80** through week 40 2024, **€16,43** from week 41. Totals row: te weinig ontvangen 973,25; netto 639,42. → Documents *extra* hours only (short call-ins + occasional full 8-h extra shifts) and pay disputes; does **not** encode the regular rotating pattern. Personal/payroll — no plant data.

### 2c. CeDo.accdb — Access DB (parsed; essentially EMPTY of plant data)
pyodbc unavailable (only the "SQL Server" ODBC driver is installed; no "Microsoft Access Driver"). Parsed with the pure-Python **`access_parser`** instead. Catalog = 17 tables, all `MSys*` system tables **except one**: `f_765C829A129E44B395814290EE407800_Data`, which holds a **single row** whose `FileData` is a zlib blob named **`Office Theme.thmx`** (the default Office theme resource in `MSysResources`). There are **no CeDo/plant tables, forms, queries, or measurement rows** — this is effectively a blank/fresh .accdb. Disposition: **parsed, no plant data.**

### 2d. 6/merged_data/CeDo Big StressSheet.xlsx — line-6 washline sample → JSON
Sheets: `Sheet1`/`Sheet2`/`Sheet3`/`Sheet4` all **empty**; data in **`merged_side_by_side_part1`** (title cell: *"Last updated: Apr 08, 2025 12:56 PM"*). **500 data rows**, laid out as **7 month-blocks side by side** (2024-08 … 2025-02), each block = `timestamp` + 5 tags: `flotation_level, dryer_left_amp, dryer_right_amp, grinder_amp, flotation_flow`. Each month's timestamps span only ~1 hour (e.g. 2025-01 covers 10:39:38–11:46), and seconds are skipped — so this is a **decimated/sampled first-~500-rows export**, a small subset of the full 1 Hz washline-6 data already summarised in `src/data/plant/trends/washline6_1hz_summary.json`. Written to **`src/data/plant/stresssheet_line6.json`** with per-month/per-tag n/min/max/mean/median. Highlights (from the JSON): flotation_level ~44–56 %; grinder_amp ~120–180 A; dryer amps ~70–110 A; flotation_flow ~20–110 L/min (with a stray negative -30 in Feb = sensor noise). 2024-08 block has timestamps only (all tag values blank), matching the manifest note that August only had flotation_level and it starts 21 Aug. Confirms these are **line-6 (wash-line) tags** (Q29/Q31 context — same `6_x` washline family).

### 2e. ★★ CEDO.xlsx — the master THROUGHPUT-BUDGET spreadsheet (FULL transcription — NEW, was mis-flagged off-disk)
**Path: `F:\Citizen\___tmp desktop\all\CEDO.xlsx`** (10,561 B / ~10 KB; single sheet `Sheet1`, range A1:M28; last modified 31 May 2024 — re-verified by openpyxl parse 2026-07-05). This is the actual Google-Drive `CEDO.xlsx` the Performance docx cites [7][8] — the operator's own **plant throughput budget + checklist-value reference**, single sheet `Sheet1`. It is the *single most load-bearing miscellaneous source found in this run*: it ties the sim's per-equipment checklist ranges to a kg/h loss cascade from bale intake to extruder. Verbatim by block:

**Block A — `Equipment` | `Checklist waarden` (the on-shift setpoint/range reference — reconciles FORM sheets):**

| Equipment | Checklist waarde | Notes / open-Q link |
|---|---|---|
| Shredder 1 | `30-60` | rpm range — reconciles **Q18** (lijn-1 shredder 32-50 vs "Shredder 1 35-60"): the reference range here is **30-60**. |
| Bunkerspeed | `200-800` | **Q16** confirmed: bunkersnelheid is a **unitless 200–800 HMI number** (matches HMI screen §1e: Pers-alleen 200 … running ~875; the "800" here is the checklist top of range). |
| Bunkerheight | `115` | bunker-height setpoint (unitless / cm), single value 115. |
| Magneetbanden | `x` | (no numeric setpoint — pass/check only) |
| Titech/Tomra 1 %PE | `50%-100%` | **Q28**: TITECH sort target = **%PE 50–100 %** (purity band the ejector holds). |
| Titech/Tomra 2 %PE | `50%-100%` | second TITECH, same %PE band. |
| Shredder 2 | `55` | rpm (single setpoint 55). |
| Verlies transportbanden | `x` | (conveyor loss — a modelled loss line, see Block B) |
| Schuifband 3A/3B (omwisseltijden?) | `?` | the **switch-belt / conveyor-12** changeover times — operator's own open question (matches transportbanden notes §1b: ~10 cm/s jog, ±1.5 m). |
| Doseerschroef VSS | `50-100` | **Q3 context**: VSS (voorsilo) dosing screw range 50–100. |
| Doseerschroef mengsilo | `x` | mengsilo (mix-silo) dosing screw — **Q3**: listed as a *separate* line item from Doseerschroef VSS, so they are tracked separately even if a motor (M11a) is shared. |
| Extrudersilo | `x` | extruder silo (pass/check). |
| Compactorband | `30s` | compactor infeed belt cycle **30 s** (matches HMI "Vertraging 30 sec" §1e and FORM "Compactorband 30s"). |
| Compactor | `150kW-250kW` | **Compactor drive power 150–250 kW** — matches ExtruderSim PCU drive-power model (§1f: ~(flow/1000)·250 kW). |
| Extruder rpm | `60-120` | screw rpm **60–120** (matches extruderlijst; ExtruderSim EREMA CCE HTML default 200 is animation-only). |
| Extruder intrekschuif | `25%-100%` | extruder infeed slide (intrekschuif) **25–100 %** open. |
| Extruder output | `1000kg/u` | **nominal extruder output 1000 kg/h** — matches docx "1,000 kg/h goal". |
| Afkeurstation | `>470 & <5/10 gas` | **Q19-adjacent**: reject/afkeurstation gate = **stortgewicht/bulk-weight > 470** AND **gas < 5/10** (the ">470" bulk-weight threshold + a 0–10 gas index; ties to FORM "Afkeurstation >470 & <5/10 gas"). |

**Block B — `Hypothetisch` + `Doorzet` (the throughput-LOSS cascade, bale intake → extruder) — answers Q9/Q21/Q19/Q24:**

Row-by-row (col D `Hypothetisch` assumption → col E `Doorzet` = surviving throughput):

| Stage | Hypothetisch (assumption) | Doorzet (surviving kg/h) |
|---|---|---|
| Shredder 1 (intake) | **7,5 balen per uur** (7.5 bales/h in) | **4500 kg/u** (= 600 kg per bale × 7.5) |
| Magneetbanden (magnet belts) | — | **4300 kg/u** (−200: 4 bins × ~ ) |
| Titech/Tomra 1 %PE | **0.7** (70 % PE passes) | **3010 kg/u** (4300 × 0.7) |
| Titech/Tomra 2 %PE | **0.7** (70 % PE passes) | **2107 kg/u** (3010 × 0.7) |
| Shredder 2 | **12,5 kg/u** (overflow loss) | **2094,5 kg/u** |
| Verlies transportbanden | **12,5 kg/u** (belt loss) | **2082 kg/u** |

→ **Q9/Q21 fully resolved with the operator's own arithmetic:** film **input** = 7.5 bales/h @ **600 kg/bale = 4500 kg/h** (matches docx). After magnet + two 70 %-PE TITECH cuts + shredder/belt losses, **~2082 kg/h of clean flake** survive to the wash/extrude side. That flake stream splits across the two extruder lines at ~**1000–1050 kg/h each** (docx). So: **4500 kg/h = whole-plant bale-film feed; ~1000/1050/1200 kg/h = per-extruder-line output;** the ~2082 kg/h is the intermediate sorted-flake budget. The **two 0.7 TITECH factors** are the dominant loss (4300→2107, ~51 %) — i.e. incoming bales are only ~49 % on-spec PE film after sorting.

**Block C — `Example calc` (mini extruder rpm→output→quality lookup, cols I–M):** a hand table pairing extruder **rpm → output kg/h → quality**, confirming the rpm/output/quality coupling the sim needs:

| time | extruder rpm | extruder output (kg/h) | quality |
|---|---|---|---|
| 16:00 | 123 | 1075 | good |
| 18:00 | 123 | 1075 | bad |
| 19:00 | 60 | 612 | medium |
| 20:00 | 80 | 700 | medium |
| 21:00 | 120 | 1050 | good |
| 22:00 | 100 | 875 | medium |

→ Rough linear coupling **~8.7 kg/h per rpm** (1075/123 ≈ 612/60 ≈ 8.7–10.2). Note two identical rpm/output rows (123→1075) tagged `good` vs `bad` — quality is **not** rpm-determined alone (moisture/contamination also drive it). Useful sim constant: **rpm × ~8.7 ≈ kg/h**, target ~1000–1075 kg/h in the "good" band (120–123 rpm), degrading below.

**Block D — logistics/rijden budget (cols F–G + J–K, rows 23–28) — bale-truck movements per shift:**
- `Sorteerlijn = Berekend` (sort line = calculated); throughput restatement: **7,5 balen per uur (60 per dienst) = 4500 kg/u (600 kg per baal)**; **Gevulde bunker (10 min) = 750 kg materiaal**; **4 volle bakken magneetbanden = 200 kg/u (400 kg per container)**; **Shredder 2 overlopen = 12,5 kg/u (100 kg per dienst)**.
- Truck/forklift movement budget (col F=stream, G=kg or count): `a`=1000, `b`=1000, `stort`=350, `hbc-40`=0, `was`=100 → **SUM = 2450**. Side note (cols J–K): `15 alba`→30 balen, `10 omrin`→30 balen, `16 reject`→48 balen, `15+10-16`, "9 extra rijden als iedere reject nieuwe balen binnen" (9 extra forklift runs if every reject means new bales in), and *"balen kapot knippen en met merlo invoeren?"* (cut bales open and feed with the Merlo telehandler?). → operator's own **material-logistics / forklift-run model** — directly feeds the sim's "can't-escape-your-shift" bale-supply loop; the **Merlo telehandler** and per-supplier bale counts (alba/omrin/reject) are named here.

**★ Bulk / bale numbers extracted (Q19 / Q24):** **600 kg per bale** (film bale); **gevulde bunker (10 min) = 750 kg**; **magnet-belt container = 400 kg per container** (200 kg/h fill = 4 bins); Shredder-2 overflow **100 kg per dienst**; **stortgewicht (bulk weight) reject threshold >470** (unitless bulk-weight index, per Afkeurstation gate). Suppliers named: **alba, omrin** (feedstock), **reject** stream, **hbc-40**, **was** (wash).

Cross-ref: this reconciles the FORM-007/008 checklist ranges (`checklist_*.md`), the extruderlijst (`extruder_3a_setpoints.json`), `slow_running.md`, and `densities.md`. It should be promoted out of "miscellaneous" into a first-class plant doc on the next pass.

---

## 3. Relevance sweeps (names + quick peek only — NO plant material found)

All three swept directories are **personal/academic**, containing **zero CeDo/plant** documents
(grepped names for cedo/extrud/recycl/titech/tomra/wasser/shredder/silo/geleen/ldpe/scada/hmi/pellet/flotation — no hits in any):

| Directory | Contents | Plant material? |
|---|---|---|
| `F:/Citizen/Downloads/Phone Files (1)` | 157 entries: **62 PDFs** (UWV/WW & Ziektewet letters, invoices, boarding passes, bank statements, patient letters) + **4 .webp** (`1017–1020.webp` = WhatsApp "Sweet Dreams" greeting **stickers**, verified — not photos) + Maastricht **BBS** university coursework (.docx/.xlsx/.pptx), audio, zips, log txts | **None** |
| `F:/Citizen_AI_Organized/Unsorted_AI_Files` | 14 PDFs: medical/pharma papers (drug labels, `019429s035lbl.pdf`, journal PDFs), a voorschot-factuur, hash-named PDFs | **None** |
| `F:/Citizen/UNSORTED` | 16 PDFs: mixed personal (Bonnen, BagageKV, Eiskarte2022, CYP2D6, actigraphy, regulatory F-numbered docs) | **None** |

---

## Open-question hits found in this sweep (doc id + quote)

- **Q9 / Q21 (line capacity / budget speed):** Performance docx [7][8] *and* **CEDO.xlsx (§2e)** — docx: *"design capacity is about 4,500 kg per hour (approximately 7.5 large bales of plastic film input per hour)"* and *"output reaching around 1,050 kg/hour … slightly above the nominal 1,000 kg/h goal."* CEDO.xlsx gives the full loss cascade: **7.5 bales/h × 600 kg = 4500 kg/h** film in → magnet 4300 → TITECH1 ×0.7 = 3010 → TITECH2 ×0.7 = 2107 → −shredder/belt = **~2082 kg/h clean flake**, which splits to ~**1000–1050 kg/h per extruder line**. → 1000/1050/1200 = per extruder line; 4,500 = whole-plant film feed; ~2082 = sorted-flake intermediate.
- **Q18 (shredder rpm):** CEDO.xlsx (§2e) checklist reference = **Shredder 1 `30-60`**, Shredder 2 single setpoint **55** — reconciles the differing FORM values (lijn-1 32-50 vs Shredder 1 35-60) toward a 30-60 band.
- **Q19 (stortgewicht / bulk weight):** CEDO.xlsx (§2e) — Afkeurstation gate **`>470 & <5/10 gas`**: bulk-weight index **>470** (unitless) with a gas index **<5/10**. Bale = **600 kg**; gevulde bunker (10 min) = **750 kg**; magnet container = **400 kg**.
- **Q28 (TITECH sort target):** CEDO.xlsx (§2e) — both TITECH/Tomra units hold **%PE 50–100 %**, and the throughput model applies a **0.7 (70 % PE pass)** factor per unit.
- **Q15 (laserfilter placement / zones):** `erema_model.py` — segment order places **Laserfilter** right after `melt_stabilization`/`filtration_interface` and **before** `homogenization_plus_zone` + `vacuum_zone_1/2`; two vacuum (degassing) zones exist downstream of the laserfilter.
- **Q16 (Bunker speed 200–800 unit):** HMI_sorteerlijn_bunker.jpg + **CEDO.xlsx (§2e, `Bunkerspeed 200-800`)** — `bunkersnelheid` HMI field: normal setpoints **875** (Beide/Zonder 3A/Zonder 3B), `Pers alleen` **200**; CEDO.xlsx confirms the checklist band is literally **200–800**. A unitless HMI bunker-speed number (compactor-only floor 200 → running ~875), not kg/h/rpm.
- **Q24 (feed vs crumb density):** `pcu_simulator.py` — loose film bulk density starts **50 kg/m³**, densifies to a **500 kg/m³** cap through the cutter-compactor → pre-compactor = loose film (low density), post = dense crumb.
- **Q25 (BOPP on 3A/3B):** No evidence in this sweep; Performance docx names **LDPE** as the feed, two parallel lines — no BOPP mention.
- **Q29 / Q31 (line-6 / "3c" tags):** Big StressSheet + Performance docx confirm the `6_x` **wash-line** family (flotation/dryer/grinder) and Ignition SCADA; consistent with the manifest's open Q3 (3c = SCADA node hosting wash line 6).
- **Q32 (real friction-washer power export):** Performance docx [9] — 21 Jan 2025 second-by-second friction-washer load test, spike **~196 A** (source `frictie_drain_test_data.xlsx`, off-disk). A real export exists; GUIexport softstarter files stay synthetic.
- **Q33 (filled-in Extruderlijst):** ExtruderSim's `extruder_realworld_input_template.xlsx` is **blank** (header only). No real filled hourly Extruderlijst found in these sources.
- **Shift calendar (memory / sim pillar context):** Performance docx = **5-ploegendienst**, 07-15 / 15-23 / 23-07 + 4 off, "Werken (n/10)" labels; Randstad xlsx = overtime only. Neither confirms a literal "2-2-2-4" — that remains the sim's design abstraction, not a documented real pattern.

## Notes for the operator (referenced-but-absent files to locate)
1. **`CEDO.xlsx`** (Google-Drive `1KiE9Us2cs7gGYngngKTv-CaD1_Lt6PHs`) — the actual source of the 4,500 kg/h capacity + 1,000/1,050 kg/h output figures. Not on local disk in swept dirs.
2. **`frictie_drain_test_data.xlsx`** (Google-Drive `1bVcJsIlnjXYlVN3wtAZuhDB1JdrBbzOo`) — the real 21 Jan 2025 friction-washer 1 Hz current log (196 A spike). Answers Q32 fully if retrieved.
3. **`simulator_service.py`** — the singleton `extruder_live_graph.py` (§1c) imports isn't on Desktop; it's inside the ExtruderSim stack (`extruder_simulator_v2.ExtruderSimulator`), wire via a small `simulator_service` shim if that live graph is ever revived.
