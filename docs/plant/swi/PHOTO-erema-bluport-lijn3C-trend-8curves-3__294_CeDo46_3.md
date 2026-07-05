# PHOTO — EREMA BluPort HMI, LIJN 3C, 8-curve trend (3rd capture, near-dup of 293)

- **Source file:** `294_CeDo46 (3).pdf` (1 page, HMI photo)
- **Near-duplicate of** `293_CeDo47 (3).pdf` (`PHOTO-erema-bluport-lijn3C-trend-8curves-2__293_CeDo47_3.md`): same LIJN 3C trend screen, same recipe `℞ LDPE 800 kg/h 22.04.2024 IBN`, same cursor snapshot `21-12-2024 2:15:07:933`. Screen clock here `2:23:33 21-12-2024` (6 s before the 293 capture at 2:23:39). Alarm bell icon NOT red here (vs red in 293).

## Differences in left-hand live column vs 293
| Pictogram | 294 value | (293 value) | Unit |
|---|---|---|---|
| thermometer | 111 | 111 | °C |
| power | **220,0** | 224,3 | kW |
| rpm | 105 | 105 | rpm |
| % | 63 | 63 | % |
| h | 3553 | 3553 | h |
| ◇ | **290** (orange) | 287 | bar |
| ▣ | 26 | 26 | bar |
| ◇ | **204** | 206 | bar |
| output | **1375** | 1376 | kg/h |

## Curve legend snapshot (identical cursor 2:15:07:933) — VERBATIM
| Curve | Variabelen-verbinding | Waarde |
|---|---|---|
| 1 | Toevoer actief | 25 |
| 2 | Preconditioning Unit vermogen | 218 |
| 3 | Preconditioning Unit temperatuur 1 | 110 |
| 4 | Extruder 1 toerental | 98 |
| 5 | Extruder 1 belasting | 58 |
| 6 | Automatische intrekschuif positie | 70 |
| 7 | Massatemperatuur voor smeltfilter 1 | 217 |
| 8 | Massadruk voor smeltfilter 1 | 284 |

(All snapshot values match 293 exactly — same frozen cursor point. Only the live left-column and clock differ.)

## Panel labels
- Yellow placard: `STAAT / Afzuiging compactor / !!! AAN !!!`.
- Blue plate: `LIJN 3C`. Recipe LDPE 800 kg/h.

## Answers to open questions
- **Q15/Q30:** Reconfirms 293. Pre-filter melt pressure ◇ **290 bar (orange = alarm zone)**, output **1375 kg/h**, power 220 kW / 63 %, 105 rpm. No new variables.
- No new answers beyond 293; retained for completeness / cross-verification of frozen snapshot values.
