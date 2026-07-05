# OTHER: EREMA BluPort HMI screenshot — LIJN 3C

- **source_file:** 211_CeDo49 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C (labelled "LIJN 3C" on plate below screen)
- **pages:** 1
- **timestamp on screen:** 2:29:10  21-12-2024

## Photo description
Single photo of the EREMA BluPort HMI touchscreen mounted on the machine.
Yellow warning label taped above screen reads (partly cut): "…GEN … IN POSITIE …
NIET VERWIJDEREN OF MISVORMEN. 1 hollandisch" (left sticker) and a bright yellow
sticker centre-top: **"Afzuiging compactor !!! AAN !!!"** (compactor extraction MUST
be ON). Top-right of screen: EREMA logo and **BluPort** wordmark. Recipe title bar:
**"Rx  LDPE 800 kg/h  22.04.2024 IBN"** (Rx = recipe; IBN = Inbetriebnahme /
commissioning date). Bottom plate under the monitor: **LIJN 3C**.

## Left-hand vertical gauge column (live extruder readings, top to bottom)
| Pictogram | Value | Unit | Meaning (gloss) |
|---|---|---|---|
| clock | 112 | °C | temperature (melt/zone) |
| (same block) | 226,2 | kW | vermogen — power |
| ↑↑↑ (rpm icon) | 107 | rpm | toerental — screw speed |
| (%) | 65 | % | belasting — load |
| (h) | 3554 | h | bedrijfsuren — operating hours |
| ◇ (pressure) | **287** | bar | druk (highlighted orange — pre-filter melt pressure) |
| ⊟ | 26 | bar | druk (2nd pressure, likely differential/post) |
| ◇ | 193 | bar | druk (3rd pressure) |
| ⟿ (output) | **1385** | kg/h | doorzet — throughput |

Left vertical bar scale runs 0–600 (for kW/temp), red marker near top.

## Trend graph (centre)
- X-axis time: 2:12:29 → 2:29:08, 21-12-2024 (~17 min window)
- Right-hand Y scale 0–250 (green/yellow band markers at ~200–225)
- Legend traces:
  - **Toevoer actief** (cyan, square-wave bottom band) — infeed active on/off
  - **PCU – temperatuur 1** (green line, steady ~250 level)
  - **PCU – vermogen** (orange/red line, fluctuating ~200–230) — PCU power
  - **AIS – positie** (yellow flat line ~150) — AIS position
- AutoPro-control box top-right: **Uit** (OFF)

## Right-side data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil (fill level) | 266 cm |
| PES-toerental | 80 % |
| TEU-toerental | 30 % |
| PCU-belasting | 72 % |
| PCU-vermogen | 226,2 kW |

## Extruder mimic tiles (centre-bottom, over EREMA machine graphic)
| Tile | Value |
|---|---|
| BC1-toerental | 60 % |
| EX1-vermogen | 228,8 kW |
| EX1-toerental | 107 rpm |
| EX1-belasting | 65 % |
| AIS-positie | 70 % |
| PCU-temp. 1 | 112 °C |
| EX1-IZ1 (zone 1 temp) | 96 °C |

## Answers to open questions
- **Q29 (Is 3C the SCADA node hosting wash line 6?):** This HMI is labelled **LIJN 3C**
  and is clearly the **EREMA extruder/compactor (BluPort) control**, NOT a wash line.
  3C here = the EREMA regranulation line node, recipe "LDPE 800 kg/h". So 3C hosts the
  EREMA BluPort extruder line, contradicting the wash-line-6 guess. [evidence: plate
  "LIJN 3C" + BluPort recipe "LDPE 800 kg/h 22.04.2024 IBN"]
- **Q9/Q21 (line capacity / budget speed):** Recipe nameplate throughput **800 kg/h**
  (LDPE) is the *design* recipe for 3C; live **doorzet 1385 kg/h** was momentarily
  shown (throughput reading). [quote: "Rx LDPE 800 kg/h 22.04.2024 IBN" and left column
  "1385 kg/h"]
- **Q30 (units):** Confirms **Vermogen hoofdmotor = kW** (EX1-vermogen 228,8 kW),
  **Snelheid hoofdmotor = rpm** (EX1-toerental 107 rpm) with a separate **belasting = %**
  (EX1-belasting 65 %). PCU/PES/TEU/BC1 toerental reported in **%**. [evidence: tiles above]
- **Q15 (extruder zones):** EX1-IZ1 (infeed zone 1) shows **96 °C**; PCU-temp 1 = 112 °C.
  Low-numbered/infeed zones run cool (~96–112 °C) as expected. [evidence: EX1-IZ1 96 °C tile]
- Compactor extraction interlock note: sticker **"Afzuiging compactor !!! AAN !!!"**
  confirms the compactor dust extraction must be manually kept ON (operator reminder).
