# PHOTO — EREMA HMI trend graph (SV-vermogen / SV-temperatuur / intrekschuif)

- **Source file:** 248_CeDo16 (3).pdf
- **Type:** Photograph of an EREMA HMI/SCADA trend-graph screen (rotated ~90°; transcribed upright). Dark, red-lit, scratched glass, partial legibility.
- **Screen timestamp / clock:** ~22:24 2/02/2024 (top-left "22:24" 2/02/2024) [unsure exact leading digits]
- **Trend X-axis span:** 22:07:28 2/02/2024 → 22:24:07 2/02/2024 (about a 16-17 minute window)
- **User/operator label:** "Peter 2..." (top, likely logged-in user name) [unsure full]
- **Scope:** Live extruder screw (SV) power/temperature + intrekschuif (draw-in slide) trend. EREMA line.

## Dual Y-axes
- **Left axis (red/cyan curves):** 400, 300, 200, 100, 0 — scale for SV-vermogen (kW)
- **Right axis (yellow/green/red curves):** 225, 200, 175, 150, 125, 100, 75, 50, 25, 0 — scale for temperature (°C) and % (intrekschuif)

## Curve legend (color-coded)
| Color | Label | Meaning |
|---|---|---|
| Red | **SV-vermogen (kW)** | SV power (kW) — SV = screw/extruder ("schroef-vermogen") |
| Cyan/blue | (bound to left kW axis, jagged trace at bottom) | [unsure: 2nd power/current signal] |
| Green | **SV-temperatuur (°C)** | SV temperature (°C) |
| Yellow | (bound to right axis, flat ~175) | [unsure: setpoint temperature line ~175°C] |
| Red (right-axis) | **intrekschuif (%)** | draw-in slide position (%) |

## State labels (bottom)
- **toevoer aan** ("feed ON") — infeed active
- Button box bottom-right: **"toevoer keuze"** ("feed selection")

## HMI nav pictograms (right edge)
Standard EREMA bluport nav icons (up/down arrows, diamond, "111" scale/weight glyph, home). Matches 247_CeDo3 and other bluport trend screens.

## Answers hunted
- **Q30 (units):** Confirms **SV-vermogen in kW** (left axis to 400), **SV-temperatuur in °C** (right axis to 225), **intrekschuif in %** (right axis). So screw/extruder power is trended in **kW** (not % or A). Doc 248_CeDo16 (3).
- **Q15 (temp zones, why zone3=175):** Yellow flat line sits at ~**175** on the °C axis — consistent with a 175°C temperature setpoint zone (matches the "zone3 = 175°C" question, i.e. a deliberately lower zone). Supports that 175°C is a real melt/zone setpoint. Doc 248_CeDo16 (3). [Correlational, not a labeled zone table.]
- **"intrekschuif (%)":** draw-in slide as a % — an EREMA feed-control actuator position; ties to "toevoer aan / toevoer keuze" feed control. Relevant to feeding/starvation modeling in the sim.
- **SV abbreviation:** "SV-vermogen" / "SV-temperatuur" — SV = extruder screw (Schnecke/schroef) power & temperature channels. [unsure literal expansion; consistent usage = extruder screw drive.]
