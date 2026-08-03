# PHOTO — EREMA HMI screenshot: "Actueel benodigde elektrische energie" (kWh/kg) + live values

- **Source file:** 328_CeDo17 (3).pdf
- **Type:** Photograph of an EREMA BluPort/HMI screen (dark panel, off-axis phone photo)
- **SWI id:** none (HMI screenshot, no SWI header)
- **Line context:** EREMA extruder line (values consistent with lijn 3C / an EREMA INTAREMA extruder HMI; no line label captured in frame)
- **Screen timestamp:** 6:01:08, 12-9-2024 (top-left). Trend graph x-axis starts 5:44:26, 12-9-2024.

## Center panel (verbatim)
- Title: **"Actueel benodigde elektrische energie"** (currently required electrical energy)
  - Value: **0,156 kWh/kg** (large readout, kWh over kg fraction)
- Sub-panel title: **"Elektrisch energieverbruik"** (electrical energy consumption)
  - Value: **735192 kWh**
  - Button: **Reset**

## Left column live values (top-to-bottom, verbatim value + unit)
| Value | Unit | Likely meaning (gloss) |
|-------|------|------------------------|
| 118 | °C | temperature (zone / melt temp) |
| 170,3 | kW | main motor / drive power |
| 140 | rpm | extruder screw speed (Snelheid) |
| 86 | % | screw load / speed % |
| 1872 | h | operating hours (bedrijfsuren) |
| 209 | bar | pressure (before filter — likely smeltdruk vóór laserfilter) |
| 49 | bar | pressure (filter Δp or after-filter) |
| 232 | bar | pressure (melt pump / after) |
| 1679 | kg/h | throughput (doorzet) |

Left-column icons partially visible next to some rows (arrow / pressure glyphs — "1", ">2", etc.) but too dark to read reliably: [unsure: pressure-point labels P1/P2].

## Right side: vertical bar gauge + trend
- Vertical scale 0 … 2500 in steps of 125 (0, 125, 250, 375, 500, 625, 750, 875, 1000, 1125, 1250, 1375, 1500, 1625, 1750, 1875, 2000, 2125, 2250, 2375, 2500).
- Colored zone markers on the bar: green band ~2375-2500 (top), yellow band ~2125-2250, orange band ~2000-2125. [unsure: this is a kg/h or power gauge given the 0-2500 range]
- Trend graph (bottom-right): green + yellow traces; a step-up around mid-graph from ~500 baseline to ~750-875 with a spike near ~1500 at the right edge. Consistent with a doorzet/throughput trend (kg/h) building up over ~17 min.

## Answers to open questions
- **Q30 (units):** Confirms on this EREMA HMI: **Vermogen hoofdmotor = kW** (170,3 kW here), **Snelheid = rpm** (140 rpm) with a separate **% load** (86 %), **doorzet = kg/h** (1679), pressures in **bar**, temp in **°C**, operating time in **h**. Energy readouts in **kWh/kg** (specific) and cumulative **kWh**.
- **Q9 / throughput:** live doorzet **1679 kg/h** captured on this extruder; specific energy **0,156 kWh/kg** (i.e. ≈156 Wh/kg). Note this corroborates the "~1 kW per ~6.4 kg/h" order and the EREMA "1 kW per 10 kg" rule of thumb documented elsewhere (307_CeDo53) — at 170,3 kW / 1679 kg/h.
- No new answers to Q1-Q8, Q10-Q29, Q31-Q33 on this page.
