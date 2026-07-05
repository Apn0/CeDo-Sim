# EREMA BluPort HMI screenshot — LIJN 3C (main overview, 2nd capture)

- **Source file:** `207_CeDo51 (3).pdf` (single page, 5.6 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI touchscreen (same panel as 206_CeDo41)
- **SWI id:** none (HMI photo)
- **Line:** LIJN 3C
- **Scope:** Live process values overview, ~15 min after 206 capture

## Physical signage (same as 206)
- WAARSCHUWING sticker (partial, top-left): "...RUIK DEZE MACHINE NIET / ...ER VEILIGHEIDSCONTROLE / IN POSITIE".
- Yellow sign: **STAAT / Afzuiging compactor / !!! AAN !!!**
- Bottom label: **LIJN 3C**
- BluPort EREMA logos top-right.

## Header
- **Rx LDPE 800 kg/h 22.04.2024 IBN**
- Clock: **2:34:38 / 21-12-2024** (~15 min later than 206's 2:19:16)

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 110 | °C |
| power | 228,3 | kW |
| rpm | 113 | rpm |
| % | 68 | % |
| hours | 3554 | h |
| diamond pressure | 298 | bar (red/highlight) |
| square pressure | 23 | bar |
| diamond pressure | 202 | bar |
| output | 1444 | kg/h |

## Trend graph
- Same layout. X-axis: 2:17:59 → 2:22:09 → 2:26:19 → 2:30:29 → 2:34:38 (21-12-2024).
- Traces: Toevoer actief (cyan), PCU-vermogen (red), PCU-temperatuur 1 (green ~250), AIS-positie (yellow ~150).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 265 cm** (note: labeled "vulpeil" here vs "vulniveau" in 206 — same meaning, fill level)
- **PES-toerental: 80 %** | **TEU-toerental: 30 %**
- **PCU-belasting: 72 %** | **PCU-vermogen: 228,3 kW**

## Bottom mimic call-outs
- **BC1-toerental: 60 %** (belt conveyor 1 now running at 60%, vs 0% in 206)
- **EX1-vermogen: 242,2 kW** [unsure: could read 242,7]
- **AIS-positie: 70 %**
- **PCU-temp. 1: 110 °C**
- **EX1-toerental: 113 rpm**
- **EX1-belasting: 68 %**
- **EX1-IZ1: 97 °C**

## Q&A hits
- **Q9 (throughput):** LIJN 3C recipe target **800 kg/h LDPE**; live output **1444 kg/h** (higher than 206's 1348). Confirms 3C runs well above nominal 800 setpoint instantaneously.
- **Q16 (Bunker speed unit):** BC1-toerental & PES/TEU-toerental all in **%** here (belt/screw speeds expressed as %). No 200-800 range visible.
- **Q30 (units):** power kW + load % both present; speed rpm + % both present; PCU-vulpeil in **cm**.
- **Q29:** again an extruder/compactor overview, not a wash SCADA screen.
- Delta from 206: BC1 0%→60%, PCU-vulpeil 269→265 cm, output 1348→1444 kg/h, pressure 291→298 bar.
