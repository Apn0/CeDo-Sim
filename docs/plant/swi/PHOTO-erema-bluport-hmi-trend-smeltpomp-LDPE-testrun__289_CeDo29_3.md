# PHOTO — EREMA BluPort HMI trend graph (Smeltpomp 1 / massadruk, LDPE testrun)

- **Source scan:** 289_CeDo29 (3).pdf (1 page, photo of HMI screen, landscape, close-up of the trend display)
- **Type:** EREMA **BluPort** operator-panel **trend graph** photo. Same HMI family as 284_CeDo12 (3) and 285_CeDo13 (3), but a **different run**: this one is titled "**EREMA testrun LDPE 22.02.24**" (not the 22.04.2024 IBN of 284/285) and the trend channels shown are **melt-pump (smeltpomp) speed + melt pressure**, not throughput kg/h.
- **No SWI id** (HMI screenshot).
- **Note:** distinct scan from 283_CeDo29 (2) (= SWI-042 p4) and from 102_CeDo29 (compactor 3B training). "CeDo29 (3)" is its own photo.

## On-screen text (verbatim)
- **Timestamp top-left:** **17:35:10  20-10-2024** (photo/screen clock).
- **Title top-centre:** **Rx  EREMA testrun LDPE 22.02.24** ("Rx" = the recipe/prescription icon on the BluPort toolbar). So this trend is reviewing a **stored LDPE test run dated 22.02.24**, displayed on 20-10-2024.
- Blue circular-arrows EREMA/AutoPro logo top-right.

### Left-hand live value readout column (top → bottom), each `value  unit`:
| value | unit | interpretation |
|-------|------|----------------|
| **108** | °C | temperature (melt/zone temperature) |
| **161,1** | kG2 [unsure: kg/2, likely a scaled load/torque or kg/cm² reading] | [unsure] |
| **95** | rpm | screw or pump speed (rpm) |
| **62** | % | drive load / AutoPro % |
| **1125** [unsure: 1126] | h | running hours |
| **314** | bar | pressure (shown in **orange/red** = alarm-high highlight) — melt pressure **before** filter |
| **34** | bar | pressure (second gauge) |
| **136** | bar | pressure (third gauge) — melt pressure **after** smeltpomp |
| **1147** | kg/h | **throughput** (mass flow) |

(Icons beside each row: gauge/tacho, delta-P, filter/screen, delta-P, flow — the standard EREMA melt-line instrument stack. Exact °C vs bar assignment per icon is [unsure] due to blur.)

### Trend plot (right, ~5 min window)
- **Blue curve (top):** steps up from ~mid to a high plateau near full-scale — labelled **"Smeltpomp 1 – toerental"** ("Melt pump 1 – rotational speed / rpm"). Right Y-axis 0–~700 (marked 100…700).
- **Green curve (bottom, low, flat):** labelled **"Massadruk voor smeltpomp 1"** ("Mass/melt pressure **before** melt pump 1").
- **Yellow curve (mid, flat plateau ~120):** labelled **"Massadruk na smeltpomp 1"** [unsure: exact label — reads "Massadruk na smeltpomp 1"] ("Mass/melt pressure **after** melt pump 1").
- **X-axis time labels:** 17:18:30, 17:22:00, 17:26:40, 17:29:00, 17:20:00 [unsure ordering; all dated 20-10-2024].
- **Bottom legend box:** "**Smeltpomp 1**" over "**Snelheid** [unsure: Snelheid]" ("Melt pump 1 / Speed").

## Answers found
- **Q9 / throughput context:** live readout shows **1147 kg/h** and a right-axis melt-pump-speed trend to ~700 — this is a **much larger EREMA line than the 284/285 ~200–300 kg/h line**. A ~1147 kg/h reading is consistent with the **~1200 kg/hr line** referenced in Q21's budget. So the plant runs at least one small EREMA line (~200–300 kg/h, the 22.04.2024 IBN trend) **and** one large line at ~**1100–1200 kg/h** (this LDPE testrun). Useful to distinguish lijn 3C (small) vs the big line for the simulator.
- **Melt-line instrument stack (Q15 melt-filter context):** the trend explicitly separates **"Massadruk vóór smeltpomp 1"** (pressure before melt pump) and **"Massadruk ná smeltpomp 1"** (pressure after melt pump), with a live **314 bar** (alarm-highlighted) pressure. This confirms the plant monitors **melt pressure before/after the melt pump and across the filter** — the delta-P that drives a laserfilter/kopfilter screen change (rising Δp = dirty screen). Directly relevant to modelling filter-fouling → pressure-rise → screen-change in the simulator.
- **"Smeltpomp"** ("melt pump" = gear/melt pump downstream of the extruder screw, before the die) and **"Massadruk"** ("mass/melt pressure") are confirmed EREMA/CeDo plant terms for the extruder melt line.
