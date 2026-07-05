# Guide page — HDFP werkingsprincipe + Snijproces (hot-die-face pelletizing principle / cutting process)

- **Source file:** `349_CeDo79.pdf`
- **Type:** Training/manual page (EREMA pelletizer). Mixed NL text + EN diagram labels. No SWI header, no id, no date. Held in a ring binder (punch holes visible). Green edge band (deck styling).
- **Companions:** `EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md`, `EREMA-korrels-matrijsplaat__167_CeDo80.md`, `pelletiseer-waterbassin-trilnaald__063_CeDo86.md`, `TRAIN-koelingsproces-korrels-slot__309_CeDo87.md`, `messen-matrijsplaat-slijtage__066_CeDo82.md`.

## Section 1 — "HDFP werkingsprincipe" *(HDFP working principle)*
**HDFP = Hot Die Face Pelletizing** (heetafslag / hot die-face pelletizing).

Body text (verbatim NL):
> "Het materiaal wordt gepelletiseerd terwijl het nog gesmolten is. Het kan nog een beetje vervormen voor het bevriezen."
*(The material is pelletized while it is still molten. It can still deform a little before it freezes/solidifies.)*

Red **(!)** caution icon at left.

### Labelled cross-section diagram (EN labels, verbatim)
A sectioned pelletizer head assembly. Callouts, left→right / top→bottom:
- **supply piece** *(supply/inlet piece — the melt feed)*
- **nozzle stock** *(die/nozzle body — matrijs)*
- **knife head** *(mes-kop — the rotating cutter head)*
- **housing**
- **motor** (far right, drives the shaft)
- **Lagergehäuse / bearing housing** *(German+EN: bearing housing)*
- **Exzenter / eccentric tappet** *(German "Exzenter" = eccentric; eccentric tappet)* [unsure: "excenter/eccentric"]
- **Bearing flansh** *(bearing flange, sic "flansh")*
- **water supply** (bottom-left, feeding the die face)
- **Pellet transport hose** (bottom-right, carries pellets away in water)

Interpretation: melt enters via the **supply piece**, is pushed through the **nozzle stock / die (matrijs)**, and the **knife head** (driven by the **motor** through an **eccentric** and **bearings**) shears the strands at the die face. **Water supply** cools/quenches at the face and the **pellet transport hose** carries the pellets away — a classic wet hot-die-face pelletizer.

## Section 2 — "Snijproces" *(cutting process)*
Body text (verbatim NL):
> "Een snijkant glijdt langs een vaste rand of matrijs en snijdt het materiaal af. Scherpte en geleidingsprecisie bepalen de kwaliteit van het resultaat."
*(A cutting edge slides along a fixed edge or die and shears off the material. Sharpness and guiding precision determine the quality of the result.)*

Photo: close-up of a **knife blade / cutting edge** (a long tapered steel blade) resting on a surface — illustrating the snijkant (cutting edge) whose sharpness matters.

## Answers to open questions
- **Q24 (densities):** none.
- No numbered-question answers, but this is the **canonical HDFP (heetafslag) principle reference**: molten pellets cut at the die face by a knife head, quenched by water, transported by hose. Names the assembly parts (supply piece, nozzle stock/die, knife head, housing, motor, bearing housing, eccentric tappet, bearing flange, water supply, pellet transport hose). Ties to Q15 (why melt stays hot through the die/laserfilter chain) and to the knife-wear docs.

## Notes for sim
- Confirms pelletizing = **hot die-face** (heetafslag): pellets are cut while still molten and can slightly deform before freezing in water. Knife **sharpness + guiding precision = pellet quality** → a dull/misaligned knife should degrade pellet quality in-sim (links to the "no gap on measuring table" acceptance check in CeDo83).
- Water supply at die face + pellet transport hose feeds the downstream ontwaterzeef / centrifuge water loop (cf. training centrifuge/ontwaterzeef docs).
