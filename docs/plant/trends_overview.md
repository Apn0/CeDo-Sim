# Plant trend data overview — real measurements, CeDo Geleen

**Sources:** `F:/Citizen/Documents/CeDo/` (EREMA/WinCC Archivspeicher exports for extruders 3A & 3B; 1 Hz wash-line exports; Grafana-style change-of-value logs)
**Extraction date:** 2026-07-04
**Machine-readable outputs:** `src/data/plant/trends/` (summaries + downsampled reference curves), `src/data/plant/line3c_scada_tags.json`
**All numbers below are computed from the raw files — nothing is estimated or invented.**

---

## 1. What data exists

| Dataset | Machines | Span | Cadence | Rows |
|---|---|---|---|---|
| EREMA Archivspeicher (archive memory) CSVs, 8 signals | Extruder 3A | 2023-06-19 15:44 → 2023-06-28 09:54 | 2–12 s per signal | ~1.03 M |
| EREMA Archivspeicher CSVs, 8 signals | Extruder 3B | 2023-06-19 09:29 → 2023-06-28 09:53 | 2–12 s per signal | ~1.04 M |
| 1 Hz wash-line tag exports ("Random Exports") | Line-6 wash line (SCADA tree `scada/3c`) | 2024-08-21 → 2025-03-31 (Jan gap: only 17–31 Jan) | 1 s | ~17 M |
| Grafana change-of-value logs (`washer6/`) | Wash-line units 6_3, 6_6, 6_11, 6_14l/r, 6_18 | 2024-10-17 → 2025-03-31 | on change | ~160 k |
| `GUIexport/` softstarter frictiewasser (friction washer) "power measurements" | Units 6_4l/4r/9l/9r | nominally 2024-08 → 2025-03 | — | 10 rows/file, **synthetic** |

Extruder signal names (folder names, Dutch, with PLC VarName):

| Folder (Dutch) | PLC tag leaf | Unit guess | Gloss |
|---|---|---|---|
| Output | `throuhput_int` (typo verbatim in PLC) | kg/h | scale throughput |
| Compacter temperatuur beneden | `lower_temp_cutter_compac` | °C | cutter/compactor lower-zone temperature |
| Druk voor kopfilter (3A) / Smeltdruk voor kopfilter (3B) | `MD_vor_SF2` | bar | melt pressure before kopfilter (head filter, SF2) |
| Smelt temperatuur voor meltfilter | `melt_temp_in_front_of_mf` | °C | melt temperature before meltfilter |
| Smeltdruk voor meltfilter | `pressure_in_front_of_mf` | bar | melt pressure before meltfilter |
| Snelheid hoofdmotor | `speed_extruder` | rpm | main-screw speed [unsure: could be % of max] |
| Vermogen compactor/compacter | `power_CC_Archive` | kW | cutter/compactor drive power [unsure: could be A] |
| Vermogen hoofdmotor | `load_extruder` | % | main-motor load; 0–119 range suggests % of nominal [unsure: could be kW/A] |

CSV format quirks handled: delimiter varies per file (`;` or `,`); `TimeString` (d-m-Y H:M:S) is often empty, so the canonical clock is `Time_ms` = Excel serial date × 1e6 (cross-checked against TimeString where present: max 1 s difference); decimal commas; `$RT_OFF$` rows (Validity=2) are WinCC runtime-stop markers, excluded from stats. For 3B kopfilter, two files missing on disk (`_7_4`, `_7_14`) were recovered from `extruder_real_world_data.zip`.

## 2. Normal operation envelopes — extruders (p5–p95 of nonzero running data)

| Signal | 3A band (p50) | 3B band (p50) |
|---|---|---|
| Output [kg/h] | 595–1082 (908) | 534–1263 (799) |
| Compacter temp beneden [°C] | 114–128 (122) | 108–130 (124) |
| Smelt temp voor meltfilter [°C] | 247–265 (257) | 230–257 (246) |
| Druk/Smeltdruk voor kopfilter [bar] | 103–173 (140) | 106–166 (143) |
| Smeltdruk voor meltfilter [bar] | 6–280 (271) ‡ | 7–190 (177) ‡ |
| Snelheid hoofdmotor [rpm] | 60–118 (95) | 60–124 (110) |
| Vermogen compactor [kW] | 128–229 (204) | 96–245 (208) |
| Vermogen hoofdmotor [%] | 53–79 (65) | 55–85 (73) |

‡ meltfilter-pressure exports cover only ONE ~72–73 minute session (28 Jun 2023 ~08:41–09:54) on both machines; the wide band includes the session's low-pressure start. Steady values: 3A ~271 bar, 3B ~177 bar.

Reading for the sim:
- **Typical output ~800–900 kg/h per EREMA, peaking ~1100–1250 kg/h.** Idle floor on the scale is ~4 kg/h (3A) / 0 (3B).
- Melt at the meltfilter runs **~250–260 °C**; compactor lower zone **~110–130 °C**.
- Kopfilter pressure cycles inside **~100–175 bar**; pressure before the meltfilter is higher on 3A (~270 bar) than 3B (~180 bar).
- Main motor spends 3–4 % of time at zero (stops); compactor power dips to zero less often (~1 %).
- Cadence differs per archive: pressures/compactor power ~2.4 s, motor speed/load ~6 s, temps/output ~11–12 s.

