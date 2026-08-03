# EREMA BluPort HMI screenshot — LIJN 3C overview (testrun recipe, 2-10-2024)

- **Source file:** `219_CeDo22 (3).pdf` (single page, 1.9 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI main overview (same screen layout as 206-210), earlier session, darker/dimmer capture.
- **SWI id:** none
- **Line:** LIJN 3C (same panel/screen; bottom label out of frame/dark but layout is identical).
- **Note:** Different recipe loaded than 206-210: **"EREMA testrun LDPE 22.02.24"** (a test-run recipe), and an earlier date (1-2 Oct 2024). Clearest LIJN 3C overview of the set (recipe name fully legible).

## Header
- **Rx  EREMA testrun LDPE 22.02.24** — recipe = "EREMA testrun LDPE", dated 22.02.24.
- Clock: **0:08:20 / 2-10-2024** (just past midnight into 2 Oct 2024).

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 107 | °C |
| power | 202,9 | kW |
| rpm | 96 | rpm |
| % | 50 | % |
| hours | 864 | h |
| diamond pressure | 259 | bar |
| square pressure | 21 | bar |
| diamond pressure | 145 | bar |
| output | 1115 | kg/h |

(Operating hours **864 h** here vs 3553-3603 h in Dec 2024 — confirms Oct 2024 is much earlier in this machine's run life.)

## Trend graph
- Left Y 0–600 (kW, red **PCU-vermogen** ~200-250). Right Y 0–250 (green **PCU-temperatuur 1**, yellow **AIS-positie** ~50).
- X-axis: 23:51:41 (1-10-2024) → 23:55:51 → 0:00:01 (2-10-2024) → 0:04:11 → 0:08:20.
- Legend: Toevoer actief (cyan square-wave, actively pulsing), PCU-vermogen (red), PCU-temperatuur 1 (green), AIS-positie (yellow).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 87 cm** (much lower fill than the 265-270 cm in Dec — testrun/low-feed condition)
- **PES-toerental: 70 %** | **TEU-toerental: 20 %**
- **PCU-belasting: 64 %** | **PCU-vermogen: 202,9 kW**

## Bottom mimic call-outs
- **BC1-toerental: 0 %**
- **EX1-vermogen: 171,8 kW**
- **AIS-positie: 33 %**
- **PCU-temp. 1: 107 °C**
- **EX1-toerental: 96 rpm**
- **EX1-belasting: 50 %**
- **EX1-IZ1: 85 °C**

## Q&A hits
- **Q9 (throughput):** LIJN 3C on a **testrun LDPE** recipe, live output **1115 kg/h** (lower than the 1342-1444 kg/h Dec production runs, consistent with a test/ramp condition). Extends 3C output evidence: ~1115 kg/h testrun vs ~1350-1450 kg/h production.
- **Q15/Q30:** melt 107 °C, EX1-IZ1 85 °C; power kW + % load, rpm + %, vulpeil cm — consistent with 206-210.
- **Q29:** Again the EREMA extruder/compactor overview — 3C HMI, not a wash SCADA host.
- Recipe date **22.02.24** and only **864 running hours** as of Oct 2024 → line 3C commissioned early 2024 (matches the "22.04.2024 IBN" commissioning recipe seen in 206-210).
