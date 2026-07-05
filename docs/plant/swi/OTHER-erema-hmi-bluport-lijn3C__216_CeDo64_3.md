# OTHER: EREMA BluPort HMI screenshot — LIJN 3C (6th frame, 17-2-2025, different recipe, low feed)

- **source_file:** 216_CeDo64 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C ("LIJN 3C" plate below monitor)
- **duplicate_of (same screen, different date/recipe/values):** 211/212/213/214/215 CeDo (3C BluPort series)
- **pages:** 1
- **timestamp on screen:** clock ~[unsure: 7:12 / 22:xx], trend 22:20:33 → 22:37:12, **17-2-2025**

## Photo description
Same EREMA BluPort HMI. **New recipe** in the title bar: **"Rx 1-14-25 production program rke"**
(NOT the "LDPE 800 kg/h" recipe used in the 211–215 frames — this is a named production
program, "rke"). AutoPro-control box: **Uit** (OFF). EREMA + **BluPort** wordmark top-right.
Plate under monitor: **LIJN 3C**. This frame captures a **ramp/low-feed** state: BC1-toerental
**0 %** (bunker feed stopped), EX1-belasting only 42 %, doorzet down to 737 kg/h while the
green PCU-temp trace is climbing — i.e. the line is being fed intermittently (cyan Toevoer-actief
trace shows gaps) and PCU is heating.

## Left vertical gauge column (live, left-cropped)
| Value | Unit | Meaning (gloss) |
|---|---|---|
| [unsure: …]99 | °C | temperature |
| [unsure: …]07,7 → 307,7 | kW | vermogen — power (matches PCU-vermogen tile 307,7 kW) |
| 80 | rpm | toerental — screw speed |
| 42 | % | belasting — load |
| 4632 | h | bedrijfsuren — operating hours (up from 3807 h → ~825 h later) |
| 172 | bar | druk (pre-filter melt pressure) |
| 12 | bar | druk (2nd pressure — differential, lowest in series) |
| 189 | bar | druk (3rd pressure) |
| 737 | kg/h | doorzet — throughput (lowest in series) |

Left bar scale 0–600. Trend X-axis 22:20:33 → 22:37:12, 17-2-2025. Legend same:
Toevoer actief (cyan) / PCU – temperatuur 1 (green) / PCU – vermogen (orange) / AIS – positie (yellow).

## Right data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil | 320 cm |
| PES-toerental | 75 % |
| TEU-toerental | 35 % |
| PCU-belasting | **98 %** (near max) |
| PCU-vermogen | 307,7 kW |

## Extruder mimic tiles
| Tile | Value |
|---|---|
| BC1-toerental | **0 %** (bunker/conveyor feed stopped) |
| EX1-vermogen | 118,7 kW (low — reduced feed) |
| EX1-toerental | 80 rpm |
| EX1-belasting | 42 % |
| AIS-positie | 30 % |
| PCU-temp. 1 | 99 °C |
| PCU-vermogen (2nd tile) | 245,0 kW |
| EX1-IZ1 | 71 °C (cool — low run) |

## Notes / answers
- **Q30 (units):** confirms across a *different* recipe too: kW / rpm / % set is stable
  (EX1-vermogen 118,7 kW, EX1-toerental 80 rpm, EX1-belasting 42 %). [evidence: tiles]
- **Q9/Q21 (throughput range floor):** at reduced/ramp feed the same 3C line drops to
  **737 kg/h** (BC1 0 %, EX1-belasting 42 %). So the 3C output range spans ~737 (low/ramp)
  up to ~1636 kg/h (hard run). [quote: "737 kg/h", "BC1-toerental 0 %"]
- **Recipe variety on 3C:** besides "LDPE 800 kg/h 22.04.2024 IBN", 3C also runs a named
  **"1-14-25 production program rke"** recipe — evidence the EREMA line runs multiple
  recipe/production-program presets. Useful for sim recipe-selection realism.
- **PCU-belasting can hit 98 %** while EX1 is lightly loaded (42 %) — decoupled: PCU
  (pre-conditioning) works hard on buffered material even when extruder feed is throttled.
- Melt-pressure differential (2nd pressure) here only **12 bar** — clean/low-Δp filter state
  vs ~24 bar in the LDPE frames. Lower throughput → lower laserfilter Δp.
