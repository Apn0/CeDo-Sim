# PHOTO — EREMA BluPort HMI trend graph (Smeltpomp 1 / massadruk, LDPE testrun) — frame 2 (clearer)

- **Source scan:** 290_CeDo30 (3).pdf (1 page, photo of HMI screen, landscape — sharper than 289)
- **Type:** EREMA **BluPort** operator-panel **trend graph** photo. **Sister frame to 289_CeDo29 (3)** — same "EREMA testrun LDPE 22.02.24" trend, captured **5 seconds later**: screen clock **17:35:15 20-10-2024** vs 17:35:10 on frame 1. This frame is clearer and lets several 289 [unsure] readings be confirmed/corrected.
- **No SWI id** (HMI screenshot).
- **Note:** distinct scan from 099_CeDo30 (compactor 3 training). "CeDo30 (3)" is its own photo.

## On-screen text (verbatim, corrected against sharper image)
- **Timestamp top-left:** **17:35:15  20-10-2024**.
- **Title top-centre:** **Rx  EREMA testrun LDPE 22.02.24** (stored LDPE test run, displayed 20-10-2024). Confirms same recipe/run as 289.

### Left-hand live value readout column (top → bottom) — CORRECTED vs 289:
| value | unit | note vs frame 1 (289) |
|-------|------|------------------------|
| **108** | °C | same |
| **160,8** | **kW** | frame 1 read "161,1 kG2 [unsure]"; sharper frame shows **160,8 kW** → this row is **drive power in kilowatts** (main-motor power), not a load figure. (Small drift 161,1→160,8 over the 5 s.) |
| **95** | rpm | same (screw/pump speed) |
| **62** | % | same (AutoPro drive load %) |
| **1126** | h | frame 1 read 1125/[1126] → confirmed **1126 h** running hours |
| **316** | bar | **orange/red alarm-highlight** pressure; frame 1 read 314 → drifted to **316 bar** (melt pressure, highlighted high) |
| **38** | bar | frame 1 read 34 → **38 bar** (second pressure gauge) |
| **137** | bar | frame 1 read 136 → **137 bar** (third pressure gauge) |
| **1146** | kg/h | frame 1 read 1147 → **1146 kg/h** throughput |

Icon stack beside rows (top→bottom): tacho/gauge, temperature/heat coils, delta-P/pressure, screen-filter delta-P, screen-filter, flow-out. Consistent with an EREMA melt line: temp → speed/%/hours → pressures across pump & filter → mass flow out.

### Trend plot (right)
- **Blue curve (top):** **"Smeltpomp 1 - toerental"** ("Melt pump 1 – rotational speed") — steps up to a high plateau just under full scale. Right Y-axis clearly marked **0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500** → **full scale ~500** (units: rpm for the pump-speed channel; the pressure channels share the same right axis in bar).
- **Yellow curve (mid, flat ~140–150):** **"Massadruk na smeltpomp 1"** ("Mass/melt pressure **after** melt pump 1") — sits ~140–150 on the right axis (bar), matching the **137 bar** live "after" reading.
- **Green curve (low, ~30–50, near-flat):** **"Massadruk voor smeltpomp 1"** ("Mass/melt pressure **before** melt pump 1") — low, matching the **38 bar** live "before" reading.
- **X-axis time labels (all 20-10-2024):** **17:18:36, 17:22:45, 17:26:55, 17:31:05, 17:35:15** — a ~17-minute trend window ending at the screen clock.
- **Bottom legend box:** "**Smeltpomp 1**" over "**Smeltdichtheid**" [unsure] ("Melt pump 1 / Melt density").
- Left mini bar-gauges: blue (top, ~full) and orange (mid) vertical indicators; right mini bar-gauges: green (top) and yellow (mid).

## Answers found
- **Q9 / large-line throughput (CONFIRMED):** **1146 kg/h** live throughput on this LDPE testrun, with **160,8 kW** drive power, **95 rpm**, **62 %** AutoPro load, melt pressures **316 / 38 / 137 bar**. This is the plant's **large EREMA line (~1150 kg/h class)**, distinct from the ~200–300 kg/h line in 284/285. Supports Q21's ~**1200 kg/hr** budget line being real plant kit. For the simulator: big line ≈ **1100–1200 kg/h @ ~160 kW**.
- **Melt-pressure delta-P monitoring (Q15 filter context, CONFIRMED):** trend explicitly plots **"Massadruk voor smeltpomp 1"** (before, ~38 bar / green) and **"Massadruk na smeltpomp 1"** (after, ~137 bar / yellow). The plant continuously monitors melt pressure **before and after the melt pump**, and a separate alarm-highlighted **316 bar** gauge — the pressures that drive **laserfilter/kopfilter screen-change decisions** (rising Δp = clogged screen). Model this as: dirtier melt/screen → higher post-filter/pump pressure → alarm → screen change.
- **Plant term confirmations:** **Smeltpomp** (melt/gear pump), **toerental** (rotational speed/rpm), **Massadruk** (melt/mass pressure), and drive **kW** readout — all confirmed EREMA/CeDo melt-line HMI terms for the extruder model.
- **289 corrections:** frame-1 "161,1 kG2" = **160,8 kW**; "314 bar" = **316 bar**; "34 bar" = **38 bar**; "136 bar" = **137 bar**; "1147 kg/h" = **1146 kg/h**; running hours **1126 h**. (Small live drift over the 5 s between frames.)
