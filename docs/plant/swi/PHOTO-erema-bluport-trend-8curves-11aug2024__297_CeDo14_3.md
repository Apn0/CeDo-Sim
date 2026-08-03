# PHOTO — EREMA BluPort HMI, 8-curve trend (rotated capture, 11-8-2024)

- **Source file:** `297_CeDo14 (3).pdf` (1 page, photo of physical HMI touchscreen)
- **Type:** Photograph of EREMA BluPort trend screen (curve legend + values), image rotated 90° (screen text runs bottom-to-top)
- **Line:** Not shown in frame (no LIJN plate visible), but curve set is IDENTICAL to LIJN 3C captures 292/293/294 → almost certainly **LIJN 3C** (same EREMA extruder telemetry template).
- **Brand:** BluPort / EREMA (logo top). ecoSAVE + Rx + remote-monitor icons on nav bar (bottom, rotated).
- **Screen timestamps visible:** cursor/label `21:14:38 11-8-2024`; second time `20:41:20 11-8-2024`. Legend snapshot column all stamped `11-8-2024 20:49:34:600`.

## Trend graph
- Y-axis (numeric scale, reading the rotated image): 0 … 600 in steps of 25 (…25, 50, 75, 100, 125 … 575, 600).
- Multiple colored curves: purple, green, orange/red, white, cyan, yellow, pink (matches the 8-variable EREMA set).
- Color swatch key top: purple, green, orange, white (leading colors).

## Curve legend + snapshot values (VERBATIM, all stamped 11-8-2024 20:49:34:600)
Column header: `Waarde` (value) · `Datum/Tijd`. Reading each colored row's value:
| # | Color | Waarde | Datum/Tijd | (Variable — by position vs 3C template) |
|---|---|---|---|---|
| 1 | cyan | **25** | 11-8-2024 20:49:34:600 | Toevoer actief (infeed active) |
| 2 | magenta/white | **139** | 11-8-2024 20:49:34:600 | Preconditioning Unit vermogen |
| 3 | green | **93** | 11-8-2024 20:49:34:600 | Preconditioning Unit temperatuur 1 |
| 4 | yellow | **59** | 11-8-2024 20:49:34:600 | Extruder 1 toerental |
| 5 | orange | **12** | 11-8-2024 20:49:34:600 | Extruder 1 belasting |
| 6 | white | **70** | 11-8-2024 20:49:34:600 | Automatische intrekschuif positie |
| 7 | pink | **257** | 11-8-2024 20:49:34:600 | Massatemperatuur voor smeltfilter 1 |
| 8 | purple | **27** | 11-8-2024 20:49:34:600 | Massadruk voor smeltfilter 1 |

(Variable names inferred from the identical 8-row EREMA legend on 293_CeDo47 where they are fully legible; only the numeric `Waarde` column is directly read here. Marked [unsure] mapping for exact color-to-variable pairing since row labels are off-frame/rotated.)

- **[unsure]** The value-to-variable pairing above assumes the same fixed row order as 293. Values themselves are clearly legible: 25 / 139 / 93 / 59 / 12 / 257 / 70 / 27.

## Answers to open questions
- **Q15:** If row order matches 3C template, **Massatemperatuur voor smeltfilter 1 = 257 °C** (curve 7, pink) at this snapshot — a hotter pre-filter melt reading than the 217-239 °C seen on 21/23-Dec. Massadruk voor smeltfilter 1 = 27 (low) — consistent with a low-pressure moment (start-up or low load: Extruder 1 belasting = 12, very low load). This looks like a **low-load / ramp state**: infeed 25, PCU vermogen 139, extruder rpm 59, load only 12 %.
- **Q30:** Reconfirms the 8-variable EREMA telemetry set and value ranges. Nothing new on units.
- **Note:** This is a different day (11-8-2024) and a low-load operating point vs the Dec captures — useful as a second data point for the telemetry model (idle/ramp vs full production).

## Notes for sim
- Provides a **low-load snapshot** (belasting 12 %, pre-filter pressure 27) contrasting the full-load Dec snapshots (belasting 58-60 %, pressure 284) — good for defining the operating envelope of the extruder telemetry model.