## 3. Anomalies worth gameplay attention (extruders)

1. **Faulty melt-temperature sensor, 3B — 155 samples ≥300 °C across the dataset**, interleaved with normal ~256 °C readings — a loose/failing thermocouple signature (value teleports, process obviously didn't). Largest episode 23 Jun 03:18–07:59 (129 samples ≥300 °C; by hour 03h:5, 04h:61, 05h:23, 06h:14, 07h:26). Second episode 24 Jun 21:45–22:01 (17 samples 300–2237 °C plus 11 zero readings). Minor tails: 5 samples 25 Jun ~05h, 2 samples 26 Jun 13:06. Great "sensor lies to you" event — and it recurs over multiple shifts.
2. **Scale surges, 3B Output — 15 samples >1500 kg/h during otherwise ~800 kg/h operation** (batch dumps on the weigher). First surge 25 Jun 17:59:46–18:00:06 (2065 → 2446 → 1788 kg/h); larger cluster 25 Jun 18:23:14–18:26:45 (7 samples, 1530–2282 kg/h); singles 26 Jun 19:34 / 19:58 / 20:26 (1996 / 1788 / 2146 kg/h).
3. **Stops/startups.** `speed_extruder` and `load_extruder` drop to 0 for ~3–4 % of samples on both machines; compactor power shows the same stops. Startup of the meltfilter-pressure session shows pressure climbing from ~5 bar to steady state within the hour.
4. **WinCC runtime stops (`$RT_OFF$`):** 1–2 per signal over the 9 days, i.e. the SCADA logger itself went down occasionally — an authentic "the trend has a hole in it" moment.
5. **3A max output spike 1644 kg/h** (26 Jun 15:13) — smaller cousin of anomaly 2.

## 4. Wash line (line 6) — 1 Hz dataset, Aug 2024 → Mar 2025

Columns: `flotation_flow` [L/min, from Jan 2025], `flotation_level` [unit unknown, plausibly %], `dryer_left_amp` / `dryer_right_amp` [A], `grinder_amp` [A]. Full per-month stats in `washline6_1hz_summary.json`; February reference curves in `washline6_feb2025_curves.json`.

Normal operation (nonzero p5–p95):
- **flotation_level:** Aug 43–61 (p50 51) narrowing to 44–48 (p50 46) from Nov onward — level control got tighter over the campaign.
- **dryer amps:** ~62–115 A, p50 ~78–100 A; right dryer consistently runs a few A above left. Inrush/fault spikes to 700–930 A (softstarter starts).
- **grinder (snijmolen/maalmolen) amp:** 125–200 A, p50 ~144–158 A, spikes to ~960 A.
- **flotation_flow:** 7–110 L/min band, p50 ~19 L/min, strongly bimodal (see the operator's own screenshot: ~15 L/min baseline with excursions to 80–140 L/min about every 15–25 min — flush/dump cycles). 4–11 % of samples are negative (down to −176) — flowmeter noise/backflow; a real sim should show that jitter.
- Null fractions are high (35–80 % per column) because tags only logged while the GUI/collector ran; the 1 s grid is not fully populated.
- **Flow-spike ↔ dryer-amp correlation** (see `output.png`, operator analysis of 30 Mar 2025): flow spikes to ~80 L/min coincide with dryer-right amp rising a few A within 1–2 minutes.

## 5. Change-of-value logs (`washer6/`), Oct 2024 → Mar 2025

14 files, Grafana export format (`#NAMES/#TYPES/#ROWS` header, US timestamps). Values are small integers 0–6, unit unknown (likely A on small drives, or a state/step code — operator to confirm). Notable: `63_fqafvoerschroef 2` logs 145 k changes (chatty signal, values 0–5, p50 3); the 6_14 dryer scraper/rotary-valve motors and 6_18 fan logged constant 0 (372–374 change events each, all zero). Full stats per file in `washer6_power_summary.json`.

## 6. Known gaps / caveats

- `GUIexport/powermeasurements_washer6_*` (32 files): every file is a 10-row 0..9 integer ramp starting at second 0 of the month — **placeholder/GUI-test exports, no real measurement content.** Real friction-washer softstarter data for units 6_4/6_9 was NOT found in this archive.
- Extruder data covers only 9 days in June 2023 — no seasonal or multi-month behaviour available.
- `february_gap_filled.csv` is a timestamp skeleton with all value columns empty.
- Wash-line January data starts 17 Jan; March data is only the night 30–31 Mar.
- Line assignments: extruder folders say 3A/3B; the wash-line SCADA tree is rooted `scada/3c` but its measurement tags name `6_x` equipment — see open question in `line3c_scada_tags.md`.
