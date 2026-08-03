# EREMA BluPort HMI screenshot — LIJN 6 overview (testrun recipe, 2-10-2024, 4th/last capture)

- **Source file:** `222_CeDo26 (3).pdf` (single page, 2.9 MB photo)
- **Doc type:** Photograph of EREMA BluPort HMI main overview (identical screen to 219/220/221).
- **SWI id:** none
- **Line:** **LIJN 6** — blue engraved bottom label clearly reads **"LIJN 6"**.
- **Note:** Same session/recipe as 219/220/221. Clock **5:02:54 / 2-10-2024** — the **latest** capture of the LIJN 6 testrun night. Full sequence: **219 (0:08:20, 864 h) → 221 (2:02:29, 866 h) → 220 (4:01:31, 868 h) → 222 (5:02:54, 869 h)**. Monotonic clock + hours across all four confirms one continuous LIJN 6 testrun the night of 1-2 Oct 2024, and strengthens that **219 is also LIJN 6**.

## Physical signage (top-left, partly legible)
- Dim label/note top-left: **"...ouden er settings gewijzigd worden / ...municeer dit met shiftleader en mail naar CI"** [unsure — best reading]. English gloss: "...if settings are changed / ...communicate this with shiftleader and mail to CI." A laminated operator instruction sticker taped above the HMI. ("CI" = Continuous Improvement dept [likely].)
- Top-right bezel shows the engraved **"ERE..."** (EREMA) machine wordmark.

## Header
- **Rx  EREMA testrun LDPE 22.02.24**
- Clock: **5:02:54 / 2-10-2024**
- **BluPort  EREMA** logos top-right.

## Left-column live values
| Pictogram | Value | Unit |
|---|---|---|
| temp | 94 | °C |
| power | 152,1 | kW |
| rpm | 90 | rpm |
| % | 44 | % |
| hours | 869 | h |
| diamond pressure | 248 | bar |
| square pressure | 21 | bar |
| diamond pressure | 98 | bar |
| output | 923 | kg/h |

(Melt **94 °C**, power **152,1 kW**, output **923 kg/h** — lowest of the four LIJN 6 captures, i.e. the run is winding down / lower feed at 5:02 vs the 1045-1115 kg/h earlier in the night. Hours **869 h**, next after 220's 868 h.)

## Trend graph
- Left Y 0–600 (kW), right Y 0–250. Green **PCU-temperatuur 1** flat ~230-250, red/orange **PCU-vermogen** ~150 (mild oscillation), yellow **AIS-positie** flat ~50-75, cyan **Toevoer actief** square-wave (feed pulses).
- X-axis: **4:46:15 → 4:50:25 → 4:54:34 → 4:58:44 → 5:02:54** (all 2-10-2024).
- Legend (bottom, verbatim): **Toevoer actief** (cyan) | **PCU – vermogen** (orange/red) | **PCU – temperatuur 1** (green) | **AIS – positie** (yellow).

## Right buttons / mimic
- **AutoPro-control → Uit** (OFF)
- **PCU-vulpeil: 244 cm** (boxed field top-right of mimic) — much higher fill than 220/221's ~101-105 cm; compactor filled up as feed slowed.
- **PES-toerental: 80 %** [unsure — partly behind overlay] | **TEU-toerental: 22 %**
- **PCU-belasting: 48 %** | **PCU-vermogen: 152,1 kW**

## Bottom mimic call-outs (partly obscured by glare/overlay)
- **BC1-toerental: 80 %** [unsure]
- **EX1-vermogen: 152,1 kW** [unsure — matches PCU-vermogen readout]
- **AIS-positie: 48 %** [unsure]
- **EX1-toerental: 90 rpm**
- **EX1-belasting: 44 %**
- (EX1-IZ1 / PCU-temp fields not clearly legible in this frame — mimic lower half washed out by reflection.)

## Q&A hits
- **Q26/Q2:** Fourth confirmation of **LIJN 6** as a distinct EREMA BluPort regranulation line. Completes the four-capture testrun sequence (219→221→220→222) all on LIJN 6 the night of 2-10-2024.
- **Q9 (throughput):** LIJN 6 testrun output here **923 kg/h** (run winding down). Full LIJN 6 testrun band across the night: **923 / 1045 / 1102 / 1115 kg/h** (222/220/221/219) — i.e. ~920–1115 kg/h on the "EREMA testrun LDPE 22.02.24" recipe.
- **Q15/Q30:** melt **94 °C** here (lower as run winds down); units consistent (kW + %, rpm + %, vulpeil cm, bar, kg/h).
- **Q29:** EREMA extruder/compactor overview, not wash SCADA.
- **Operator-note finding:** the taped instruction "if settings are changed, communicate with shiftleader and mail to CI" documents a real CeDo change-control practice around this HMI — useful colour for the sim's shift/handover mechanics.
