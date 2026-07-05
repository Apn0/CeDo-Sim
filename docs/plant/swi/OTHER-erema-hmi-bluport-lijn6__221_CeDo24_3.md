# EREMA BluPort HMI screenshot — LIJN 6 overview (testrun recipe, 2-10-2024, 2nd capture)

- **Source file:** `221_CeDo24 (3).pdf` (single page, 1.8 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI main overview (same screen as 220).
- **SWI id:** none
- **Line:** **LIJN 6** (blue engraved bottom label reads **"LIJN 6"**, dim but legible).
- **Note:** Same session/recipe as 220. Clock **2:02:29 / 2-10-2024** — ~2 h *before* 220's 4:01:31, ~2 h *after* 219's 0:08:20. So 219 (0:08) → 221 (2:02) → 220 (4:01) is one continuous LIJN 6 testrun night. Strengthens that **219 is also LIJN 6** (same recipe, hours 864/866/868 across the three).

## Header
- **Rx  EREMA testrun LDPE 22.02.24**
- Clock: **2:02:29 / 2-10-2024**

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 106 | °C |
| power | 198,4 | kW |
| rpm | 98 | rpm |
| % | 47 | % |
| hours | 866 | h |
| diamond pressure | 247 | bar |
| square pressure | 21 | bar |
| diamond pressure | 142 | bar |
| output | 1102 | kg/h |

(Hours **866 h** — between 219's 864 and 220's 868, exactly consistent with the 0:08 → 2:02 → 4:01 ordering.)

## Trend graph
- Left Y 0–600 (kW), right Y 0–250. Green **PCU-temperatuur 1** ~250, red **PCU-vermogen** ~175-200 (oscillating), yellow **AIS-positie** flat ~50, cyan **Toevoer actief** square-wave.
- X-axis: 1:45:51 → 1:50:00 → 1:54:10 → 1:58:20 → 2:02:30 (all 2-10-2024).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 105 cm**
- **PES-toerental: 80 %** | **TEU-toerental: 40 %**
- **PCU-belasting: 63 %** | **PCU-vermogen: 198,4 kW**

## Bottom mimic call-outs
- **BC1-toerental: 60 %** (with second highlighted **60 %** field — live vs setpoint)
- **EX1-vermogen: 167,0 kW**
- **AIS-positie: 33 %**
- **PCU-temp. 1: 106 °C**
- **EX1-toerental: 98 rpm**
- **EX1-belasting: 47 %**
- **EX1-IZ1: 80 °C**

## Q&A hits
- **Q26/Q2:** Second confirmation of **LIJN 6** as a distinct EREMA BluPort regranulation line. Three-capture testrun sequence (219→221→220) all on the same machine the night of 2-10-2024.
- **Q9:** LIJN 6 testrun output **1102 kg/h** (219/221/220 = 1115/1102/1045 kg/h → LIJN 6 testrun steadily ~1045-1115 kg/h).
- **Q30/Q15:** consistent units; EX1-IZ1 80 °C, melt 106 °C.
- **Q29:** extruder/compactor overview, not wash SCADA.
