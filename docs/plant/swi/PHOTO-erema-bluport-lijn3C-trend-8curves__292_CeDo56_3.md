# PHOTO — EREMA BluPort HMI, LIJN 3C, 8-curve trend graph + legend table

- **Source file:** `292_CeDo56 (3).pdf` (1 page, photo of physical HMI touchscreen)
- **Type:** Photograph of EREMA BluPort trend screen with curve legend/values table
- **Line:** LIJN 3C (engraved plate below screen)
- **Recipe banner (top center):** `℞ LDPE 800 kg/h  22.04.2024  IBN` — recipe "LDPE 800 kg/h", dated 22-04-2024, IBN (Inbedrijfstelling / commissioning).
- **Screen timestamp:** `1:15:29  23-12-2024`
- **Brand:** BluPort / EREMA (top-right).

## Left-hand live value column (pictogram → value → unit)
| Pictogram | Value | Unit | Gloss |
|---|---|---|---|
| thermometer | **96** | °C | melt temperature |
| power ◎ | **226,1** | kW | hoofdmotor power |
| screw ~~~ | **95** | rpm | extruder screw speed |
| % | **51** | % | screw load/speed % |
| clock | **3599** | h | running hours |
| ◇ | **256** | bar | pressure (pre-filter melt) |
| ▣ | **23** | bar | pressure |
| ◇ | **206** | bar | pressure |
| output ⤒ | **1217** | kg/h | throughput/output |

## Trend graph axes
- Left Y-axis: 0 … 500 (marks every 50).
- Right Y-axis: 0 … 600 (marks every 25).
- X-axis (time): `0:42:00 23-12-2024` → `0:50:19` → `0:58:39` → `1:06:58` → `1:15:18 23-12-2024`.
- Playback/zoom controls row: ■ (stop) · ⏪ · ⏩ · 🔍 · 🔍 (rewind/forward/zoom).

## Curve legend + snapshot values table (VERBATIM — cursor at 23-12-2024 0:58:40:306)
| Curve | Variabelen-verbinding (variable link) | Waarde | Datum/Tijd |
|---|---|---|---|
| 1 (cyan) | **Toevoer actief** (infeed active) | 25 | 23-12-2024 0:58:40:306 |
| 2 (magenta) | **Preconditioning Unit vermogen** (PCU power) | 226 | 23-12-2024 0:58:40:306 |
| 3 (green) | **Preconditioning Unit temperatuur 1** (PCU temp 1) | 100 | 23-12-2024 0:58:40:306 |
| 4 (yellow) | **Extruder 1 toerental** (extruder 1 speed/rpm) | 54 | 23-12-2024 0:58:40:306 |
| 5 (orange) | **Extruder 1 belasting** (extruder 1 load) | 60 | 23-12-2024 0:58:40:306 |
| 6 (white) | **Automatische intrekschuif positie** (automatic infeed-slide position) | 234 | 23-12-2024 0:58:40:306 |
| 7 (pink/salmon) | **Massatemperatuur voor smeltfilter 1** (melt temp before melt filter 1) | 239 | 23-12-2024 0:58:40:306 |
| 8 (purple) | **Massadruk voor smeltfilter 1** (melt pressure before melt filter 1) | [value column cut/obscured — row present] |

(Right-hand color swatch bars top-right: purple, green, red, orange — the trend line colors.)

## Navigation bar (bottom, left→right)
✕ · ▦ modules · ⌂ home · 🔔 alarms · ♡ health · 🔧 maintenance · 📈 trends (highlighted) · ℞ recipes · ⚡ energy · eco·SAVE · monitor remote · ▶| next.

## Physical panel labels
- **Top-left placard (warning):** `WAARSCHUWING — GEBRUIK DEZE MACHINE NIET ... VEILIGHEIDSCONTROLE IN POSITIE ... BORD NIET VERWIJDEREN OF MISVORMEN — 1 hollandisch` (partly cut). Do not use machine without safety control in position; do not remove or deface the sign.
- **Top-center yellow placard:** `STAAT / Afzuiging compactor / !!! AAN !!!` (State: compactor extraction ON).
- **Blue engraved plate:** `LIJN 3C`.

## Answers to open questions
- **Q15 (temp zones / laserfilter):** Legend confirms measured melt values around the melt filter: **Massatemperatuur voor smeltfilter 1 = 239** (°C) and **Massadruk voor smeltfilter 1** (melt pressure before melt filter). "smeltfilter" = melt filter / laserfilter. Melt temp entering the filter ~239 °C, consistent with the 240-255 °C hot zones cited in Q15. The 96 °C left readout is a different sensor (likely PCU/preconditioning), NOT the melt-filter temp.
- **Q30 (units):** Reconfirms Vermogen in **kW** (226,1) with parallel **%** (51); Snelheid in **rpm** (95). PCU power reads as a raw number "226" (matches kW). Extruder 1 belasting (load) = 60 (likely %). Output 1217 kg/h.
- **Q9 / Q21 (throughput):** Recipe = **LDPE 800 kg/h** (nameplate design rate for this LDPE recipe on line 3C); live output momentarily reads **1217 kg/h**. So 3C's LDPE recipe target is 800 kg/h. (Q21's 1200 kg/hr budget is close to the live 1217 reading here but recipe nameplate is 800.)
- **Q3/M11a, Q6 (Pomp zeefbocht):** No data.

## Notes for sim
- Curve set (8 vars) is an excellent template for an EREMA extruder-line telemetry model: infeed-active flag, PCU power, PCU temp, extruder rpm, extruder load, auto infeed-slide position, melt temp before filter, melt pressure before filter.
- Recipe object model: name ("LDPE 800 kg/h") + commissioning date + IBN flag.
