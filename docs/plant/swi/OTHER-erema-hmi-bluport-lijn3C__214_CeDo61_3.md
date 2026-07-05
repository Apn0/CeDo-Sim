# OTHER: EREMA BluPort HMI screenshot — LIJN 3C (4th frame, 3-1-2025, max rpm)

- **source_file:** 214_CeDo61 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C ("LIJN 3C" plate)
- **duplicate_of (same screen, different date/values):** 211/212/213 CeDo (3C BluPort series)
- **pages:** 1
- **timestamp on screen:** trend 5:41:34 → 5:58:13, **3-1-2025**

## Photo description
Same EREMA BluPort HMI. Yellow sticker "Afzuiging compactor !!! AAN !!!". Recipe bar
"Rx LDPE 800 kg/h 22.04.2024 IBN". AutoPro-control: **Uit**. Plate **LIJN 3C**. This is
the hardest-running frame of the series — screw at the recipe max (130 rpm) and highest
throughput.

## Left vertical gauge column
| Value | Unit |
|---|---|
| 112 | °C |
| 243,1 | kW |
| **130** | rpm (screw at/near max) |
| 77 | % (load) |
| 3807 | h (operating hours — highest in series) |
| **280** | bar (pre-filter melt pressure) |
| 24 | bar |
| 201 | bar |
| **1636** | kg/h (highest throughput in series) |

Trend X: 5:41:34 → 5:58:13, 3-1-2025. Same trace legend.

## Right data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil | 259 cm |
| PES-toerental | 70 % |
| TEU-toerental | 30 % |
| PCU-belasting | 77 % |
| PCU-vermogen | 243,1 kW |

## Extruder mimic tiles
| Tile | Value |
|---|---|
| BC1-toerental | **13 %** (bunker/conveyor nearly idle — buffer not calling) |
| EX1-vermogen | 274,6 kW |
| EX1-toerental | 130 rpm |
| EX1-belasting | 77 % |
| AIS-positie | 56 % |
| PCU-temp. 1 | 112 °C |
| EX1-IZ1 | 96 °C |

## Notes / answers
- **Q30 (Snelheid hoofdmotor 0-130 unit):** This frame shows **130 rpm** — i.e. the
  "0–130" main-motor speed range in the SCADA export is **rpm**, and 130 is the top end
  (EX1-toerental 130 rpm here = the ceiling). [quote: left column "130 rpm", tile
  "EX1-toerental 130 rpm"] Confirms Q30 speed = rpm, full-scale 130.
- **Q30 (Vermogen hoofdmotor 0-119):** EX1-vermogen here 274,6 kW — so the raw "0-119"
  main-motor field is NOT kW (kW readings are 178–275). 0–119 is more consistent with a
  **% or amperage** scale; belasting (%) tops ~77 here, so 0-119 likely a % or a scaled
  load index, not kW. [evidence: EX1-vermogen 274,6 kW vs belasting 77 %]
- **Q9/Q21:** throughput series across 4 frames of 3C = 1200 / 1385 / 1474 / **1636 kg/h**
  (recipe nameplate 800 kg/h). Real steady band ≈ 1200–1650 kg/h for the 3C EREMA line.
- **Q16 (Bunker speed):** BC1-toerental swings 13 %→100 % across frames — a demand-driven %
  feed control, inversely tracking PCU buffer fill.
