# Lijn 3B flow diagram incl waterloops — 20-04-2023 (Cedo, official process flowchart)

- **Source file:** `264_CeDo134.pdf`
- **Type:** Photo of the printed Cedo flowchart in the ring binder. Title block bottom-right: **"Lijn 3b flow diagram / incl waterloops / 20-04-2023"** with the **cedo** logo (logo appears twice — sheet + binder cover peeking below). Blue-boxed nodes = water/pump/utility; tan-boxed nodes = material-path process equipment; thin arrows = flow.
- **HIGH VALUE:** The 3B sibling of `FLOW-lijn3a-flow-diagram__261_CeDo130.md`. Answers several open questions **differently from 3A** — notably 3B HAS a **Pomp zeefbocht** (Q6), uses a **Rafter** + **Ontwaterschroef van rafter** instead of the 3A Frictiewasser M1/M2, names **Frictiescheider 210**, and has **two mechanical dryers 310 & 311** plus a **Frictiescheider li/re** (left/right). Dated one day after the 3A sheet (3A = 19-04-2023, 3B = 20-04-2023).

## Node inventory (verbatim box text), grouped by row as drawn

### Top utility/water row (blue boxes)
- **Zandscheider** (*sand separator* — no "naar LA1" suffix here, just "Zandscheider")
- **LA1**
- **P1** (pump P1)

### Row A — infeed / wash / flotation train (tan, left→right)
1. **Vuilsnipper silo 3b** (*dirty-snippet/reject silo 3b*)
2. **Doseerschroef M11a** (*dosing screw M11a*)
3. **Rafter** (*[unsure: brand/type name of the wash unit — the 3B equivalent of the 3A "Frictiewasser (M1 en M2)"]*)
4. **Ontwaterschroef van rafter** (*dewatering screw of the rafter*)
5. **Frictiescheider 210** (*friction separator 210*)
6. **Intrekrol flotatie tank** (*draw-in roller, flotation tank*)
7. **flotatie tank**
8. **Uittrek rol flotatie tank** (*draw-out roller, flotation tank*)
9. **Ontwater schroef** (*dewatering screw*)

### Row B — drying / air-classify train (tan; flow runs right→left as drawn)
- **Ringventilator** (*ring fan*) ← **ventilator** ← **Thermische droger** (*thermal dryer*) ← **Verdeelwals** (*distribution roller*) ← **Ventilator** ← **Mechanische droger 310** and **Mechanische droger 311** (two mechanical dryers, stacked) ← **Frickischeider li/re** (*[unsure: "Frictiescheider li/re" = friction separator left/right]*)
- **Heater** (below Thermische droger)

### Bottom material row — extrusion / pelletize / finish (tan, left→right)
- **Extruder silo** → **Compactor band** → **Compactor** → **Extruder laserfilter vacuum** → **Kopfilter & heetafslag** → **Ontwaterzeef** → **Centrifuge** → **Weegschaal** → **MS / LS silo buiten**

### Bottom utility/water row (blue boxes)
- **Pomp was 3b** (*pump wash 3b*)
- **Blauwe tank** ← **ZSS**
- **Vers kanaalwater** (*fresh canal water*)
- **Pomp was 4**
- **Pomp zeefbocht** (*pump sieve-bend / wedge-wire screen pump*) — bottom-left, standalone
- **Blauwe vat** + **Pomp** (below it)
- **Tankje tussen extruders** + **Pomp** (below it)
- **Riool naar EOP** + **Koeltoren circuit**

## Key connections / routing observed (arrows)
- **Vuilsnipper silo 3b → Doseerschroef M11a → Rafter → Ontwaterschroef van rafter → Frictiescheider 210 → Intrekrol flotatie tank → flotatie tank → Uittrek rol flotatie tank → Ontwater schroef →** up to **Frickischeider li/re → Mechanische droger 310/311 → Ventilator → Verdeelwals → Thermische droger → ventilator → Ringventilator**, then down to **Extruder silo**.
- **Zandscheider / LA1 / P1** sit top-right, servicing the wash/flotation water circuit (P1 pumps, LA1 = wash basin/circuit, Zandscheider removes sand). Note: unlike 3A there is **no separate P2/LA2 pair drawn** — 3B shows a single **LA1 / P1 / Zandscheider** water head plus the **Pomp zeefbocht**.
- **Blauwe tank** fed by **ZSS** + **Vers kanaalwater**; **Pomp was 3b** and **Pomp was 4** draw from it.
- **Blauwe vat + Pomp** → extruder-laserfilter / kopfilter water.
- **Tankje tussen extruders + Pomp** and **Koeltoren circuit** → pelletize/cooling water; **Ontwaterzeef / Centrifuge** dewater; spent → **Riool naar EOP**.
- **Pomp zeefbocht** is a distinct bottom-left pump (the sieve-bend/screen recirculation pump) — PRESENT on 3B (absent on 3A).

