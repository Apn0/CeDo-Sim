# FLOW — Lijn 1 flow diagram (process block diagram)

- **Source file:** `239_CeDo125.pdf`
- **Doc id:** none (titled block diagram, not an SWI)
- **Title:** "Lijn 1 flow diagram"
- **Date:** 11-04-2023
- **Publisher:** CeDo (logo bottom-right)
- **Type:** process flow / block diagram of recycling **Line 1** (single page, printed on white sheet in a binder)
- **Scope:** full material path of Lijn 1 from metal-detection intake through wash/dry/float to extrusion, laserfilter, pelletizing and storage silo.

## Full block sequence (verbatim box labels, in flow order)

The diagram flows across four horizontal bands, snaking left→right then dropping to the next band. Boxes transcribed exactly (Dutch), with English gloss.

### Band 1 (top, intake + coarse separation) — left → right
1. **Metaal detectie band** — metal-detection belt (intake)
2. **Opzetband (Westa)** — feed/incline belt, brand "Westa"
3. **Band 1 onder shredder** — belt 1 under the shredder
4. **Magneetband (boven band 1)** — magnet belt (above belt 1) — ferrous removal
5. **Band 2 (naar voorwas trommel)** — belt 2 (to the pre-wash drum / voorwas trommel)
6. **Band 2 (naar HPS/SGA)** — belt 2 (to HPS/SGA)
7. **HPS (SGA) zware delen scheider** — HPS (SGA) heavy-parts separator ("zware delen scheider" = heavy-fraction separator)

### Band 2 (friction wash + mill + flotation) — flows right → left back under band 1
8. **Frictiescheider 6a** — friction separator 6a  ← (fed from HPS/SGA)
9. **Frictiescheider 6b** — friction separator 6b
10. **Mechanische droger 7a** — mechanical dryer 7a (fed from 6a)
11. **Mechanische droger 7b** — mechanical dryer 7b (fed from 6b)
12. **Ventilator 8a** — fan/blower 8a (from dryer 7a)
13. **Ventilator 8b** — fan/blower 8b (from dryer 7b)
14. **Maalmolen 1** — mill/granulator 1 (8a + 8b converge here)
15. **Ventilator 10a** — fan 10a (from maalmolen)
16. **Ventilator 10b** — fan 10b
17. **Intrekschroef 11a** — pull-in / infeed screw 11a (from ventilator 10a)
18. **Intrekschroef 11b** — pull-in / infeed screw 11b (from ventilator 10b)
19. **Flotatie tank** — flotation tank (both intrekschroeven feed it)

### Band 3 (flotation discharge → MAS drying line, two parallel trains) — left → right
20. **Uittrekschroef flotatie tank** — pull-out screw of the flotation tank
21. **Frictiescheider links rechts** — friction separator "left right" (splits to two parallel trains)
22. **Kufferath 1** / **Kufferath 2** — Kufferath screens/sieves 1 & 2 (brand "Kufferath", parallel a/b trains)
23. **MAS buffer 1** / **MAS buffer 2** — MAS buffer 1 & 2
24. **MAS droger 1** / **MAS droger 2** — MAS dryer 1 & 2
25. **Transport ventilator 1 (Deltoid)** / **Transport ventilator 2 (Deltoid)** — transport fan/blower 1 & 2, brand "Deltoid"
26. → both trains converge into **Extruder silo** (right edge)

### Band 4 (bottom, extrusion + pelletize + storage) — right → left
27. **Extruder silo** — buffer silo feeding the extruder
28. **Compactor band** — compactor feed belt
29. **Compactor** — compactor (PCU preconditioning unit)
30. **Extruder incl laserfilter, vacuum en matrijs** — extruder including **laserfilter, vacuum degassing and die/matrijs**
31. **Ontwaterzeef** — dewatering sieve (de-watering screen for the pellet/water slurry after die-face cut)
32. **Centrifuge** — centrifuge (pellet drying)
33. **Weegschaal** — weigh scale
34. **Voorraad silo buiten (MS/LS)** — outdoor storage silo (MS/LS grades) — final product storage

## Process narrative (derived)
Intake film → metal detection → shred → magnetic (ferrous) removal → pre-wash drum → HPS/SGA heavy-parts sink-float separation → dual friction washers (6a/6b) → mechanical dryers (7a/7b) → blowers → **maalmolen (mill)** → blowers → infeed screws → **flotation tank** (sink-float: PE floats, contaminants sink) → pull-out screw → friction separator splitting into two parallel **Kufferath → MAS buffer → MAS dryer → Deltoid transport-fan** trains → **extruder silo** → compactor (PCU) → **extruder w/ laserfilter + vacuum + die** → dewatering sieve → centrifuge → weigh scale → outdoor MS/LS storage silo.

## Answers to open questions
- **Q (line topology / equipment order for Lijn 1):** Full ordered equipment list transcribed above (34 blocks). This is the authoritative process order for Line 1.
- **Q4 (laserfilter placement):** Confirmed the **laserfilter sits at the extruder** — box 30 "Extruder incl laserfilter, vacuum en matrijs" — i.e. the melt filter is inline between extruder screw and die (matrijs), with vacuum degassing. Downstream is die-face pelletizing → **ontwaterzeef** (dewatering sieve) → **centrifuge** → weigh scale → storage. This locates the laserfilter in the melt stream (relevant to laser_filter project geometry).
- **Q6 / pump-zeefbocht:** not explicitly a box; flotation & wash circuits use screws (intrek/uittrekschroef) not a named "zeefbocht" on this diagram.
- **Q (dryer stages):** Line 1 has BOTH a **mechanische droger (7a/7b)** stage after friction washing AND a **MAS droger (1/2)** stage before the extruder silo — two distinct drying stages plus a final **centrifuge** on the pellet side.
- **Q (brands seen):** Westa (feed belt), Kufferath (screens), Deltoid (transport fans), MAS (buffer/dryer). Useful for asset naming in the sim.
- **Sink/float principle:** two sink-float stages — **HPS (SGA) heavy-parts separator** early, and the **flotatie tank** mid-line.
