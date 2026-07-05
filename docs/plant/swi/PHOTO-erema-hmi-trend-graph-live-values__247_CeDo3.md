# PHOTO — EREMA HMI trend graph with live values (durchsatz/throughput)

- **Source file:** 247_CeDo3.pdf
- **Type:** Photograph of an EREMA HMI/SCADA trend-graph screen (image rotated ~90° CCW; transcribed upright). Dirty/scratched glass, low legibility.
- **Screen timestamp:** 13:30 10/04/2024 (top-left live clock)
- **Trend X-axis time span:** 11:30:03 10/04/2024 → 12:00:03 10/04/2024 → 12:30:03 10/04/2024
- **Scope:** Live extruder/melt-filter process values + curve legend. Line context = EREMA extruder line (likely 3C laser-filter line, matches other bluport HMI docs).

## Live value readout (bottom-left column, each with pictogram + unit)
| Pictogram/var | Value | Unit |
|---|---|---|
| (motor/vermogen symbol) | = 188 | [kW] |
| (2nd symbol) | = 108 | [°C] |
| (%) | = [unsure: value illegible] | [%] |
| P (bar) | = 129 | [bar] |
| ⇥ (throughput arrow) | = 1087 | [kg/h] |

## Y-axis scale (left) — shared graph axis
2000, 1750, 1500, 1250, 1000, 750, 500, 250, 0

## Curve legend — "Variabelenaanbinding" (variable binding) — "Kromme" (curve)
| Curve # | Label | Meaning |
|---|---|---|
| 1 | **doorzet (kg/h)** (blue) | throughput (kg/h) |
| 2 | **vermogen verdichter (kW)** | power of compactor/densifier (kW) |
| 3 | **temperatuur verdichter (°C)** (green) | temperature of compactor (°C) |
| 4 | **toerental extruder (rpm)** | extruder speed (rpm) |
| 5 | **belasting extruder (%)** | extruder load (%) |
| 6 | **[unsure: toevoer? / vulling?]** (red) | [unsure best reading] |
| 7 | **massadruk voor smeltfilter 2 (bar)** | melt pressure before melt-filter 2 (bar) |
| (8) | **[smelt]temperatuur voor smeltfilter** (green text) | melt temperature before melt-filter |

## HMI navigation pictograms (right edge)
Standard EREMA bluport nav icons: log-out/exit arrow (top-right), up/down navigation diamonds, "gewicht/schaal" scale icon, alarm/bell, home/return arrow (bottom). Zoom "+" magnifier near top-right of graph. Matches other 3C/lijn6 bluport HMI docs (e.g. 217_CeDo10_3, 218_CeDo11_3 trend graphs).

## Answers hunted
- **Q9 (line throughput kg/h):** Live **doorzet = 1087 kg/h** on this extruder line at 13:30 10/04/2024. This is a real running-line snapshot. Doc 247_CeDo3. (Consistent with the "1200 kg/hr budget" reference in Q21 — actual ~1087.)
- **Q30 (units):** Confirmed units on this EREMA HMI: **Vermogen (power) = kW** (hoofdmotor 188 kW), **massadruk/melt pressure = bar** (129 bar), **doorzet/throughput = kg/h** (1087), **temperatuur = °C** (108°C), **belasting extruder = %**, **toerental extruder = rpm**. So on EREMA: power in kW, pressure in bar, throughput kg/h, extruder speed in rpm, extruder load in %. Doc 247_CeDo3. [Resolves Q30: Vermogen hoofdmotor in kW (not % or A) on this trend; Snelheid/toerental in rpm.]
- **Q15/laserfilter:** curve 7 = "massadruk voor smeltfilter 2 (bar)" and curve 8 = "temperatuur voor smeltfilter" — confirms melt pressure/temp are monitored **before** the smeltfilter (melt filter / laserfilter). Two melt filters implied ("smeltfilter 2"). Doc 247_CeDo3.
- **Verdichter (compactor) monitored:** vermogen verdichter (kW) + temperatuur verdichter (°C) are trended alongside extruder — confirms EREMA PCU compactor power & temp are live SCADA points.
