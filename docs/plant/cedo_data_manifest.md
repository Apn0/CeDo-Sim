# CeDo measurement archive — full manifest

**Source:** `F:/Citizen/Documents/CeDo/` (~2 GB)
**Extraction date:** 2026-07-04
**Rule applied:** no raw files copied into the repo; everything parsed in place with Python. Every file in the archive is listed below with its disposition.

## Parsed → repo outputs

| Source | What it is | Output |
|---|---|---|
| `Gegevens extruder 3A/` — 8 signal folders, 81 CSVs (~125 MB) | EREMA/WinCC Archivspeicher (archive memory) exports, 19–28 Jun 2023 | `src/data/plant/trends/extruder_trends_summary.json`, `src/data/plant/trends/3a_*.json` (8 reference curves) |
| `Gegevens extruder 3B/` — 8 signal folders, 80 CSVs on disk, 82 processed (~133 MB) | Same, extruder 3B. Extracted folder was missing `Smeltdruk voor kopfilter/Erema Archivspeicher_7_4.csv` and `_7_14.csv`; both recovered from the bundled zip (hence 80 on disk + 2 recovered = 82 processed) | `extruder_trends_summary.json`, `src/data/plant/trends/3b_*.json` (8 curves) |
| `Gegevens extruder 3B/extruder_real_world_data.zip` | Zip of the same 3B folders (source of the 2 missing files) | folded into 3B outputs |
| `GUIexport/` — 32 CSVs | `powermeasurements_washer6_{64l,64r,69l,69r}_softstarterfrictiewasser_{2024_08..2025_03}.csv`. **All 32 are 10-row synthetic 0..9 ramps** (placeholder/GUI-test exports) | recorded verbatim in `src/data/plant/trends/washer6_power_summary.json` with `is_synthetic_ramp: true` |
| `washer6/` — 14 CSVs (~4.8 MB) | Grafana-style change-of-value logs (`#NAMES/#TYPES/#ROWS` header), units 6_3/6_6/6_11/6_14l/6_14r/6_18, 17 Oct 2024 – 31 Mar 2025 | `washer6_power_summary.json` (per-file stats, tag mapping) |
| `Random Exports/*.csv` (see per-file table below) | 1 Hz wash-line tag exports Aug 2024 – Mar 2025 (flotation flow/level, dryer amps, grinder amp) | `src/data/plant/trends/washline6_1hz_summary.json`, `washline6_feb2025_curves.json` |
| `Random Exports/3c_tags.xlsx` | 1084-row SCADA tag dump (1056 unique) | `src/data/plant/line3c_scada_tags.json` + full transcription in `docs/plant/line3c_scada_tags.md` |

### Random Exports per-file disposition

| File | Size | Disposition |
|---|---|---|
| `August_cleaned.csv` | 22.6 MB | stats computed (21–30 Aug 2024; only flotation_level populated) |
| `September_cleaned.csv` | 70.6 MB | stats computed (full Sep 2024; only flotation_level populated) |
| `October_cleaned.csv` | 81.0 MB | stats computed (dryer amps + grinder appear from Oct) |
| `November_cleaned.csv` | 81.8 MB | stats computed |
| `December_cleaned.csv` | 85.8 MB | stats computed |
| `January_cleaned.csv` | 43.8 MB | stats computed (starts 17 Jan 2025; flotation_flow appears) |
| `february_1_to_14.csv` / `february_15_to_29.csv` | 34.9 / 31.2 MB | stats computed (raw halves, US timestamp text) |
| `5tags_Feb_cleansed.csv` | 94.0 MB | stats computed; used for the February reference curves |
| `february_gap_filled.csv` | 19.1 MB | **timestamp skeleton — all 6 value columns 100 % empty**; recorded, no stats possible |
| `4tags_August_with_estimated_flow.csv` | 28.2 MB | stats computed; contains user-derived `level_smooth`, `level_shifted`, `estimated_flow` (model output, NOT a measurement — estimated_flow is 58 % negative) |
| `5tags_Feb.csv` | 73.5 MB | not re-parsed: same Feb data with `"Feb 1, 2025, 12:00:00 AM"` timestamps; superseded by `_cleansed` |
| `5tags_Feb_ISO.csv` | 63.6 MB | not re-parsed: ISO-re-timestamped duplicate of the above |
| `Merged_cleaned_full_timestamps.csv` | 402 MB | not re-parsed: concatenation of the monthly `*_cleaned.csv`; covered by the monthlies |
| `Done/2024_09.csv` | 70.6 MB | not re-parsed: near-duplicate of `September_cleaned.csv` with mangled header (`Unnamed: n` leaked into first data row) |
| `Done/2025_03.csv` | 3.0 MB | stats computed (30–31 Mar 2025; pandas-merge `_x/_y` artefact columns; unsuffixed columns = `_x` set) |
| `scriptje.txt` | 0 B | empty file — nothing to parse |
| `Portable Python-3.10.5 x64.exe` | 40.8 MB | tooling installer, not plant data |

