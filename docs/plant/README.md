# Plant Documentation Index — CeDo Geleen LDPE Recycling Plant

Extracted 2026-07-04 from real plant documentation by a multi-cluster extraction run,
then audited by a completeness critic (this file). The plant had 5 lines (1, 3A, 3B, 3C, 6);
3A/3B run EREMA extruders. Source docs are mostly Dutch; digests keep Dutch terms verbatim
with an English gloss on first use.

**Prime directive of the whole corpus: NO DATA LOSS.** Digests are full transcriptions,
not summaries. Anything illegible is transcribed best-effort and marked `[unsure: ...]`
(MD) / `"unsure": true` (JSON). Nothing is invented.

## Source directories (raw truth)

| Location | Contents | Status |
|---|---|---|
| `C:/Users/arnod/Documents/CeDo_Simulator_data/` | 22 PDFs (photos/scans of printed plant docs) | All 22 extracted. Subfolder `Netjes/` is **empty** (0 files). |
| `F:/Citizen/Documents/CeDo/` | 234 files: EREMA/WinCC trend CSVs (3A: 81, 3B: 80 + `extruder_real_world_data.zip` with 2 recovered), GUIexport (32), washer6 (14), Random Exports (16 CSVs + `3c_tags.xlsx` + `scriptje.txt` + Portable Python), root PNGs/zip/installers, `Merged_with_February - Copy.txt` (487 MB) | All families processed or dispositioned; see `cedo_data_manifest.md`. |

**Source of truth for raw trends is F:/Citizen/Documents/CeDo — do NOT delete it.**
The JSONs under `src/data/plant/trends/` are summaries and downsampled curves
(median-per-bucket); any future need for full-resolution data (e.g. second-by-second
event replay, new percentiles, exact spike timestamps) must go back to the raw CSVs.
`docs/plant/cedo_data_manifest.md` is the per-file disposition map of that drive.

## Index — digests (docs/plant) and machine data (src/data/plant)

### Line flow topology
| Digest | JSON | Source PDF(s) |
|---|---|---|
| `lijn_1_flow.md` | `line_flow_graphs.json` (lines 1/3A/3B combined; 137 nodes, 155 edges) | `lijn_1_flow_diagram.pdf`, `lijn_1_flow_diagram_incusief_water.pdf` |
| `lijn_3a_flow.md` | (same JSON) | `lijn_3A_flow_diagram.pdf`, `lijn_3A_flow_diagram_inclusief_water.pdf` |
| `lijn_3b_flow.md` | (same JSON) | `lijn_3B_flow_diagram.pdf`, `lijn_3B_flow_diagram_incusief_water.pdf` |

### Water circuits
| Digest | JSON | Source PDF(s) |
|---|---|---|
| `water_circuit_3a_la1.md` | `water_circuits.json` (all 4 circuits; incl. cross-connections between lines 1/3A/3B) | `Water_circuit_3A_LA1.pdf` |
| `water_circuit_3a_la2.md` | (same JSON) | `Water_circuit_3A_LA2.pdf` |
| `water_circuit_blauwe_tank.md` | (same JSON; 14 blocks, 28 edges) | `Water_circuit_blauwe_tank.pdf` |
| `water_circuit_kanaalwater.md` | (same JSON) | `Water_circuit_kanaalwater.pdf` |

### Checklists, forms, maintenance, troubleshooting
| Digest | JSON | Source PDF(s) |
|---|---|---|
| `extruderlijst_3a.md` | `extruder_3a_setpoints.json` | `Extruderlijst_3A.pdf`, `Extruderlijst_3A_clean_A4.pdf` (content-identical variants) |
| `checklist_lijn1.md` | `shift_checklists.json` (FORM-007, 20 rows — covers lijn 1 AND 5) | `Checklist_1.pdf` |
| `checklist_3a_3b.md` | `shift_checklists.json` (FORM-008, 29 rows) | `Checklist_3A_3B.pdf` |
| `onderhoud_lijn1.md` | `maintenance_lijn1.json` (FORM-012; 14 sections, 47 tasks, 180 bar threshold) | `Onderhoud_1.pdf` |
| `slow_running.md` | `troubleshooting_slow_running.json` (budget speed 1200 kg/hr) | `Slow_running.pdf`, `Slow_running_2.pdf` |
| `voertuig_controle.md` | `vehicle_inspection.json` (FORM-023) | `Voertuig_controle.pdf` |

