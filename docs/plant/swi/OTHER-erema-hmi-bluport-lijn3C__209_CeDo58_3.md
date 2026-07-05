# EREMA BluPort HMI screenshot — LIJN 3C (main overview, 23-12-2024)

- **Source file:** `209_CeDo58 (3).pdf` (single page, 5.5 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI (same panel/screen as 206-208), different day
- **SWI id:** none
- **Line:** LIJN 3C

## Physical signage
- WAARSCHUWING sticker (partial): "IN POSITIE / ...CHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN / 1 hollandisch".
- Yellow: **STAAT / Afzuiging compactor / !!! AAN !!!**
- Bottom: **LIJN 3C**. BluPort EREMA top-right.

## Header
- **Rx LDPE 800 kg/h 22.04.2024 IBN**
- Clock: **5:06:10 / 23-12-2024** (2 days after 206-208)

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 110 | °C |
| power | 223,2 | kW [unsure: could read 223,8] |
| rpm | 118 | rpm |
| % | 61 | % |
| hours | 3603 | h |
| diamond pressure | 270 | bar |
| square pressure | 24 | bar |
| diamond pressure | 194 | bar |
| output | 1342 | kg/h |

## Trend graph
- X-axis: 4:49:30 → 4:53:40 → 4:57:50 → 5:02:00 → 5:06:09 (23-12-2024).
- Traces: Toevoer actief (cyan), PCU-vermogen (red ~200), PCU-temperatuur 1 (green ~250), AIS-positie (yellow, lower here ~100).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 270 cm**
- **PES-toerental: 75 %** | **TEU-toerental: 25 %**
- **PCU-belasting: 71 %** | **PCU-vermogen: 222,8 kW**

## Bottom mimic call-outs
- **BC1-toerental: 0 %**
- **EX1-vermogen: 215,5 kW**
- **AIS-positie: 40 %** (lower than 70% in prior captures)
- **PCU-temp. 1: 110 °C**
- **EX1-toerental: 118 rpm**
- **EX1-belasting: 61 %**
- **EX1-IZ1: 81 °C**
- **NEW boxed field near EX1-IZ1: 224,8 kW** (highlighted blue box) — appears to be a second/live EX1-vermogen readout or a cursor-selected value.

## Q&A hits
- **Q9:** LIJN 3C — 800 kg/h recipe, live output **1342 kg/h**. Fourth 3C sample; range across 206-209 = 1342-1444 kg/h.
- **Q15 zones:** EX1-IZ1 (zone 1) = 81 °C this capture (vs 94-97 earlier) — first heating zone varies 81-97 °C.
- **Q30:** power kW + % load, rpm + %, vulpeil cm — consistent.
- AIS-positie swings 40-70% across captures (melt-filter/screen position).
