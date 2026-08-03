# PHOTO — EREMA BluPort HMI, LIJN 3C, 8-curve trend graph + legend (2nd capture)

- **Source file:** `293_CeDo47 (3).pdf` (1 page, photo of physical HMI touchscreen)
- **Type:** Photograph of EREMA BluPort trend screen with curve legend/values table (sibling of `292_CeDo56 (3)`)
- **Line:** LIJN 3C (engraved plate below screen)
- **Recipe banner:** `℞ LDPE 800 kg/h  22.04.2024  IBN`
- **Screen timestamp:** `2:23:39  21-12-2024`
- **Note:** Alarm bell icon in nav bar is RED (active alarm state) in this capture.

## Left-hand live value column
| Pictogram | Value | Unit | Gloss |
|---|---|---|---|
| thermometer | **111** | °C | melt temperature |
| power | **224,3** | kW | hoofdmotor power |
| screw | **105** | rpm | extruder screw speed |
| % | **63** | % | screw load/speed % |
| clock | **3553** | h | running hours |
| ◇ | **287** | bar | pressure (pre-filter melt) — displayed in orange (near/over limit) |
| ▣ | **26** | bar | pressure |
| ◇ | **206** | bar | pressure |
| output | **1376** | kg/h | throughput/output |

## Trend graph axes
- Left Y: 0…500 (marks /50). Right Y: 0…600 (marks /25).
- X-axis time: `2:06:47 21-12-2024` → `2:10:57` → `2:15:07` → `2:19:17` → `2:23:26 21-12-2024`.
- Cursor line at `2:15:07:933`.

## Curve legend + snapshot values (cursor 21-12-2024 2:15:07:933) — VERBATIM, all 8 rows legible
| Curve | Variabelen-verbinding | Waarde | Datum/Tijd |
|---|---|---|---|
| 1 (cyan) | Toevoer actief | **25** | 21-12-2024 2:15:07:933 |
| 2 (magenta) | Preconditioning Unit vermogen | **218** | 21-12-2024 2:15:07:933 |
| 3 (green) | Preconditioning Unit temperatuur 1 | **110** | 21-12-2024 2:15:07:933 |
| 4 (yellow) | Extruder 1 toerental | **98** | 21-12-2024 2:15:07:933 |
| 5 (orange) | Extruder 1 belasting | **58** | 21-12-2024 2:15:07:933 |
| 6 (white) | Automatische intrekschuif positie | **70** | 21-12-2024 2:15:07:933 |
| 7 (pink) | Massatemperatuur voor smeltfilter 1 | **217** | 21-12-2024 2:15:07:933 |
| 8 (purple) | **Massadruk voor smeltfilter 1** | **284** | 21-12-2024 2:15:07:933 |

→ This capture supplies the **curve-8 value (284)** that was cut off in `292_CeDo56`. Confirms curve 8 = melt pressure before melt filter 1, value ~284 (bar-range number; matches the ◇ 287 bar left readout — the pre-filter melt pressure).

## Physical panel labels
- Top-center yellow placard: `Afzuiging compactor / !!! AAN !!!` (compactor extraction ON).
- Blue plate: `LIJN 3C`.
- Nav bar: ✕ · ▦ · ⌂ · 🔔(RED, active) · ♡ · 🔧 · 📈 · ℞ · ⚡ · ecoSAVE · remote · ▶|.

## Answers to open questions
- **Q15:** Melt-filter (laserfilter) inlet readings on 3C: **Massatemperatuur voor smeltfilter 1 = 217 °C**, **Massadruk voor smeltfilter 1 = 284** (bar), with left readout **◇ 287 bar** (shown orange = alarm/near-limit). Confirms pre-laserfilter melt pressure runs ~280+ bar and inlet melt temp ~215-240 °C on 3C. Corroborates that the high pressure differential drives laserfilter screen changes.
- **Q30:** Vermogen kW (224,3) + % (63); Snelheid rpm (105). Pre-filter pressure in bar; orange coloring = value approaching/exceeding limit (a UI convention worth mirroring in-sim). Output kg/h (1376).
- **Q9/Q21:** Recipe nameplate LDPE 800 kg/h; live output 1376 kg/h (this line clearly runs well above nameplate at times).

## Notes for sim
- Two captures (292: 1217 kg/h, 293: 1376 kg/h) show output on 3C swinging 1200-1400 kg/h against an 800 kg/h recipe label → good variance data for a throughput model.
- Orange-colored pressure readout = "approaching alarm" visual state to replicate.