### Densities, layout, sorting
| Digest | JSON | Source PDF(s) |
|---|---|---|
| `densities.md` | `material_densities.json` (PCU in/out bulk densities) | `for_claude_data_needed_densities.pdf` |
| `floor_plan_edits.md` | `floor_plan_edits.json` (declarative target layout, no scale/dimensions) | `floor_plan_edits_needed.pdf` |
| `titech_tomra.md` | `titech_tomra_layout.json` (pages 1–2 of a 3-page doc; **page 3 was never scanned**) | `Titech_Tomra_render.pdf`, `Titech_Tomra_schematic.pdf` |

### Trend data (F: drive)
| Digest | JSON | Source |
|---|---|---|
| `trends_overview.md` | `trends/extruder_trends_summary.json` + 16 downsampled curve files `trends/3a_*.json` / `trends/3b_*.json` (8 signals per extruder, median-per-bucket) | `Gegevens extruder 3A` / `3B` EREMA CSVs (~2.07M rows) |
| `trends_overview.md` | `trends/washer6_power_summary.json` | `GUIexport/` (32 files — **synthetic placeholders**, not real measurements) + `washer6/` (14 change-of-value logs) |
| `trends_overview.md` | `trends/washline6_1hz_summary.json`, `trends/washline6_feb2025_curves.json` | `Random Exports/` 1 Hz wash-line tag exports (~17M rows) |
| `line3c_scada_tags.md` | `line3c_scada_tags.json` (1084 rows, 1056 unique tags) | `Random Exports/3c_tags.xlsx` |
| `cedo_data_manifest.md` | — | Per-file disposition of everything on `F:/Citizen/Documents/CeDo` |

## How the sim should consume this

- **`material_densities.json` → BaleDefs / material resources.** Bulk density of loose
  cut film entering the PCU (cutter-compactor) and of compacted crumb leaving it drives
  bale mass, hopper fill volumes, and conveyor throughput conversions (kg/h ↔ m³/h).
- **`extruder_3a_setpoints.json` → `Extruder3A.tres` / `Extruder3B.tres`-style machine
  resources.** Field list = what the operator logs hourly; numeric targets come from
  Checklist FORM-008 (sourced per entry). Combine with the trend envelopes below for
  realistic operating bands rather than single setpoints.
- **`trends/*.json` → machine behaviour curves.** `extruder_trends_summary.json` gives
  per-signal operating bands (p5/p50/p95, zero fractions, rt_off events) for the EREMA
  state machine (startup ramps, steady state, trips); the 16 `3a_*/3b_*` curve files are
  ready-made downsampled time series for in-game trend screens and for tuning noise/spike
  models. `washline6_1hz_summary.json` + `washline6_feb2025_curves.json` do the same for
  the line-6 wash line (flotation flow/level, dryer amps, grinder amps). Anomaly episodes
  (faulty thermocouple, output surges during scale swaps) are candidate scripted events.
- **`line_flow_graphs.json` → LineFlow topology validation.** The node/edge graphs for
  lines 1/3A/3B are the authoritative machine order; a sim-side test should assert the
  in-game line topology matches these graphs (referential integrity already validated).
- **`water_circuits.json` → water system sim.** Circuit membership, cross-connections
  between lines, and the blauwe tank (blue tank) hub define which machines share water
  quality/temperature state — needed for "dirty water cascades" gameplay.
- **`shift_checklists.json`, `maintenance_lijn1.json`, `vehicle_inspection.json` →
  shift-task and maintenance gameplay.** Checklist rows become per-shift tasks; the
  `kritisch` flags mark tasks whose neglect should trigger failures; FORM-023 feeds the
  vehicle pre-use inspection loop.
- **`troubleshooting_slow_running.json` → diagnosis minigame.** Cause tree for output
  below the 1200 kg/hr budget speed; remedies that are null in the source stay null.
- **`floor_plan_edits.json` + `titech_tomra_layout.json` → world layout.** Declarative
  target state for the floor plan and the TITECH/TOMRA sorter arrangement.
- **`line3c_scada_tags.json` → tag naming.** Note the `scada/3c` tree references line-6
  equipment numbers — use it for authentic SCADA screen labels.

## Open questions for the operator

Status updated 2026-07-05 after digesting the full 379-PDF SWI/plant-doc corpus into
`swi/` (see `swi/INDEX.md`). The broader operator open-questions **Q1–Q33** (ZSS, C1,
water routing, HMI units, throughput, laserfilter zones, etc.) each have a resolved
status + evidence in **`src/data/plant/question_answers.json`** (15 answered, 16 partial,
2 unanswered). The seven data-scan items below are updated in place:

