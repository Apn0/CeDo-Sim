# PHOTO — EREMA Bluport HMI trend screen, live values with UNITS (1/06/2024)

- **Source file:** `354_CeDo8 (3).pdf` (D:/drive-download-20251124T130330Z-1-001)
- **Type:** Single-page photo of an EREMA HMI touchscreen (dirty/greasy glass, taken at an angle). Trend-graph screen with a live-value readout row along the bottom, each value carrying its unit in square brackets. Legend box top-right ("Variabelen / Kromme" curve table).
- **SWI id:** none (operator photo of live HMI)
- **Scope:** Directly answers **Q30** (HMI variable units). Timestamp on screen: **20:09:15 1/06/2024** (trend cursor) and **20:39 1/06/2024** (right edge). Date stamp also bottom-left "1/06/2024".
- **Related:** `PHOTO-erema-hmi-SV-extruder-livevalues__257_CeDo5_3.md`, `OTHER-erema-hmi-mimic-SV-compactor-extruder-zones__185_CeDo88_3.md`, `PHOTO-erema-bluport-hmi-trend-kgh-1082__344_CeDo4_3.md`.

## Live-value readout row (VERBATIM, bottom of screen, left→right)
Each has a small pictogram/symbol then value and unit:

| Pictogram (symbol) | Value | Unit | Meaning (interpretation) |
|---|---|---|---|
| ⊘ (EREMA screw/motor symbol) | **204** | **[kW]** | Vermogen hoofdmotor (main-motor power) |
| (thermometer symbol) | **114** | **[°C]** | Temperatuur (a melt/zone temperature) |
| ↯↯↯ (load bars symbol) | **73** | **[%]** | Belasting / vermogen as percentage (load %) |
| Ⓟ (P in circle) | **286** | **[bar]** | Druk / massadruk (pressure, e.g. before filter) |
| Ⓟ (P in circle, 2nd) | **113** | **[bar]** | Druk (second pressure point, e.g. after filter / melt pump) |
| ⇥ (throughput arrow) | **598** | **[kg/h]** | Doorzet / throughput |

## Trend-graph Y axis (verbatim ticks)
Y-axis scale printed: **1400 – 1200 – 1000 – 800 – 600 – 400 – 200 – 0** (multi-variable overlay; the different traces share this composite scale — kW curve, temp curve, %, bar, kg/h all plotted).

## Legend box (top-right "Variabelen / Kromme" — partly legible)
Curve table with numbered rows 1–7 ("Kromme" = curve). Legible variable labels (Dutch, colour-coded traces):
- **vermogen v[ermogen]** — power (kW)
- **temperatuur ex[truder]** — extruder temperature (°C)
- **toerental ex[truder]** — extruder speed/rpm
- **belasting ex[truder]** — extruder load (%)
- **massadruk** — melt pressure (bar)
- [additional rows partly obscured — [unsure: two more rows, likely druk na filter and doorzet kg/h]]

## Open-question hits — Q30 (STRONG, primary answer source)
Confirms the HMI live-value UNITS verbatim:
- **Vermogen hoofdmotor = kW** (here 204 kW). → Q30: main-motor power is displayed in **kW** (not % or A) on the trend readout. (Note a separate **belasting = % (73%)** field exists for load — so the HMI shows BOTH an absolute kW value AND a % load figure.)
- **Snelheid / toerental extruder** — labelled "toerental ex" in legend → **rpm** (speed as rpm; a separate % load exists). Supports Q18/Q30 rpm interpretation.
- **Massadruk = bar** (286 bar and 113 bar shown = two pressure points, consistent with before/after laserfilter or melt-pump inlet/outlet).
- **Doorzet = kg/h** (598 kg/h). Matches the LDPE-film throughput band from the TVEplus brochure (`352`), on the low side (partial load / ramp).
- **Temperatuur = °C** (114 °C shown — low, likely a specific zone or the PCU/intake, not a melt zone).

## Q15 (temp zones)
Single temp shown (114 °C) is too low to be a melt zone — likely PCU/intake or cooling; consistent with the low-temp intake design. Not a full zone map.

## Q9/Q21 (throughput)
Live value **598 kg/h** on this line at this moment. Consistent with an INTAREMA running LDPE film below its max (a 1310-class machine's 700-850 band, ramping or part-loaded). Not the 1200 kg/h budget line.

## Notes
- Photo is heavily reflective/greasy; some legend rows [unsure]. Values in the readout row are clear and reliable.
- The dual-bar [%] and [kW] presence is the key modelling insight: the HMI exposes power both as kW and as % load simultaneously (answers the Q30 ambiguity about whether Vermogen is %/kW/A → it is kW, with a companion % load field).
