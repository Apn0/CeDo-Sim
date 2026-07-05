# OTHER: EREMA BluPort HMI screenshot — LIJN 3C (3rd frame, next day)

- **source_file:** 213_CeDo57 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C ("LIJN 3C" plate)
- **duplicate_of (same screen, different day/values):** 211_CeDo49 (3).pdf / 212_CeDo53 (3).pdf
- **pages:** 1
- **timestamp on screen:** partly cut "…:39 …2-2024" trend spans 0:53:14 → 1:09:53, **23-12-2024**

## Photo description
Same EREMA BluPort HMI, photographed slightly cropped left. Yellow sticker top:
"Afzuiging compactor !!! AAN !!!". Recipe bar: **"Rx LDPE 800 kg/h 22.04.2024 IBN"**.
AutoPro-control: **Uit** (OFF). Plate: **LIJN 3C**. This frame captures a green PCU-temp
trace bump (~0:56–1:00) — a transient temperature rise — then settling.

## Left vertical gauge column (left-cropped labels)
| Value | Unit | (reading) |
|---|---|---|
| …6 | °C | temperature (leading digit cut) |
| …8,2 | kW | power |
| 95 | rpm | screw speed |
| 53 | % | load |
| …599 | h | operating hours (cf. 3554 h earlier → ~3599 h) |
| 256 | bar | melt pressure (pre-filter) |
| 34 | bar | pressure 2 |
| 194 | bar | pressure 3 |
| **1200** | kg/h | doorzet — throughput |

Trend X-axis: 0:53:14 → 1:09:53, 23-12-2024. Legend same
(Toevoer actief / PCU-temperatuur 1 / PCU-vermogen / AIS-positie).

## Right data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil | **498 cm** (much fuller than 266/268 cm frames) |
| PES-toerental | 80 % |
| TEU-toerental | 25 % |
| PCU-belasting | 72 % |
| PCU-vermogen | 228,2 kW |

## Extruder mimic tiles
| Tile | Value |
|---|---|
| BC1-toerental | **100 %** (bunker/conveyor at full) |
| EX1-vermogen | 178,6 kW |
| EX1-toerental | 95 rpm |
| EX1-belasting | 53 % |
| AIS-positie | 60 % |
| PCU-temp. 1 | 96 °C |
| EX1-IZ1 | 88 °C |

## Notes / answers
- **Q21 (the 1200 kg/hr budget speed — which line?):** Here **doorzet = exactly 1200 kg/h**
  on **LIJN 3C** (EREMA BluPort LDPE line). So the "1200 kg/hr" figure belongs to the
  3C EREMA regranulation line's steady output band. [quote: left column "1200 kg/h", plate
  "LIJN 3C", recipe "LDPE 800 kg/h"] — note recipe nameplate is 800 but real throughput
  runs 1200–1474 kg/h across these frames.
- **Q16 (Bunker speed 200-800 unit?):** BC1-toerental is reported here in **%** (100 %),
  so the standalone "Bunker speed 200-800" values on other docs are NOT this % field — more
  likely a rpm or a raw frequency/scale reading of a different bunker drive, not the BluPort
  BC1. (BC1 on BluPort caps at 100 %.) [evidence: "BC1-toerental 100 %"]
- **Q30**: confirms same unit set (kW / rpm / %).
- PCU-vulpeil range now spans 266–498 cm across the three frames — buffer fill level in cm.
