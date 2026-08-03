# EREMA BluPort HMI screenshot — LIJN 6 trend + curve table (photo)

- **Source file:** `225_CeDo70 (3).pdf`
- **Doc id:** none (photo of EREMA BluPort HMI trend screen). Physical label plate "LIJN 6" below screen. "BluPort® EREMA" logo top-right.
- **Type:** single-page photograph of live HMI
- **Scope:** Lijn 6 EREMA extruder + Preconditioning Unit (PCU/compactor) + smeltfilter (laserfilter)
- **Screen title (Rx line):** "1-14-25 production program rke"
- **Clock overlay top-left:** 2:40:38 / 12-3-2025

## Physical labels above screen (stickers)
- **Left cream sticker (verbatim):**
  "**Laserfilter uittrekschroeven setting**
   3 rpm minimum
   8 rpm maximum
   Mochten er settings gewijzigd worden communiceer dit met shiftleader en mail naar CI"
  Gloss: laserfilter pull-out screws (uittrekschroeven) setting range **3–8 rpm**; if settings changed, communicate with shiftleader and mail to CI.
- **Center yellow sticker (verbatim):**
  "**STAAT  Afzuiging compactor  !!! AAN !!!**"
  Gloss: "STATE — compactor extraction/suction MUST BE ON." (afzuiging compactor = compactor exhaust/dedusting must stay ON.)

## Left-hand vertical parameter column (pictogram + value + unit)
| Pictogram (gloss) | Value | Unit |
|---|---|---|
| clock | 2:40:38 / 12-3-2025 | (time) |
| gauge (temp) | 111 | °C |
| (power) | 215,8 | kW |
| screw/auger | 110 | rpm |
| % | 56 | % |
| hours | 3554 | h |
| pressure ◇ | 261 | bar |
| pressure (boxed) | 19 | bar |
| pressure ◇ | 173 | bar |
| output ⤷ | 1185 | kg/h |

## Trend graph
- X-axis: 2:23:52, 2:28:02, 2:32:12, 2:36:22, 2:40:31 — all 12-3-2025
- Left Y-axis: 0..500 (steps 50)
- Right Y-axis: 0..600 (steps 25), color-key swatches purple/red/orange/white at top

## Curve legend table (verbatim — Curve | Variabelen-verbinding | Waarde | Datum/Tijd)
All Datum/Tijd = 12-3-2025 2:32:12:836
| Curve | Variabelen-verbinding | Waarde |
|---|---|---|
| 1 | Toevoer actief ("feed active") | 0 |
| 2 | Preconditioning Unit vermogen ("PCU power") | 223 |
| 3 | Preconditioning Unit temperatuur 1 ("PCU temp 1") | 112 |
| 4 | Extruder 1 toerental ("Extruder 1 speed") | 110 |
| 5 | Extruder 1 belasting ("Extruder 1 load") | 54 |
| 6 | Automatische intrekschuif positie ("automatic infeed-slide/AIS position") | 100 |
| 7 | Massatemperatuur voor smeltfilter 1 ("melt temp before melt-filter 1") | 215 |
| 8 | Massadruk voor smeltfilter 1 ("melt pressure before melt-filter 1") | 265 |

## Bottom toolbar icons (verbatim glyphs, L→R)
X (close) · grid (menu) · home · **red bell (alarm active)** · heartbeat/diagnostics · wrench (maintenance) · trend (chart, selected) · Rx (recipe) · monitor/power · **eco⚡SAVE** (EREMA ecoSAVE energy mode) · dual-monitor · ▶| (next)

## Answers to open questions
- **Q9 (throughput):** Lijn 6 at **1185 kg/h**, Extruder 1 at 110 rpm / 54% load. Combined with 224 (1060 kg/h) confirms lijn 6 operating band ~1060–1185 kg/h.
- **Q15 (temp zones / laserfilter):** Curves 7 & 8 = "Massatemperatuur/Massadruk **voor smeltfilter 1**" (melt temp & pressure BEFORE melt-filter): temp 215 °C, pressure 265 bar before the filter. Left-column pressure trio 261/19/173 bar = melt pressures around the laserfilter (before/Δ/after style). Confirms melt pressure is measured before smeltfilter and the ~200–235 °C band is the pre-filter melt temperature.
- **Q30 (units):** Confirms Vermogen = kW (215,8 kW), toerental = rpm (110), belasting = %, AIS-positie = %, temp = °C, druk = bar, output = kg/h. On BluPort the curve-table "Waarde" columns are unitless raw values matching those units.
- **Laserfilter uittrekschroeven ("pull-out screws"):** operating setpoint **3–8 rpm** (from sticker) — this is the laserfilter contaminant-discharge screw speed. Directly relevant to laser-filter model.
- **Afzuiging compactor:** must be ON — the compactor dedust/exhaust is a mandatory-on utility for lijn 6.
