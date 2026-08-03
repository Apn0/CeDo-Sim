# EREMA HMI screenshot #3 — live values + specific energy 0,159 kWh/kg

- **Source file:** 184_CeDo20 (3).pdf (1 page, photo of HMI touchscreen)
- **Doc id / slug:** OTHER-erema-hmi-screenshot-live-values-3
- **Doc type:** Photograph of same EREMA extruder HMI, 5 s after 182, 2 s after 183
- **Timestamp on screen:** 6:01:18, 12-9-2024 (sequence: 182=6:01:13, 183=6:01:16, 184=6:01:18)
- **Related:** 182_CeDo18_3, 183_CeDo19, 165_CeDo66_3

## Live values (top to bottom, VERBATIM)
| Pictogram | Value | Unit | Meaning |
|---|---|---|---|
| Circle S-swirl | 118 | °C | Melt/screw temp (steady 118) |
| (same) | 161,6 | kW | Main-drive power (162,7 → 163,1 → **161,6**, fluctuating) |
| Coils "≋₃" | 140 | rpm | Screw speed |
| (same) | 86 | % | Load % (85 → **86**) |
| (same) | 1872 | h | Operating hours |
| Diamond ◆₁ | 201 | bar | Melt pressure pre-filter (206→205→**201**) |
| Boxed-8 ⊡₁ | 51 | bar | Filter Δp (49→50→**51**) |
| Diamond ◆₂ | 231 | bar | Melt pressure post-filter |
| Output ⤶ | 1692 | kg/h | Throughput (1684→1685→**1692**) |

## Right panel — NOW LEGIBLE (VERBATIM)
- **"Actueel benodigde elektrische energie"** (Currently required electrical energy): value **`0,159 kWh / kg`** — i.e. **0,159 kWh per kg** of throughput. This is the specific energy consumption of the extruder.
- **"Elektrisch energieverbruik"** (Electrical energy consumption): panel value washed out.
- **"Reset"** button.
- Right-edge bar scale: throughput axis 0…1875 kg/h (as in 183); a second live trend/graph now visible lower right with a timestamp "5:44:5x" and a green/orange trend curve.

## Sanity check on 0,159 kWh/kg
161,6 kW ÷ 1692 kg/h = 0,0955 kW·h/kg. Displayed 0,159 kWh/kg is higher → the "actueel benodigde elektrische energie" figure likely includes more than just the main-drive kW (heaters, ancillaries) or is a rolling/normalized figure. Record the displayed value 0,159 kWh/kg verbatim; note the main-drive-only ratio ≈ 0,096 kWh/kg.

## Answers to open questions
- **Q30/Q33 — CONFIRMS.** Third live frame; power kW, speed rpm+%, throughput kg/h all ticking. Real filled-in extruder data. Adds **specific energy = 0,159 kWh/kg** as a real KPI the sim can display/target.
- **Q9 — DATA.** Steady-state ≈ 1690 kg/h at ~162 kW, 140 rpm/86 %, melt 201/231 bar, Δp 51 bar, 118 °C. Specific energy 0,159 kWh/kg (displayed).
- **Q15 — HINT.** Pressure pair 201/231 bar around the filter, Δp 51 bar (climbing 49→50→51 over 5 s = screen slowly loading / filter). Supports laserfilter-Δp interpretation.
- **Q32 — YES.** Real per-kg energy export exists on the HMI (0,159 kWh/kg panel).