## Not parsed (with reason)

| File | Reason / description |
|---|---|
| `Merged_with_February - Copy.txt` (487 MB, root) | CSV-in-txt: the merged monthlies plus February appended (header `timestamp,flotation_level,dryer_left_amp,dryer_right_amp,grinder_amp,flotation_flow`, starts 2024-08-21 11:02:28). Duplicate of parsed data; recorded in `washline6_1hz_summary.json` under `skipped_files` |
| `Extracted_Images.zip` (5.5 MB, 28 PNGs named `00:43.png` … `01:10.png`) | Frame sequence (~1 fps) extracted from a screen-recording video of the CeDo plant-monitoring web GUI. Frames inspected (00:43, 01:10): "cedo" logo; menu bar `System, OEE Shift, OEE Dag/Week/Maand, Technical overview, Plant overview, Planned downtimes, Order overview, SCADA, IFS`; `Gebruiker: ArnoDaamen`; page shows TWO extruder-line schematics stacked (top + bottom): infeed screw conveyors (drawn as zig-zag truss screws), two stacked rectangular silos/day bins, a large circular fan/blower symbol, extruder barrel with melt-filter section (vertical squiggle lines), second fan circle at right, small status LEDs (green/red/purple dots) and a green pill readout `0.00`; numeric readouts at far right overlap each other and are illegible at this resolution [unsure: values like `580 107.0 232/0.019.00 62 kW %  bar kg/h bar` can be made out as unit labels kW, %, bar, kg/h, bar]. Not tabular data — treat as GUI reference imagery for the sim's monitoring screens |
| `Screenshot 2025-04-02 044419.png` (257 KB) | Operator's matplotlib figure: "Flotation Flow and Level Trends, Feb 17 2025, 05:00–07:00". Blue = smoothed flow (L/min, left axis 0–140), green = smoothed level (right axis 44.0–48.0). Shows 3 flow surges to ~120–140 L/min (~05:05, ~05:35, ~06:00) each followed by decay to a ~15 L/min baseline; level oscillates 45–47.5 and settles into a banded 46–47 pattern after 06:15. Analysis artefact, not raw data |
| `output.png` (763 KB) | Operator's matplotlib figure: 5 stacked "Flow Spike at HH:MM:SS" panels (16:10:40, 16:40:20, 17:26:50, 20:13:30, 21:12:50 on the 30th — matches 30 Mar 2025 data in `Done/2025_03.csv`). Each panel: blue flotation flow vs red/purple dashed dryer right/left amps, 6–8 min windows. Shows dryer-amp response accompanying flow spikes. Analysis artefact |
| `output (1).png` (81 KB) | Operator's matplotlib figure: "Flotation Flow (5s Average) - 22:00 to 23:00" — **empty plot** (no data in window). Analysis artefact |
| `DB.Browser.for.SQLite-v3.13.1-win64.msi` (19.9 MB) | tooling installer, not plant data |
| `python-3.13.3-amd64.exe` (28.6 MB) | tooling installer, not plant data |

## Notes for the operator (open questions)

1. `washer6/` change-of-value logs: values are small integers 0–6 — are these amps, or a state/step code? And are the constant-zero 6_14/6_18 motor logs real (motors never drew current in that window) or dead tags?
2. `GUIexport/` softstarter files are placeholders — does a real export of 6_4/6_9 friction-washer softstarter current exist elsewhere?
3. Tag tree says `scada/3c/...` while measurement tags name `6_x` equipment: is "3c" the SCADA node hosting wash line 6, or does the wash line belong to line 3C administratively?
4. `Vermogen hoofdmotor` (`load_extruder`) unit: % load, kW or A? Values run 0–119 (3A) / 0–103 (3B).
5. `flotation_level` unit: % of tank height?
