# EREMA HMI mimic screen — Schneidverdichter (compactor) + extruder barrel zones

- **Source file:** 185_CeDo88 (3).pdf (1 page, photo of EREMA HMI mimic/overview screen)
- **Doc id / slug:** OTHER-erema-hmi-mimic-SV-compactor-extruder-zones
- **Doc type:** Photograph of EREMA process-overview (mimic) HMI showing the Schneidverdichter (SV = cutter/compactor) feeding the extruder, with barrel temperature zones
- **Key:** "SV" = Schneidverdichter (EREMA cutter-compactor, the PCU). "EMT"/"EMA" branding = EREMA. Bottom pictogram row labels: **vulzone** (feed), **extruder**, **smelt(filter)** (melt/filter, cut off right).

## Live values (VERBATIM, by panel)
| Panel label (NL) | Value | Unit | Meaning (EN) |
|---|---|---|---|
| **SV-vulpeil** | 45 | cm | Compactor fill level = 45 cm |
| **afzuiging 1** | 55 | % | Extraction/suction fan 1 = 55 % |
| **afzuiging 2** (afzuigi…, cut off) | 0 | (%) | Extraction/suction fan 2 = 0 (off) |
| **SV-belasting** | 61 | % | Compactor (cutter) load = 61 % |
| **SV-vermogen** | 193 | kW | Compactor drive power = 193 kW |
| **SV-temperatuur** | 108 | °C | Compactor internal temperature = 108 °C |
| **schuif** | 100 | % | Slide/gate (schuif) between compactor & extruder = 100 % (fully open) |
| **ex-belasting** | 102 | % | Extruder load = 102 % |
| **extr rpm** | 120 | rpm | Extruder screw actual speed = 120 rpm |
| (setpoint box, highlighted) | 120 | rpm | Extruder screw setpoint = 120 rpm |

## Extruder barrel temperature zones (VERBATIM, left→right along the barrel)
| Zone | Temp | Note |
|---|---|---|
| **EZ-1** (Einzugszone / feed zone 1) | 113 °C | First zone right after compactor infeed — LOW (feed/intake) |
| **ZZ-1** (Zylinderzone 1 / cylinder zone 1) | 157 °C | |
| **ZZ-2** (Zylinderzone 2) | 184 °C | |
| **ZZ-3** (Zylinderzone 3) | 213 °C | rising toward die/filter (value cut off at right edge, "213" visible) |

Ramp: 113 → 157 → 184 → 213 °C along the barrel toward the melt/filter (smelt) end. Each zone tile has a small cyan bar = heating/cooling status indicator.

## Answers to open questions
- **Q15 (extruder temperature zones — which before/after laserfilter, why zone3 low) — MAJOR ANSWER.** This EREMA barrel uses zones **EZ-1 (feed) then ZZ-1/2/3** with an **increasing** ramp 113→157→184→213 °C from feed to die. The sim's list "200-235-175-240-245-250-255" is a DIFFERENT (higher, 7-zone) barrel — likely the OTHER extruder line, OR includes post-filter/die zones. Here the FEED zone (EZ-1) is the coolest (113 °C), which explains the sim's low "175" reading as a feed/intake zone rather than a mid-barrel zone. The physical logic: feed zone stays cool so pellets/crumb don't bridge/melt-plug at intake; melt temperature climbs toward the die and filter. So a low zone-3 in the sim (175 °C) is plausible if that index maps to a feed/vent/cooling zone, not a mid-melt zone.
- **Q30 (units) — DIRECT ANSWER.** On the EREMA mimic: **SV-vermogen (compactor power) = kW** (193 kW); **SV-belasting / ex-belasting (loads) = %** (61 %, 102 %); **extr rpm = rpm** (120). So "Vermogen hoofdmotor" on EREMA is **kW**; "belasting" (load) is the **%** channel; speed is **rpm**. The sim's "flotation_level ~44-61" is unrelated here, but note the pattern belasting=% (SV-belasting 61 %). Confirms load% and power-kW are separate channels.
- **Q16 ("Bunker speed 200-800" unit) — HINT.** Not directly named here; but this screen shows the analogous compactor/extruder speeds in **rpm** and fill in **cm** (SV-vulpeil 45 cm). Bunker/dosing "speed 200-800" is most likely an rpm or a raw actuator value, not %. No definitive unit here.
- **Q3 (SV feed / schuif) — RELATED.** The "schuif 100 %" slide gates compactor→extruder; SV-vulpeil (45 cm) is the compactor buffer level. Relevant to the compactor-to-extruder feed screw question (Q3) — shows a slide, not a shared screw, on this line.
- **Q33 — YES.** Real filled-in values: SV 193 kW / 61 % / 108 °C / 45 cm, extruder 120 rpm / 102 %, zones 113/157/184/213 °C.
- **Q28 (afzuiging/extraction) — DATA.** Two suction fans (afzuiging 1 = 55 %, afzuiging 2 = 0) on the compactor de-dust/vent — real setpoints.
