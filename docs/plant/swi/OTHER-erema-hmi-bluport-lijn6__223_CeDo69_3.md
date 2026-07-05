# EREMA BluPort HMI screenshot — LIJN 6 overview (PRODUCTION recipe, 12-3-2025)

- **Source file:** `223_CeDo69 (3).pdf` (single page, 5.3 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI main overview (same screen design as 219-222).
- **SWI id:** none
- **Line:** **LIJN 6** — blue engraved bottom label clearly reads **"LIJN 6"**.
- **Note:** **Different recipe and much later date than the other LIJN 6 photos.** This is a real **production** run in **March 2025**, not the Oct 2024 "testrun". Best/clearest LIJN 6 overview of the set (well-lit, mimic fully legible).

## Physical signage (above the panel)
- Top-left laminated sticker (same as seen on 222): **"...ouden er settings gewijzigd worden / ...eer dit met shiftleader en mail naar CI"** [best reading]. Gloss: "...if settings are changed / ...communicate this with shiftleader and mail to CI." (CI = Continuous Improvement [likely].) Confirms 222 and 223 are the **same physical LIJN 6 panel** (same taped note).
- Yellow warning label top-centre: **"!!! ..AAN.. !!!"** [unsure] — a yellow "AAN" (ON) caution tag on the panel frame.

## Header
- **Rx  1-14-25 production program rke** — recipe name = **"1-14-25 production program rke"** (a dated production program; "rke" likely operator initials or a grade code). This is a **production** recipe, distinct from the "EREMA testrun LDPE 22.02.24" recipe in 219-222.
- Clock: **2:40:26 / 12-3-2025**.
- **BluPort  EREMA** logos top-right.

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 111 | °C |
| power | 214,4 | kW |
| rpm | 110 | rpm |
| % | 55 | % |
| hours | 3554 | h |
| diamond pressure | 269 | bar |
| square pressure | 19 | bar |
| diamond pressure | 172 | bar |
| output | 1185 | kg/h |

(Operating hours **3554 h** in Mar 2025 vs **864-869 h** on this same LIJN 6 in Oct 2024 → ~2690 running hours added over ~5 months. Interesting: LIJN 3C read **3553-3554 h** in Dec 2024 (206-210); LIJN 6 reaches 3554 h only by Mar 2025 — the two lines have similar total run-hours but 6 lags 3C by a few months, consistent with 6 being commissioned/ramped slightly later.)

## Trend graph
- Left Y **0–600** (kW): red/orange **PCU-vermogen** ~200-260 (oscillating), well below the 600 ceiling. Right Y **0–250**: green **PCU-temperatuur 1** flat ~230-250, yellow **AIS-positie** flat ~100.
- X-axis: **2:23:46 → 2:27:56 → 2:32:06 → 2:36:15 → 2:40:25** (all 12-3-2025).
- Legend (verbatim): **Toevoer actief** (cyan, dense square-wave pulses = feed cycling) | **PCU – vermogen** (orange/red) | **PCU – temperatuur 1** (green) | **AIS – positie** (yellow).

## Right buttons / mimic (all clearly legible this frame)
- **AutoPro-control → Uit** (OFF)
- **PCU-vulpeil: 179 cm**
- **PES-toerental: 80 %** | **TEU-toerental: 30 %**
- **PCU-belasting: 68 %** | **PCU-vermogen: 214,4 kW**

## Bottom mimic call-outs (fully legible)
- **BC1-toerental: 0 %**
- **EX1-vermogen: 195,1 kW**
- **AIS-positie: 100 %** (melt filter fully advanced / screen position at max)
- **PCU-temp. 1: 111 °C**
- **EX1-toerental: 110 rpm**
- **EX1-belasting: 55 %**
- **EX1-IZ1: 92 °C** [unsure — small, reads ~92 °C]

## Q&A hits
- **Q26/Q2 (which lines exist / floorplan):** Definitive, well-lit confirmation of **LIJN 6** as a full EREMA BluPort regranulation line running a real **production program** ("1-14-25 production program rke") in Mar 2025 — not just a one-off testrun. So LIJN 3C **and** LIJN 6 are both in production service; identical HMI, distinguished only by the engraved blue bottom label.
- **Q9 (throughput):** LIJN 6 **production** output **1185 kg/h** (recipe "1-14-25 production program rke", 12-3-2025). This lands right in the LIJN 3C production band (1342-1444 kg/h Dec 2024 was a bit higher; 1185 kg/h here is a solid production figure and well above the 923-1115 kg/h Oct testrun). Both lines operate around ~1.1–1.45 t/h.
- **Q15/Q30:** melt **111 °C**, EX1-IZ1 **~92 °C**; AIS-positie can reach **100 %**; PCU-vulpeil 179 cm; units consistent throughout (kW + % load, rpm + %, cm, bar, kg/h).
- **Q29:** Reconfirms the EREMA BluPort HMIs are **extruder + PCU (compactor) line overviews**, not wash-line SCADA. LIJN 6 here shows EX1 (extruder) + PCU (Plast Compactor Unit) live tags exactly like LIJN 3C.
- **Operating-hours cross-check:** LIJN 6 = 3554 h (Mar 2025) vs LIJN 3C = 3553-3554 h (Dec 2024). Same taped shiftleader/CI note on 222 & 223 confirms both are the one LIJN 6 panel.
