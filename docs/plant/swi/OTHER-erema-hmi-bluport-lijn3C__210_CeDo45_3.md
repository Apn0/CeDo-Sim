# EREMA BluPort HMI screenshot — LIJN 3C (main overview, 5th capture)

- **Source file:** `210_CeDo45 (3).pdf` (single page, 5.1 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI (same panel/screen as 206-209)
- **SWI id:** none
- **Line:** LIJN 3C
- **Note:** Same 21-12-2024 session as 206-208 (clock 2:23:20, ~4 min after 206's 2:19:16, ~11 min before 207/208's 2:34).

## Physical signage
- WAARSCHUWING sticker (partial top-left): "...RUIK DEZE MACHINE NIET / ...DER VEILIGHEIDSCONTROLE / IN POSITIE / WAARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN / 1 hollandisch".
- Yellow: **STAAT / Afzuiging compactor / !!! AAN !!!**
- Bottom: **LIJN 3C**. BluPort EREMA top-right.

## Header
- **Rx LDPE 800 kg/h 22.04.2024 IBN**
- Clock: **2:23:20 / 21-12-2024**

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 111 | °C |
| power | 223,3 | kW |
| rpm | 105 | rpm |
| % | 62 | % |
| hours | 3553 | h |
| diamond pressure | 292 | bar |
| square pressure | 24 | bar |
| diamond pressure | 203 | bar |
| output | 1375 | kg/h |

## Trend graph
- Left Y-axis 0–600 (kW, red **PCU-vermogen** ~250). Right Y-axis 0–250 (green **PCU-temperatuur 1** ~100 on this scale, yellow **AIS-positie** ~75).
- X-axis: 2:06:39 → 2:10:49 → 2:14:59 → 2:19:09 → 2:23:18 (21-12-2024).
- Legend: Toevoer actief (cyan), PCU-vermogen (red), PCU-temperatuur 1 (green), AIS-positie (yellow).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 265 cm**
- **PES-toerental: 80 %** | **TEU-toerental: 30 %**
- **PCU-belasting: 71 %** | **PCU-vermogen: 223,3 kW**

## Bottom mimic call-outs
- **BC1-toerental: 15 %**
- **EX1-vermogen: 221,4 kW**
- **AIS-positie: 70 %**
- **PCU-temp. 1: 111 °C**
- **EX1-toerental: 105 rpm**
- **EX1-belasting: 62 %**
- **EX1-IZ1: 95 °C**

## Q&A hits
- **Q9:** LIJN 3C — recipe 800 kg/h LDPE, live output **1375 kg/h**. Fifth 3C sample; 206-210 range = 1342-1444 kg/h (all well above 800 setpoint).
- **Q15 zones:** EX1-IZ1 = 95 °C; melt temp 111 °C.
- **Q16/Q30:** BC1/PES/TEU speeds in %, power kW + % load, rpm + %, vulpeil cm — consistent.
- No new answers vs 206-209. Five of five 3C captures are the same extruder/compactor overview (Q29 counter-evidence: 3C HMI is the EREMA regranulation line, not a wash SCADA host).
