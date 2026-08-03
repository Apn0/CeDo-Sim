# EREMA HMI screenshot #2 — live process values + throughput bar scale

- **Source file:** 183_CeDo19.pdf (1 page, photo of HMI touchscreen)
- **Doc id / slug:** OTHER-erema-hmi-screenshot-live-values-2
- **Doc type:** Photograph of same EREMA extruder HMI main screen, 3 s later than 182
- **Timestamp on screen:** 6:01:16, 12-9-2024 (vs 6:01:13 in 182_CeDo18(3)) — same shift, same run
- **Related:** OTHER-erema-hmi-screenshot-live-values__182_CeDo18_3.md, OTHER-erema-hmi-screenshot__165_CeDo66_3.md

## Live values (top to bottom, VERBATIM)
| Pictogram | Value | Unit | Meaning |
|---|---|---|---|
| Circle S-swirl (screw/extruder) | 118 | °C | Melt/screw temperature (unchanged from 182) |
| (same group) | 163,1 | kW | Actual main-drive electrical power (was 162,7 → 163,1, live fluctuation) |
| Heating-coils "≋₃" | 140 | rpm | Main-motor / screw speed |
| (same) | 85 | % | Main-motor load / % of max |
| (same) | 1872 | h | Operating hours |
| Diamond ◆₁ | 205 | bar | Melt pressure 1, pre-filter (was 206) |
| Boxed-8 ⊡₁ | 50 | bar | Filter Δp / differential (was 49) |
| Diamond ◆₂ | 231 | bar | Melt pressure 2, post-filter (was 232) |
| Output ⤶ | 1685 | kg/h | Throughput (was 1684) — units "kg / h" |

## Right-side bar-graph scale (VERBATIM, this shot shows it clearly)
Vertical axis labels top→bottom, with a colored bar (green top → yellow → orange/red segments):
`2xx (green) … 2x … 22x … 21x … 20x (orange marker) … 1875 … 1750 … 1625 … 1500 … 1375 … 1250 … 1125 … 1000 … 875 … 750 … 625 … 500 … 375 … 250 … 125 … 0`
- The dense lower scale (0, 125, 250, 375, ... 1875) is the **throughput (kg/h)** bar-graph axis, ranging **0 to ~1875+ kg/h**. Current 1685 kg/h sits near the top (green/upper band).
- Top cluster (green→orange, ~200–232) is a second bar = **melt pressure (bar)** scale, with the orange marker near 205–232 bar (matching the pressure sensors).

## Answers to open questions
- **Q9 / Q21 (line capacity, budget speed) — DATA.** Throughput bar axis maxes around **1875 kg/h**; live throughput 1685 kg/h. Confirms this extruder line runs ~1685 kg/h, well above a 1200 kg/h budget figure. The design/max end of the scale ≈ 1875 kg/h.
- **Q30 (units) — CONFIRMS 182.** Power = kW (163,1), speed = rpm (140) with parallel % (85), throughput = kg/h. Two consecutive frames 3 s apart show kW and kg/h ticking (162,7→163,1; 1684→1685), proving these are live analog readings, not static labels.
- **Q15 (temperature zones) — HINT (same as 182).** Pressure pair 205/231 bar with 50 bar differential brackets the melt filter (laserfilter). 118 °C is the feed/compactor-side reading, not a barrel zone setpoint.
- **Q33 (real filled-in extruder values) — YES.** Second confirming live snapshot; values drift frame-to-frame, genuine operating data (12-9-2024, run-hour 1872).
- **Q32 — same as 182:** real kW export exists for extruder main drive.
