# Cedo-PROD-SWI-074 — Laserfilter wissel LF 2 - 406

- **Source file:** `296_CeDo139.pdf` (1 page scan of a CeDo work-instruction sheet)
- **SWI id:** `Cedo-PROD-SWI-074`
- **Title:** `Laserfilter wissel LF 2 - 406` (Laserfilter change, unit LF2, equipment tag 406)
- **Rev No:** 01
- **Issue Date:** 26-07-2023
- **Author:** Lean Practitioner
- **Approved By:** Prod manager
- **Doc class:** PROD D... (PROD Document, header cut at right edge)
- **Note:** This is page 1 (the "Benodigdheden" / required tools & materials step). The step-table continues on further pages not present in this single-page scan.

## Legend (pictogram key, bottom of sheet)
| Icon | Meaning |
|---|---|
| ✋ (hand) | Functie (function / manual action) |
| 🔔 (bell) | Geluid (sound) |
| 👁 (eye) | Zicht (sight / visual check) |
| ➕ (red cross) | LET OP: Veiligheid (CAUTION: Safety) |
| ◆ (green diamond) | LET OP: Kwaliteit (CAUTION: Quality) |
| ● (blue dot) | TIP |

## Column headers (step table)
`Nr | Titel handeling | Let op | Omschrijving handeling | Ondersteunende foto`
(Nr | action title | attention/icons | action description | supporting photo)

## Step 1 — VERBATIM

**Nr:** 1
**Titel handeling:** `Benodigdheden` (required items / tools)
**Let op (icons):** ✋ Functie · 👁 Zicht · ℹ️ info
**Omschrijving handeling** — full checklist of tools/materials, verbatim:
- `- dop 36` (socket 36)
- `- dop 46` (socket 46)
- `- Bordes` (work platform / gantry)
- `- koevoet` (crowbar / pry bar)
- `- koperen ring` (copper ring)
- `- zegering tang` (circlip / snap-ring pliers)
- `- Spuitbus kopervet` (copper-grease spray can)
- `- verloopstuk tacker` (adapter for the tacker)
- `- tacker / luchthamer` (tacker / air hammer)
- `- ring-steeksleutel 13` (combination spanner 13)
- `- plamuurmessen 2 x` (2 putty knives / scrapers)
- `- schroevendraaier plat` (flat screwdriver)
- `- grootte kunststof hamer` (large plastic/dead-blow hammer)
- `- 2 luchthamers los / vast` (2 air hammers, loose / fixed)
- `- leeg boutenrek voor 42 stuks` (empty bolt rack for 42 pieces)
- `- koperen ring voor in schraper` (copper ring for in the scraper)
- `- hitte bestendige handschoenen` (heat-resistant gloves)
- `- beschermings mouwen voor arm` (protective sleeves for arm)
- `- momentsleutel al ingesteld op 500Nm` (torque wrench preset to 500 Nm)
- `- 42 schone bouten en een leegboutenrek` (42 clean bolts and an empty bolt rack)
- `- 2 spindels om afvoer vijzels te demonteren` (2 spindles to dismount the discharge augers/screws)
- `- elektronische momentsleutel met volle accu` (electronic torque wrench with full battery)
- `- buis om over de stang te plaatsen bij openen deur` (tube to place over the rod when opening the door)
- `- buis om de ruimte in deuropening schoon te kunnen maken` (tube to clean out the space in the door opening)

## Supporting photo + highlighted note box (VERBATIM)
Photo: green **BOLL `MIEDŹ W SPRAYU`** spray can (copper spray / kopervet).
Highlighted (yellow) note text:
- `Invetten van schroefdraad en overgang vijzels op aandrijving kopervet spuitbus gebruiken.` (Grease the thread and the auger-to-drive transition using the copper-grease spray can.)
- `Kopervet hoeft er maar lichtjes opgespoten te worden niet teve[el]` (Copper grease only needs to be sprayed on lightly, not too much.) [right edge cut]
- `Dit kan de dienst voorafgaand aan de laserwissel al uitvoeren` (The shift can already do this prior to the laser[filter] change:)
  - `- 2 afvoervijzels` (2 discharge augers)
  - `- 2 spindels`
  - `- 42 bouten` (42 bolts)

## Answers to open questions
- **Q15 (laserfilter changeover):** DIRECT HIT. This is the formal **laserfilter-wissel** procedure for **LF2 (tag 406)** on the plant. Key modeled facts:
  - The laserfilter is bolted with **42 bolts** (an "empty bolt rack for 42 pieces" + "42 clean bolts"), torqued to **500 Nm** (`momentsleutel al ingesteld op 500Nm`). → filter-housing has a 42-bolt flange, 500 Nm spec.
  - Requires sockets **dop 36** and **dop 46**, air hammers, crowbar, heat-resistant gloves + arm sleeves (hot melt/steel work).
  - **2 afvoervijzels** (discharge augers/screws) and **2 spindels** are demounted — corroborates the corrugated-bottom/auger discharge that ejects contaminant "lumps." The laserfilter self-cleans by scraping retentate to discharge augers.
  - Copper grease (kopervet, BOLL Miedź) on threads + auger-to-drive transition.
  - Prep can be done by the shift ahead of the wissel (grease 2 afvoervijzels, 2 spindels, 42 bouten).
- **Q30:** Torque spec surfaced: **500 Nm** on the 42 laserfilter bolts.
- Ties to memory note [Laser filter (Britas-style melt filter)] — the "lumps" discharge is via these **afvoervijzels** (discharge augers), not a passive hose; the SWI confirms augers + spindles hardware.

## Notes for sim
- Laserfilter maintenance mini-game / event: open door (tube over rod), remove 42 bolts (dop 36/46, 500 Nm), demount 2 afvoervijzels + 2 spindels, scrape door opening clean, re-grease with kopervet, reinstall with 42 clean bolts at 500 Nm. Heat-resistant PPE required (hot work).
- Tag numbering: **LF2 = 406**. Implies **LF1** exists (separate laserfilter). Two laserfilters in the plant.
