# OTHER: EREMA BluPort HMI screenshot — LIJN 3C (5th frame, 3-1-2025, 120 rpm)

- **source_file:** 215_CeDo60 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C ("LIJN 3C" plate below monitor)
- **duplicate_of (same screen, different timestamp/values):** 211/212/213/214 CeDo (3C BluPort series)
- **pages:** 1
- **timestamp on screen:** clock 5:50:30, trend 5:33:50 → 5:50:29, **3-1-2025** (≈8 min after the 214 frame)

## Photo description
Same EREMA BluPort HMI touchscreen. Recipe title bar **"Rx LDPE 800 kg/h 22.04.2024 IBN"**.
Top-right AutoPro-control box: **Uit** (OFF). Top-right EREMA logo + **BluPort** wordmark.
Plate under monitor: **LIJN 3C**. The EX1-toerental setpoint tile shows **120** highlighted
(blue selection box) with a live **120 rpm** below it — screw held at 120 rpm this frame.
Bottom of photo shows the physical HMI hard-key pictograms row.

## Left vertical gauge column (live, top to bottom)
| Value | Unit | Meaning (gloss) |
|---|---|---|
| 114 | °C | temperature |
| 238,5 | kW | vermogen — power |
| 120 | rpm | toerental — screw speed |
| 70 | % | belasting — load |
| 3807 | h | bedrijfsuren — operating hours (same as 214 frame) |
| **273** | bar | druk (pre-filter melt pressure) |
| 24 | bar | druk (2nd pressure) |
| 186 | bar | druk (3rd pressure) |
| **1547** | kg/h | doorzet — throughput |

Left vertical bar scale 0–600. Trend X-axis 5:33:50 → 5:50:29, 3-1-2025. Trace legend same:
Toevoer actief (cyan) / PCU – temperatuur 1 (green) / PCU – vermogen (orange) / AIS – positie (yellow).

## Right data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil | 251 cm |
| PES-toerental | 70 % |
| TEU-toerental | 30 % |
| PCU-belasting | 76 % |
| PCU-vermogen | 238,5 kW |

## Extruder mimic tiles
| Tile | Value |
|---|---|
| BC1-toerental | 100 % |
| EX1-vermogen | 249,1 kW |
| EX1-toerental | 120 rpm (setpoint 120 highlighted) |
| EX1-belasting | 70 % |
| AIS-positie | 56 % |
| PCU-temp. 1 | 114 °C |
| EX1-IZ1 | 94 °C |

## Notes / answers
- **Q9/Q21 (throughput band):** doorzet **1547 kg/h** here at 120 rpm / 70 % load. Series
  for 3C now 1200 / 1385 / 1474 / 1547 / 1636 kg/h — real steady band ≈ 1200–1650 kg/h,
  recipe nameplate 800 kg/h. [quote: left column "1547 kg/h", EX1-toerental "120 rpm"]
- **Q30 (units):** confirms Vermogen = kW (238,5/249,1 kW), Snelheid = rpm (120 rpm),
  belasting = % (70 %). EX1-toerental setpoint field editable (blue box on "120").
- **Q16 (Bunker/BC1):** BC1-toerental back at 100 % here while PCU-vulpeil low (251 cm) —
  reinforces demand-driven % feed inversely tracking buffer fill (251 cm → 100 % feed).
- Melt-pressure differential (2nd pressure tile) steady ~24 bar across 3C frames — laserfilter Δp.
