# Lijn 3A flow diagram — 19-04-2023 (Cedo, official process flowchart)

- **Source file:** `261_CeDo130.pdf`
- **Type:** Photo of a printed Cedo flowchart in a ring binder. Title block bottom-right: **"Lijn 3a flow diagram / 19-04-2023"** with the **cedo** logo. Blue-boxed nodes = water/pump/utility; tan-boxed nodes = material-path process equipment. Arrows = flow direction.
- **HIGH VALUE:** This single diagram answers a large fraction of the open questions (Q1, Q2, Q3, Q5, Q6, Q7, Q8, Q11, Q12). Companion to the existing lijn-1 (`FLOW-lijn1-flow-diagram__239_CeDo125.md`) and lijn-3B (`FLOW-lijn3b-...`) diagrams.

## Node inventory (verbatim box text), grouped by row as drawn

### Top utility/water row (blue boxes)
- **P1** (pump P1)
- **Zandscheider naar LA1** (*sand separator to LA1*)
- **P2** (pump P2)
- **LA2**

### Row A — wash/friction/flotation train (tan, left→right)
1. **Vuilsnipper silo 3a** (*dirty-snippet/reject silo 3a*)
2. **Doseerschroef M11a** (*dosing screw M11a*)
3. **Frictiewasser (M1 en M2)** (*friction washer, motors M1 and M2*)
4. **C1**
5. **Frictiescheider M3** (*friction separator M3*)
6. **Intrekrol flotatie tank** (*draw-in roller, flotation tank*)
7. **Flotatie tank**
8. **Uittrek rol flotatie tank** (*draw-out roller, flotation tank*)
9. **Ontwater schroef flotatie tank** (*dewatering screw, flotation tank*)

### Row B — drying / air-classify / mixing train (tan, left→right as drawn; note flow runs right→left here)
- **Ventilator V2a** ← **Cycloon & windzifter** (*cyclone & air classifier*) ← **ringleiding** (*ring line/loop duct*) ← **Ventilator V2** ← **Doseerschroef M11b** ← **Mengsilo** (*mix silo*) ← **Ventilator V4** ← **Mechanische droger M8 + intrek schroef** (*mechanical dryer M8 + infeed screw*) ← **Frictiescheider M4**
- **Heaters** (feeds Doseerschroef M11b area)

### Row C — thermal-dryer branch (left column, tan)
- **Verdeelwals thermische droger** (*distribution roller, thermal dryer*)
- **Thermische droger** (*thermal dryer*) + **Heaters**
- **Cycloon -> ventilator V3**
- (feeds down to) **Extruder silo**

### Row C-right — mengsilo dosing / rondmengen branch
- **Doseerschroef M11a** (second occurrence — under Mengsilo) 
- **Verdeelwals (m14)** (*distribution roller m14*)
- **Ventilator V1 rondmengen** (*fan V1, recirculation mixing*) + **Heaters**
- **bigbag station**

### Bottom material row — extrusion / pelletize / finish (tan, left→right)
- **Extruder silo** → **Compactor band** → **Compactor** → **Extruder laserfilter vacuum** → **Kopfilter & heetafslag** (*die-head filter & hot-face cut / heetafslag = hot die-face pelletizing*) → **Ontwaterzeef** (*dewatering screen*) → **Centrifuge** → **Weegschaal** (*weigh scale*) → **MS / LS silo buiten** (*MS/LS silo outside*)

### Bottom utility/water row (blue boxes)
- **Pomp was 3a** (*pump wash 3a*)
- **Blauwe tank** (*blue tank*) ← **ZSS**
- **Vers kanaalwater** (*fresh canal water*)
- **Pomp was 4** (*pump wash 4*)
- **Blauwe vat** (*blue vat/drum*) + **Pomp** (below it)
- **Tankje tussen extruders** (*small tank between extruders*) + **Pomp** (below it)
- **Riool naar EOP** (*sewer to EOP*) + **Koeltoren circuit** (*cooling-tower circuit*)

## Key connections / routing observed (arrows)
- **Vuilsnipper silo 3a → Doseerschroef M11a → Frictiewasser (M1 en M2) → C1 → Frictiescheider M3 → Intrekrol flotatie tank → Flotatie tank → Uittrek rol → Ontwaterschroef flotatie tank →** (up to) **Frictiescheider M4 → Mechanische droger M8 + intrek schroef → Ventilator V4 → Mengsilo**.
- **P1** and **Zandscheider naar LA1** sit above the Frictiewasser/C1/M3 area (water for the first wash circuit → sand separator → **LA1**).
- **P2** and **LA2** sit above the Flotatie-tank / Ontwaterschroef area (second water circuit → **LA2**).
- **Mengsilo** branches two ways: (a) up-left via **Doseerschroef M11b → Ventilator V2 → ringleiding → Cycloon & windzifter → Ventilator V2a → Verdeelwals thermische droger → Thermische droger → Cycloon→ventilator V3 → Extruder silo**; (b) down via **Doseerschroef M11a (2nd) → Verdeelwals (m14) → Ventilator V1 rondmengen** (recirculation) and to **bigbag station**.
- Extrusion chain bottom row feeds **MS / LS silo buiten**.
- **Ontwaterzeef → Centrifuge**; the **Tankje tussen extruders** + **Pomp** and **Koeltoren circuit** service the pelletize/cooling water; overflow/spent → **Riool naar EOP**.
- **Blauwe tank** is fed by **ZSS** and **Vers kanaalwater**; **Pomp was 3a** and **Pomp was 4** draw from it. **Blauwe vat** has its own **Pomp** feeding the extruder-laserfilter-vacuum / kopfilter water.

