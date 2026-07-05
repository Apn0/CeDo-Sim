# EREMA — Mogelijkheden voor procesaanpassingen + HMI overview screenshot (1kW / 10kg rule)

- **Source file:** `307_CeDo53.pdf` (single page, EREMA manual/training excerpt, scanned; large HMI overview screenshot)
- **SWI id:** none (EREMA training/manual page — process adjustment options + Cutter-Compactor/Extruder overview HMI)
- **Title:** Mogelijkheden voor procesaanpassingen (Options for process adjustments)
- **Scope:** Which levers the operator has to adjust the EREMA line (feeding setpoint, compactor disc speed, extruder speed, infeed-slider position) + annotated overview HMI mimic.
- **References:** EREMA Cutter-Compactor (CC) + extruder overview; overlaps PHOTO-erema-hmi-SV-extruder-livevalues, OTHER-erema-hmi-mimic-SV-compactor-extruder-zones.

## Text — Mogelijkheden voor procesaanpassingen (verbatim NL + EN gloss)
Bullet list:
- "Instelpunt van voeding, **basisregel = 1kW voor 10kg doorvoer**"
  - EN: *Feeding setpoint, **rule of thumb = 1 kW per 10 kg throughput**.*
- "Compactor schijfsnelheid (rpm)" — *Compactor disc speed (rpm).*
  - o "Extruder snelheid (rpm)" — *Extruder speed (rpm).*
  - o "Positie invoerschuif" — *Position of infeed slider (feed-slider position).*

## HMI overview screenshot (annotated mimic — description + all readable values)
Header: clock "**06:51 04/05/2021**", brand **EREMA** top-right.
Left half: trend graph, dual Y-axes.
- Left Y axis scale (°C, red/green temp trends): **250 / 225 / 200 / 175 / 150 / 125 / 100 / 75 / 50 / 25**.
- Right Y axis scale: **450 / 400 / 350 / 300 / 250 / 200 / 150 / 100 / 50**.
- X axis timestamps: "06:35:09 04/05/2021" … "06:51:40 04/05/2021".
- Legend: "feeding on", "cc - temperature (°F)" [unsure], "speed reel feeder (%)".

Right half: process mimic of Cutter-Compactor + extruder with live-value boxes (all reading 0 in this idle snapshot):
| Field | Value | Meaning (EN) |
|-------|-------|--------------|
| tracking control cutter compactor | **off** | CC tracking control state |
| reel feeder | **0 %** | reel/film feeder speed |
| cc - torque | **0 %** | cutter-compactor torque |
| cc - load | **0 %** | cutter-compactor load |
| cc - speed | **0 rpm** | cutter-compactor disc speed |
| cc - power | **0.0 hp** | cutter-compactor power (horsepower) |
| cc - temperature | **0 °F** | cutter-compactor temperature |
| slider | **0 %** | infeed slider position |
| extruder load | **0 %** | extruder motor load |
| extruder rpm | **0 rpm** | extruder screw speed |
| EZ-1 | **0 °F** | extruder zone 1 temperature |
| Z2-1 | **0 °F** | extruder zone 2-1 temperature |

Bottom nav bar (icons, left→right): **feeding / feeding selection**, **extruder**, **melt filter**, **downstream**, **alarms**, ▶ (next). Bottom-left button: "**feeding selection**".

## Key values (verbatim)
- Power/throughput rule of thumb: **1 kW ≈ 10 kg doorvoer (throughput)** → i.e. ~**0.1 kW per kg**.
- Operator adjustment levers: feeding setpoint, **compactor disc speed (rpm)**, **extruder speed (rpm)**, **infeed-slider position (%)**.
- HMI temp unit here shown in **°F** (cc-temperature, EZ-1, Z2-1); power in **hp**; trend graph °C on left axis.

## Q&A hits
- **Q30 (units — power_CC, snelheid):** ANSWERED partially. On this EREMA overview HMI: cc-power = **hp** (horsepower), cc-speed / extruder rpm = **rpm**, cc-load/torque/slider/reel-feeder = **%**, temperatures = **°F** (EZ-1, Z2-1, cc-temperature). Trend left-axis temps in **°C** (0–250). Note the plant HMI mixes °F on live boxes and °C on trend axis.
- **Q21 / Q9 (throughput budget):** Relevant — gives the sizing heuristic **1 kW ≈ 10 kg/h doorvoer**. Quote: "Instelpunt van voeding, basisregel = 1kW voor 10kg doorvoer." Useful to back-calc line kg/h from motor kW in the sim.
- **Q15 (temp zones):** trend axis top = **250 °C**; extruder zones labelled **EZ-1, Z2-1**. Not the full 200–255 sequence.
- Confirms operator's tuning model: feed setpoint drives compactor+extruder speed & slider position.