## Open-question ANSWERS from this doc

- **Q6 (Pomp zeefbocht — which line?):** **CONFIRMED on lijn 3B.** A standalone blue node **"Pomp zeefbocht"** sits in the bottom-left utility cluster of the 3B diagram (it is NOT on the 3A sheet). So the **zeefbocht (sieve-bend / wedge-wire screen) recirculation pump is a 3B feature.** *Quote: box "Pomp zeefbocht".*
- **Q1 (ZSS):** Same as 3A — **ZSS** is a blue water node feeding the **Blauwe tank** (with **Vers kanaalwater**). Confirms ZSS is a plant-wide water-supply node present on both 3A and 3B. *Quote: box "ZSS" → "Blauwe tank".* (Acronym still not expanded; **[unsure of expansion]**.)
- **Q2 (block "C1"):** On 3B the equivalent front-end wash chain is **Rafter → Ontwaterschroef van rafter → Frictiescheider 210** — there is **no "C1" box on 3B**. So C1 is specific to the 3A layout (between Frictiewasser M1/M2 and Frictiescheider M3); 3B replaces that stretch with the Rafter + its dewater screw. Supports reading C1 as a line-3A-specific wash/buffer cell.
- **Q3 (M11a):** On 3B, **Doseerschroef M11a** appears once, front-end (Vuilsnipper silo 3b → M11a → Rafter). 3B does not draw a second M11a under a mengsilo (3B has no separate "Mengsilo/rondmengen" branch on this sheet). So the duplicate-M11a phenomenon is a **3A** feature; on 3B M11a is just the infeed dosing screw.
- **Q5 (water routing 3B):** ZSS + Vers kanaalwater → Blauwe tank → Pomp was 3b / Pomp was 4; **Zandscheider / LA1 / P1** = the wash-water circuit head; **Pomp zeefbocht** recirculates screen water; Blauwe vat + Pomp → laserfilter/kopfilter; Tankje tussen extruders + Pomp + Koeltoren circuit → pellet/cooling; spent → Riool naar EOP. (Title literally says **"incl waterloops"** — this is THE water-routing reference sheet for 3B.)
- **Q7 (Tankje tussen extruders):** **CONFIRMED present on 3B** with its own **Pomp**, in the pelletize/cooling cluster next to Koeltoren circuit / Riool naar EOP. One per line (3A and 3B each have one). *Quote: box "Tankje tussen extruders" + "Pomp".*
- **Q11 (LA1/LA2):** 3B shows **LA1** (with **Zandscheider** and **P1**) but **no LA2** on this sheet — consistent with LA1 = the (sand-separated) primary wash circuit. 3B apparently runs a single LA1 circuit head (+ Pomp zeefbocht) rather than the 3A dual LA1/LA2.
- **Q12 (EOP):** Same node **"Riool naar EOP"** present. Confirms EOP is the shared effluent/end-of-pipe destination on both lines. *Quote: box "Riool naar EOP".*
- **Q8 (bigbag station):** **NOT drawn on the 3B sheet** (3B has no bigbag-station / rondmengen branch, unlike 3A). So the bigbag station is a **3A** feature per these diagrams.

## 3A vs 3B equipment differences captured (for sim)
| Stage | Lijn 3A (261) | Lijn 3B (264) |
|---|---|---|
| Wash unit | Frictiewasser (M1 en M2) + **C1** | **Rafter** + **Ontwaterschroef van rafter** |
| Friction sep (main) | Frictiescheider **M3** | Frictiescheider **210** |
| Friction sep (dryer side) | Frictiescheider **M4** | **Frickischeider li/re** |
| Mechanical dryer | Mechanische droger **M8** | Mechanische droger **310** + **311** (two) |
| Water circuits | **LA1 + LA2** (P1, P2) | **LA1** (P1) + **Pomp zeefbocht** |
| Mengsilo / rondmengen / bigbag | present (M11b, m14, V1 rondmengen, bigbag station) | **not on this sheet** |
| Shared both | Doseerschroef M11a, Intrek/Uittrek rol flotatie tank, flotatie tank, Ontwaterschroef, Thermische droger, Verdeelwals, Ventilator/Ringventilator, Heater, Extruder silo→Compactor band→Compactor→Extruder laserfilter vacuum→Kopfilter & heetafslag→Ontwaterzeef→Centrifuge→Weegschaal→MS/LS silo buiten, Blauwe tank←ZSS, Vers kanaalwater, Pomp was 4, Blauwe vat+Pomp, Tankje tussen extruders+Pomp, Riool naar EOP, Koeltoren circuit | — |

## Additional vocabulary captured
Rafter, Ontwaterschroef van rafter, Frictiescheider 210, Frickischeider li/re, Mechanische droger 310, Mechanische droger 311, Ringventilator, Pomp zeefbocht, Pomp was 3b.