## Open-question ANSWERS from this doc

- **Q1 (ZSS meaning/location):** **ZSS** is a blue (water) node in the bottom utility row, feeding the **Blauwe tank** (alongside **Vers kanaalwater**). So ZSS = a water source/tank that supplies the blue tank on lijn 3A. Location: bottom-left utility cluster, next to Blauwe tank / Vers kanaalwater / Pomp was 3a / Pomp was 4. (Meaning of the acronym still not spelled out in the doc; functionally it is a process-water supply feeding Blauwe tank — likely "Zuiver/Zand Spoel Systeem" or a water buffer; **[unsure of expansion]**.) *Quote: box "ZSS" → arrow into "Blauwe tank".*
- **Q2 (block C1 on lijn 3A between Frictiewasser M1/M2 and Frictiescheider M3):** **CONFIRMED.** The chain is literally **Frictiewasser (M1 en M2) → C1 → Frictiescheider M3**. C1 sits between them. (C1 = a labeled process block/vessel there; the diagram does not expand what C1 stands for — likely a wash/buffer cell or conveyor, **[unsure]**.) *Quote: "Frictiewasser (M1 en M2)" — "C1" — "Frictiescheider M3".*
- **Q3 (M11a shared by Mengsilo dosing screw AND infeed screw?):** **Doseerschroef M11a appears TWICE** on this diagram: (1) top row, feeding the Frictiewasser from Vuilsnipper silo 3a; (2) under the Mengsilo, feeding Verdeelwals (m14). Both are labeled "M11a." So the **same tag M11a is used for two dosing screws** — the front-end vuilsnipper dosing screw and the Mengsilo dosing screw. This supports the "shared/duplicated M11a" reading — either a labeling reuse or genuinely one motor tag spanning both. *Quote: two separate boxes both "Doseerschroef M11a".* (Note: M11b is the distinct one between Mengsilo and Ventilator V2.)
- **Q5 (water routing):** Strong answers for lijn 3A —
  - **ZSS + Vers kanaalwater → Blauwe tank → Pomp was 3a / Pomp was 4** (wash-water supply loop).
  - **Zandscheider → LA1** (first circuit), **P2 → LA2** (second circuit): P1/P2 are the circulation pumps, LA1/LA2 the two wash-water circuits/basins.
  - **Blauwe vat + Pomp →** extruder laserfilter vacuum / kopfilter water.
  - **Tankje tussen extruders + Pomp** and **Koeltoren circuit** → pelletizing/cooling water; **Ontwaterzeef/Centrifuge** dewater; spent → **Riool naar EOP**.
- **Q6 (Pomp zeefbocht):** Not present on lijn-3A diagram by that exact name (the dewatering here is **Ontwaterzeef → Centrifuge**, and **Ontwaterschroef flotatie tank**). "Zeefbocht" pump not on this sheet.
- **Q7 (Tankje tussen extruders — between which, shared?):** **CONFIRMED present** as a blue node with its own **Pomp**, in the pelletize/cooling water cluster on lijn 3A. It sits with the Ontwaterzeef/Centrifuge/Koeltoren group — i.e. the pellet-water tank serving the extruder(s) on this line. The diagram places one "Tankje tussen extruders" per line (here 3A). *Quote: box "Tankje tussen extruders" with "Pomp" below.*
- **Q8 (lijn 3B bigbag station):** This is the **lijn 3A** diagram and it DOES show a **"bigbag station"** node (near Ventilator V1 rondmengen / Mengsilo output). So a bigbag station exists on 3A too. *Quote: box "bigbag station".*
- **Q11 (LA1/LA2 meaning):** Both appear as top-row water nodes: **"Zandscheider naar LA1"** and **"LA2"**, fed by **P1** and **P2** respectively. LA1/LA2 = the two wash-water circuits/basins (LA = likely "Loog-/Lut-... " no — more plausibly the two wash flotation/circulation basins on the line). Functionally: **LA1 = first (sand-separated) wash circuit, LA2 = second wash circuit**, each with its own pump (P1, P2). (Acronym not expanded here; consistent with existing `TRAIN-water-circuit-1-La1-was3a` and `TRAIN-water-circuit-2-La2-was3a` docs — LA1/LA2 are wash circuits.)
- **Q12 (EOP meaning):** Node **"Riool naar EOP"** (*sewer to EOP*) — EOP is the effluent/end-of-pipe destination the sewer routes to. Confirms drains/spent water → Riool → **EOP** (end-of-pipe / effluent treatment plant). Acronym still not spelled out. *Quote: box "Riool naar EOP".*

## Additional equipment vocabulary captured (for sim)
Vuilsnipper silo, Doseerschroef (M11a/M11b), Frictiewasser (M1/M2), C1, Frictiescheider (M3/M4), Intrekrol/Uittrekrol flotatie tank, Flotatie tank, Ontwaterschroef flotatie tank, Mechanische droger M8, Ventilator V1/V2/V2a/V3/V4, Cycloon & windzifter, ringleiding, Mengsilo, Verdeelwals (thermische droger / m14), Thermische droger, Heaters, Ventilator V1 rondmengen, bigbag station, Extruder silo, Compactor band, Compactor, Extruder laserfilter vacuum, Kopfilter & heetafslag, Ontwaterzeef, Centrifuge, Weegschaal, MS/LS silo buiten, Pomp was 3a/4, Blauwe tank, ZSS, Vers kanaalwater, Blauwe vat, Tankje tussen extruders, Riool naar EOP, Koeltoren circuit.
