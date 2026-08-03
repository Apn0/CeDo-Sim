# Photo — EREMA Bluport HMI trend screen (Variabelenaanbinding), 10-04-2024

- **Source file:** `344_CeDo4 (3).pdf`
- **Type:** Plant-floor photograph of an EREMA Bluport HMI panel showing the **trend/curve ("Kromme") screen** with the variable-binding ("Variabelenaanbinding") legend. Scan is rotated ~90° CW and glare-obscured; screen is dark green background with white grid.
- **No SWI id.** Timestamped from the on-screen date.

## On-screen date/time
- Photo timestamp (bottom-left overlay): **13:38 10/04/2024** [unsure: "13:38"].
- Trend time axis span: **11:30:03 10/04/2024** (left) → **12:00:03 10/04/2024** (mid) → **12:30:03 10/04/2024** (right).

## Live values (left column, EREMA symbol = value = unit)
Read verbatim from the left-edge readouts (each has a small pictogram):
- ⊘ / motor symbol = [value illegible under glare] **[kW]** — *(vermogen / power, kW)*
- clock/temp symbol **⊙ = 108 [°C]** — *(a temperature = 108 °C)*
- **↕ = [value illegible] [%]** — *(a percentage reading, %)*
- **P₂ = 130 [bar]** — *(pressure P2 = 130 bar; likely massadruk/melt pressure)*
- **G = 1082 [kg/h]** — *(throughput / doorzet = 1082 kg/h)*

## Kromme legend — "Variabelenaanbinding" (variable binding), curves 1-8
The trend legend maps 8 curves to variables (verbatim, with EN gloss):
1. **doorzet (kg/h)** — throughput (blue) [unsure: curve colour]
2. **vermogen verdichter (kW)** — compactor power (kW)
3. **temperatuur verdichter (°C)** — compactor temperature (°C)
4. **toerental extruder (rpm)** — extruder speed (rpm)
5. **belasting extruder (%)** — extruder load (%)
6. **[unsure: "..." (red)]** — [illegible label, red curve]
7. **massadruk voor smeltfilter 2 (bar)** — melt pressure before melt-filter 2 (bar)
8. **[smelt]temperatuur voor smeltfilter (green)** — melt temperature before melt-filter (°C) [unsure: full label "massatemperatuur voor smeltfilter"]

## Right-edge nav icons
Standard EREMA Bluport navigation glyphs (login/logout door, diamond/home, up-arrows, wavy "extruder" icon, screen-return arrow).

## Answers to open questions
- **Q9 (line throughput kg/h):** A live datapoint — **doorzet G = 1082 kg/h** on this EREMA extruder line (10-04-2024). Consistent with the ~1000-1200 kg/h class seen elsewhere (cf. Q21 "1200 kg/hr budget").
- **Q30 (units):** Confirms EREMA trend units: **vermogen in kW, temperatuur in °C, toerental extruder in rpm, belasting extruder in %, massadruk/smeltdruk in bar, doorzet in kg/h.** So "belasting extruder" (extruder load) is the **%** metric and "toerental" (speed) is the **rpm** metric.
- **Q15 (melt-filter zones):** Trend tracks **massadruk voor smeltfilter 2 (bar)** and **temperatuur voor smeltfilter** — i.e. sensors sit *before* the melt/laser filter, matching the laserfilter pressure-differential monitoring (cf. `laserfilter-smeltdrukverschil__062_CeDo72.md`).

## Notes for sim
- Real captured operating point for an EREMA line: **1082 kg/h throughput, 130 bar pre-filter melt pressure, one temp reading 108 °C** (that 108 °C is low → likely the compactor/verdichter temperature, curve 3, not a melt zone). Good calibration anchor for the extruder HMI in-sim.
