# EREMA BluPort HMI screenshot — LIJN 3C (main overview screen)

- **Source file:** `206_CeDo41 (3).pdf` (single page, 5.1 MB photo)
- **Doc type:** Photograph of an EREMA BluPort HMI touchscreen, physical machine panel
- **SWI id:** none (HMI photo, not a work instruction)
- **Line:** LIJN 3C (blue engraved label bottom of panel)
- **System:** EREMA / BluPort (logos top-right: "BluPort EREMA")
- **Scope:** Live process values, main extruder+compactor overview mimic

## Panel labels / physical signage
- Top-left white sticker: **WAARSCHUWING** (warning) — "GEBRUIK DEZE MACHINE NIET ZONDER VEILIGHEIDSCONTROLE IN POSITIE" ("Do not use this machine without safety guard/check in position"). Small text: "WAARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN", "1 hollandisch".
- Top-center yellow sign: **STAAT / Afzuiging compactor / !!! AAN !!!** ("Status / compactor extraction/suction / ON") — i.e. compactor exhaust extraction is ON.
- Bottom blue label: **LIJN 3C**

## Header (recipe bar)
- **Rx  LDPE 800 kg/h  22.04.2024 IBN** — recipe: LDPE at 800 kg/h, dated 22-04-2024, "IBN" (Inbetriebnahme / commissioning recipe).
- Clock: **2:19:16 / 21-12-2024**

## Left-column live values (top to bottom, with pictogram)
| Pictogram | Value | Unit | Meaning (gloss) |
|---|---|---|---|
| thermometer/clock | 109 | °C | melt temperature |
| (power) | 226,8 | kW | motor/extruder power |
| (rpm bars) | 105 | rpm | screw speed |
| (%) | 63 | % | load/belasting |
| (hours) | 3553 | h | operating hours |
| diamond (pressure) | 291 | bar | pressure (red/highlighted — pre-filter melt pressure) |
| square (pressure) | 24 | bar | pressure (2nd point) |
| diamond (pressure) | 203 | bar | pressure (3rd point) |
| output arrow | 1348 | kg/h | throughput/output rate |

## Trend graph
- Left Y-axis 0–600 (kW scale, red trace **PCU-vermogen**).
- Right Y-axis 0–250 (green **PCU-temperatuur 1** ~250, yellow **AIS-positie** ~150).
- Cyan square-wave bottom trace: **Toevoer actief** (feed active on/off).
- X-axis timestamps: 2:02:37 → 2:06:47 → 2:10:57 → 2:15:07 → 2:19:16, all 21-12-2024.
- Legend: Toevoer actief (cyan), PCU-vermogen (red/orange), PCU-temperatuur 1 (green), AIS-positie (yellow).

## Right-side buttons / mimic values
- **AutoPro-control**  →  **Uit** (OFF)
- **PCU-vulniveau: 269 cm** (PCU fill level)
- **PES-toerental: 75 %** | **TEU-toerental: 25 %**
- **PCU-belasting: 72 %** | **PCU-vermogen: 226,8 kW**
- Blue water-droplet triangle icon = compactor/PCU feed mimic.

## Bottom mimic call-out boxes (EX1 = extruder 1)
- **BC1-toerental: 0 %** (belt conveyor 1 speed = 0)
- **EX1-vermogen: 223,0 kW**
- **AIS-positie: 70 %**
- **PCU-temp. 1: 109 °C**
- **EX1-toerental: 105 rpm** (highlighted field shows **105 rpm**)
- **EX1-belasting: 63 %**
- **EX1-IZ1: 94 °C** (IZ1 = intake/first heating zone temp)
- EREMA logo on the extruder body mimic.

## Q&A hits
- **Q29 (3C = SCADA host for wash line 6?):** No evidence here — this 3C screen is an **extruder/compactor (regranulation) overview**, showing EX1 + PCU (compactor) values, recipe "LDPE 800 kg/h". No wash-line data. (Adds counter-evidence: 3C HMI shown here is the EREMA extruder line HMI, not a wash SCADA host.)
- **Q30 (units):** Vermogen hoofdmotor shown in **kW** (226,8 kW) AND load separately in **% (63 %)**; Snelheid in **rpm** (105 rpm) with a separate **% (63/70 %)** field; so both kW and % appear, rpm and % appear. PCU-vulniveau in **cm** (269 cm).
- **Q15/temp zones:** melt temp 109 °C, EX1-IZ1 (zone 1) 94 °C shown; not the full 200-235-175-240... ladder.
- **Q9 (throughput):** recipe target **800 kg/h (LDPE)**; live output field reads **1348 kg/h** (instantaneous, higher than recipe setpoint). This is a LIJN 3C figure.
- **Q10/blauwe tank:** not shown.
- No answer to Q1–Q8, Q11–Q14, Q16–Q28, Q31–Q33 on this page.

*Note: "IBN" = Inbetriebnahme (commissioning), German EREMA term. AIS = likely melt-filter screen/piston position sensor. PCU = Plast Compactor Unit. PES/TEU = auxiliary drive designations.*
