# EREMA BluPort HMI screenshot — LIJN 6 overview (testrun recipe, 2-10-2024)

- **Source file:** `220_CeDo25 (3).pdf` (single page, 2.1 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI main overview (identical screen layout to 206-210/219).
- **SWI id:** none
- **Line:** **LIJN 6** — the blue engraved bottom label clearly reads **"LIJN 6"** (not 3C!).
- **IMPORTANT:** This is the **same EREMA BluPort HMI screen design** as the "LIJN 3C" captures, same recipe **"EREMA testrun LDPE 22.02.24"**, same Oct 2024 session (~4 h after 219's 0:08:20). So CeDo has **at least two EREMA BluPort regranulation lines** whose HMIs look identical: one labelled **LIJN 3C** and one labelled **LIJN 6**. The bottom-panel engraved label is the only way to tell them apart.

## Physical signage
- Partial white sticker top-left (dim): "...Plant C1" [unsure] readable at bottom of the sticker — possibly a machine/asset tag referencing "Plant C1" area.

## Header
- **Rx  EREMA testrun LDPE 22.02.24**
- Clock: **4:01:31 / 2-10-2024** (~4 h after the 219 capture at 0:08:20 same night)

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 104 | °C |
| power | 180,2 | kW |
| rpm | 95 | rpm |
| % | 49 | % |
| hours | 868 | h |
| diamond pressure | 256 | bar |
| square pressure | 21 | bar |
| diamond pressure | 112 | bar |
| output | 1045 | kg/h |

(Operating hours **868 h** — nearly the same as 219's 864 h, confirming same machine + same night. But this is LIJN 6, and 219 layout matched 3C — see note: 219's line label was out of frame; given identical recipe/hours it is plausible 219 is ALSO LIJN 6, not 3C. See Q&A.)

## Trend graph
- Left Y 0–600 (kW), right Y 0–250. Green **PCU-temperatuur 1** ~250, red **PCU-vermogen** ~150-175, yellow **AIS-positie** stepping 50→75→100, cyan **Toevoer actief** square-wave.
- X-axis: 3:44:51 → 3:49:01 → 3:53:11 → 3:57:21 → 4:01:30 (all 2-10-2024).

## Right buttons / mimic
- **AutoPro-control → Uit**
- **PCU-vulpeil: 101 cm** (low fill — testrun)
- **PES-toerental: 80 %** | **TEU-toerental: 22 %**
- **PCU-belasting: 57 %** | **PCU-vermogen: 180,2 kW**

## Bottom mimic call-outs
- **BC1-toerental: 80 %**
- **EX1-vermogen: 166,2 kW**
- **AIS-positie: 50 %**
- **PCU-temp. 1: 104 °C**
- **EX1-toerental: 95 rpm** (with a second highlighted **95 rpm** field just below — live vs setpoint)
- **EX1-belasting: 49 %**
- **EX1-IZ1: 70 °C**

## Q&A hits
- **Q26 / Q2 (floorplan, which lines exist):** Confirms a **LIJN 6** EREMA BluPort regranulation line exists, distinct from **LIJN 3C**, with an **identical HMI**. So the "3C" HMI photos (206-210) and this "6" HMI are two separate physical lines sharing the same EREMA BluPort screen design. The partial "...Plant C1" sticker may relate to line 3A "block C1" (Q2) — [unsure], flagged.
- **Q9 (throughput):** LIJN 6 testrun output **1045 kg/h** (recipe "EREMA testrun LDPE 22.02.24"). Adds a LIJN 6 datapoint: ~1045 kg/h on testrun.
- **Q29:** Reinforces that these EREMA BluPort HMIs are **extruder/compactor line overviews** (EX1 + PCU), not wash SCADA. "3C" and "6" are both regranulation lines.
- **Correction note for 219:** `219_CeDo22` (same recipe, 864 h, same night 2-10-2024) was filed under "lijn3C" because its bottom label was dark/out-of-frame; given identical recipe + hours + session, **219 may actually be LIJN 6 too**. Flagged as uncertain in that digest's line attribution.
- **Q30/Q15:** consistent units and zone temps (EX1-IZ1 70 °C).