1. **TITECH/TOMRA page 3** — **ANSWERED.** The full 3-page "Werking Titech tomra" set is
   now digested (`Werking-Titech-tomra-p1/p2/p3__174/173/172`), incl. the page-3 PolySort
   UHR NIR content and the AUTOSORT FLYING BEAM + EM-sensor principle. See Q28.
2. **No filled-in Extruderlijst** — **STILL OPEN.** `FORM-extruderlijst-lijn3A-blank__233_CeDo43`
   confirms the Lijn-3A Extruder lijst is a blank template only; real setpoints are still
   derived from FORM-008 + EREMA trend envelopes. See Q33.
3. **GUIexport CSVs are synthetic** — **STILL OPEN.** No real softstarter/frictiewasser
   power export was found in the SWI corpus; live electrical data does exist on the LIJN 3C/6
   BluPort panels (kW/A/kWh/kg/power-factor) but not as an exported file. See Q32.
4. **[unsure] flow/floor-plan items** — **MOSTLY ANSWERED.** The line-flow "inclusief water"
   diagrams and the water-circuit training slides decode the blue routing: **ZSS** =
   plant-wide water-treatment/supply node feeding the Blauwe tank (Q1); full water routing
   ZSS/EOP→Blauwe tank→wash pumps, La1/La2 circuits, pellet/koeltoren loops, Riool naar EOP
   (Q5); **C1** = Pomp C1 (Q2). A few pixel-level `[unsure]` readings remain marked in the
   individual digests. See Q1, Q2, Q5, Q11, Q12.
5. **`3c` vs line 6 naming** — **ANSWERED.** LIJN 3C and LIJN 6 are two SEPARATE EREMA
   BluPort **regranulation extruder lines** (identical HMIs, distinct engraved plates), NOT
   a wash-line SCADA host. The wash line has its own SIMATIC WinCC SCADA (`256_CeDo51`). The
   `scada/3c` tag-tree root is a tag-export naming artefact, not a physical wash host. See Q29.
6. **`february_gap_filled.csv` empty / `2024_09.csv` mangled header** — **STILL OPEN.**
   Data-provenance question on the F: raw trends; not resolvable from the SWI scans.
7. **Extracted_Images.zip GUI frames** — **ANSWERED (superseded).** The EREMA HMI frames are
   now transcribed frame-by-frame across the `OTHER-erema-hmi-*` / `PHOTO-erema-bluport-*`
   digests (LIJN 3C 194–216, LIJN 6 219–226, melt-pump/trend frames), giving live values,
   units, recipes and alarm ladders. See Q9, Q15, Q30, Q31.

**See also:** `swi/INDEX.md` (human index of all digests, grouped by line then topic) ·
`src/data/plant/swi_index.json` (machine index, ~190 entries) ·
`src/data/plant/question_answers.json` (Q1–Q33 with evidence + confidence).

## Fidelity issues found and FIXED (2026-07-04)

Independent re-verification against the raw sources flagged four issues after the initial
extraction; **all were corrected the same day** (details below for the audit trail). The
underlying statistics/tables were otherwise verbatim-correct.

- `maintenance_lijn1.json` + `onderhoud_lijn1.md`: two `kritisch` flags were flipped
  ("Ventilatoren 10a/10b — waaierhuis reinigen" is NOT critical; "Waterfilters
  reinigen/wisselen" IS critical — verified against 8×-zoom crops of the source). The
  form's typo `leidingevende` is now kept verbatim with a [sic] note. **Fixed.**
- `trends/extruder_trends_summary.json` + `trends_overview.md`: the 3B
  faulty-thermocouple and output-surge anomaly notes understated the events; both now
  carry the full recount (155 samples ≥300 °C across multiple episodes; 15 output samples
  >1500 kg/h across 3 clusters). Stats were always exact. **Fixed.**
- `trends/washline6_1hz_summary.json`: min/max/mean (and null/negative/zero fractions)
  have been **recomputed exactly on the full data** (full-scan, 2026-07-04); only
  p5/p50/p95 + nonzero_band remain from the 1/3 systematic sample, and each column's
  stats_note now says so. The full-scan caught extremes the sample missed (e.g. January
  flotation_flow min −636, December dryer_left max 981). **Fixed.**
- `cedo_data_manifest.md`: extruder CSV counts corrected — **81** on disk under
  `Gegevens extruder 3A`, **80** under `3B` (82 processed counting the 2 recovered from
  `extruder_real_world_data.zip`). **Fixed.**
