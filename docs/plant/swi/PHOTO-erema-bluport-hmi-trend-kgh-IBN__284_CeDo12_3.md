# PHOTO — EREMA BluPort HMI trend graph (kg/h, IBN commissioning) — lijn 3C/6

- **Source scan:** 284_CeDo12 (3).pdf (1 page, photo of HMI screen, rotated ~90° CCW)
- **Type:** Photograph of an EREMA **BluPort** operator panel (AutoPro + ecoSAVE branding visible) showing a live/historical **trend graph**.
- **No SWI id** (HMI screenshot).

## On-screen text (verbatim, de-rotated)
- Top-left branding: **EREMA** (large), **BluPort**, **AutoPro** (blue circular-arrows logo).
- Graph title / axis label: **kg/h  22.04.2024  IBN** ("IBN" = Inbetriebnahme, German for commissioning/start-up run).
- Left Y-axis scale (kg/h), tick labels reading: 25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500, 525, 550, 575, [600] — full scale ~600 kg/h.
- Time axis markers: **19:37:42  11-4-2024** and **20:11:00  11-4-2024** (trend window on 11-April-2024).
- Toolbar icons along bottom: ecoSAVE, battery/power, lightning (energy), spanner (tools/settings), Rx, chart/curve, navigation arrows (◄ ▲ ►), page/export icons.

## Legend / channel table (right side), colored series with values — timestamp all "11-8-2024 19:26:02:693":
| color | value | timestamp |
|-------|-------|-----------|
| (purple/violet) | 0 | 11-8-2024 19:26:02:693 |
| (green) | 203 [unsure: 205] | 11-8-2024 19:26:02:693 |
| (teal/cyan) | 100 | 11-8-2024 19:26:02:693 |
| (yellow) | 0 | 11-8-2024 19:26:02:693 |
| (orange) | 70 | 11-8-2024 19:26:02:693 |
| (red/brown) | 261 [unsure: 267] | 11-8-2024 19:26:02:693 |
| (white/grey) | 10 | 11-8-2024 19:26:02:693 |

(Column header partly legible: "...TU" / "Waarde" (value). Channel names not legible in this photo.)

## Trend shape (described)
- One channel (pink/white) steps up to a high plateau (~300 region) then drops sharply — looks like a throughput ramp then cut.
- A green channel holds a flat mid-level (~200).
- Purple/white noisy channels oscillate low (bell-shaped hump around the 19:37 marker) — likely a pressure or vibration/level signal.

## Answers found
- **Q9 (line throughput kg/h):** This EREMA line's throughput trend is scaled to ~**600 kg/h full-scale**, with a working plateau channel around **~200 kg/h** (green) and a peak channel reaching **~300 kg/h**. Legend snapshot values: 203, 100, 70, 261, 10 (mixed units — some kg/h, some likely °C or bar/%). Consistent with a single EREMA extruder line running a few hundred kg/h (not the 1200 kg/hr budget of Q21, which is a different/larger line). Date of commissioning trend: **22.04.2024 IBN**, window 11-04-2024 ~19:37–20:11.
- **BluPort/AutoPro/ecoSAVE** = EREMA's HMI + auto-throughput-control + energy-save features — matches lijn 3C / lijn 6 EREMA installs already documented.
