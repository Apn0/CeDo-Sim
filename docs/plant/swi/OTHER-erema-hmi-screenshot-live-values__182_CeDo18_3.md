# EREMA HMI screenshot — live process values (extruder line)

- **Source file:** 182_CeDo18 (3).pdf (1 page, photo of HMI touchscreen)
- **Doc id / slug:** OTHER-erema-hmi-screenshot-live-values
- **Doc type:** Photograph of EREMA extruder HMI main screen showing LIVE (real, filled-in) process values
- **Timestamp on screen:** 6:01:13, 12-9-2024 (12 Sep 2024) — early-morning shift reading
- **Related:** OTHER-erema-hmi-screenshot__165_CeDo66_3.md (another HMI shot)

## Screen layout
Left column = a vertical strip of pictograms each paired with a live numeric value + unit. Right side = three stacked buttons/panels. Right edge shows a partial vertical scale (numbers 32/50/62/75/8x/10x/1x... cut off at frame edge — a bar-graph axis).

## Live values (top to bottom, VERBATIM) with pictogram meaning
| Pictogram | Value | Unit | Meaning (best reading) |
|---|---|---|---|
| Circle with S-swirl (screw/extruder symbol) | 118 | °C | Melt/screw temperature |
| (same group, 2nd line) | 162,7 | kW | Actual electrical power draw of main drive |
| Heating-coils symbol ("≋₃" wavy lines, subscript 3) | 140 | rpm | Main-motor / screw speed |
| (same) | 85 | % | Main-motor load / speed as % of max |
| (same) | 1872 | h | Operating hours (running-hour counter) |
| Diamond-with-dot ◆₁ | 206 | bar | Melt pressure sensor 1 (pre-filter) |
| Boxed-8 / gauge ⊡₁ | 49 | bar | Pressure differential / filter Δp sensor 1 [unsure: could be Δp across laserfilter] |
| Diamond-with-dot ◆₂ | 232 | bar | Melt pressure sensor 2 (post-filter) |
| Output/arrow symbol ⤶ | 1684 | kg/h | Throughput (output rate) — units shown as "kg / h" |

## Right-side panels (VERBATIM, low-res)
- **"Actueel benodigde elektrische energie"** (Currently required electrical energy) — panel, value area blank/washed out in photo.
- **"Elektrisch energieverbruik"** (Electrical energy consumption) — panel, value area blank in photo.
- **"Reset"** — button.

## Answers to open questions
- **Q30 (units) — DIRECT ANSWER (strong).** On this EREMA extruder HMI: **Vermogen hoofdmotor = kW** (162,7 kW shown, i.e. the "power" reading is kilowatts, not %/A). **Snelheid hoofdmotor: BOTH rpm AND % are shown** — 140 rpm alongside 85 % (so rpm is absolute speed, % is speed-as-fraction-of-max). This resolves the sim's "Snelheid hoofdmotor (0-130)" as most likely **rpm** (140 here slightly above 130) OR the % channel. Throughput channel = **kg/h**.
- **Q15 (extruder temperature) — HINT.** The single big temperature shown here is 118 °C on the screw/melt symbol — this is a compactor/feed-zone-style reading, NOT one of the barrel zone setpoints (200-235-175-240-245-250-255). This screen shows melt-side pressures (206/49/232 bar) that bracket a filter: 206 bar before, 232 bar after, 49 bar as the differential — consistent with a laserfilter Δp. Supports that the pressure pair straddles the laserfilter.
- **Q32 (do real softstarter/frictiewasser power exports exist?) — PARTIAL / RELATED.** Real live power export DOES exist for the EXTRUDER main drive: 162,7 kW captured here, plus dedicated "Actueel benodigde elektrische energie" and "Elektrisch energieverbruik" HMI panels. (This is extruder, not frictiewasser/softstarter specifically.)
- **Q33 (do real filled-in hourly extruder values exist?) — YES (strong).** This is a genuine live snapshot: 118 °C, 162,7 kW, 140 rpm / 85 %, 1872 running hours, melt pressures 206/49/232 bar, throughput 1684 kg/h, dated 12-9-2024 06:01. Real operating data point for calibrating the sim's extruder line.
- **Q21 (1200 kg/hr budget line) — RELATED.** Actual measured throughput here = 1684 kg/h, above a 1200 kg/h budget — a real datapoint for line capacity (Q9).
- **Q9 (line capacity) — DATA.** Measured throughput 1684 kg/h at 140 rpm / 85 % load, 162,7 kW.
