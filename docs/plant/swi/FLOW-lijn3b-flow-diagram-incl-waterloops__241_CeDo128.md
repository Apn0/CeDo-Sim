# FLOW — Lijn 3b flow diagram incl. waterloops (process + water-circuit block diagram)

- **Source file:** `241_CeDo128.pdf`
- **Doc id:** none (titled block diagram)
- **Title:** "Lijn 3b flow diagram incl waterloops" ("Line 3b flow diagram including water loops")
- **Date:** 20-04-2023
- **Publisher:** CeDo (logo bottom-right)
- **Type:** process flow diagram of **Line 3b**, with the **water circuits** overlaid (grey/tan boxes = material path; blue/purple boxes = water & pump loop).
- **Scope:** full Line-3b material path (dry-fed vuilsnipper silo → wash/float/dry → extrude/laserfilter → pelletize → silo) PLUS the wash-water pump/tank loops and cooling/sewer circuits.

## Legend of box colours
- **Grey/tan boxes** = solids/material processing equipment.
- **Blue / purple boxes** = **water-loop** elements (tanks, pumps, separators, cooling, sewer).

## Band 1 (top material train) — left → right
1. **Vuilsnipper silo 3b** — dirty-shredder silo 3b (infeed buffer of shredded dirty film)
2. **Doseerschroef M11a** — dosing screw M11a (meters material out)
3. **Rafter** — [unsure: "Rafter" = a rafting/washing tank or brand; a wet pre-wash "raft" separator]
4. **Ontwaterschroef van rafter** — dewatering screw of the rafter
5. **Frictiescheider 210** — friction separator 210
6. **Intrekrol flotatie tank** — pull-in roll of the flotation tank
7. **flotatie tank** — flotation tank (sink-float)
8. **Uittrek rol flotatie tank** — pull-out roll of the flotation tank
9. **Ontwater schroef** — dewatering screw
   - **Blue overlay boxes above band 1:** **Zandscheider** (sand separator) → **LA1** → **P1** (water-loop: sand separator with pump LA1/P1 returning clarified water; arrows loop back to Rafter and flotatie tank).

## Band 2 (drying train) — right → left return
10. **Frickischeider li/re** — [friction separator left/right — "Frickischeider" = misspelling of Frictiescheider]
11. **Mechanische droger 310** / **Mechanische droger 311** — mechanical dryers 310 & 311 (parallel)
12. **Ventilator** — fan/blower
13. **Verdeelwals** — distribution roller (spreads material)
14. **Thermische droger** — thermal dryer (hot-air), fed from below by:
15. **Heater** — heater (supplies hot air to the thermische droger)
16. **ventilator** — fan
17. **Ringventilator** — ring blower (conveys to next band)

## Band 3 (extrusion + pelletize) — left → right
18. **Extruder silo** — extruder buffer silo
19. **Compactor band** — compactor feed belt
20. **Compactor** — compactor (PCU)
21. **Extruder laserfilter vacuum** — extruder incl. **laserfilter** + **vacuum** degassing
22. **Kopfilter & heetafslag** — head filter & hot die-face cut ("heetafslag" = hot-face pelletizing at the die head)
23. **Ontwaterzeef** — dewatering sieve (pellet/water separation)
24. **Centrifuge** — centrifuge (pellet drying)
25. **Weegschaal** — weigh scale
26. **MS / LS silo buiten** — outdoor MS/LS product silo (final storage)

## Water loops (blue/purple boxes, bottom band + top overlay)
Left group (wash-water supply/return):
- **Pomp was 3b** — pump for wash 3b
- **Pomp was 4** — pump for wash 4
- **Pomp zeefbocht** — **pump of the sieve-bend (zeefbocht)**  ← ANSWERS Q6
- **Blauwe tank** — blue tank (wash-water buffer) ← feeds/receives from ZSS + Vers kanaalwater
- **ZSS** — (wash-water screening/sludge unit)
- **Vers kanaalwater** — fresh canal water (make-up water intake)

Center group (extruder cooling water):
- **Blauwe vat** — blue vessel/drum → **Pomp** (supplies extruder/laserfilter vacuum + die cooling)

Right group (pellet-water + cooling + sewer):
- **Tankje tussen extruders** — small tank between extruders → **Pomp**
- **Riool naar EOP** — sewer to **EOP** (Effluent/End-Of-Pipe water treatment / waste-water plant)
- **Koeltoren circuit** — cooling-tower circuit

Top overlay group (float/sand water clarification):
- **Zandscheider → LA1 → P1** — sand separator + pumps returning clarified process water to the wash/float tanks.

## Water-loop routing (derived from arrows)
- **Vers kanaalwater** (fresh canal water) is the make-up source → into **Blauwe tank** (with ZSS screening) → pumped by **Pomp was 3b / Pomp was 4 / Pomp zeefbocht** into the wash & flotation stages.
- **Zandscheider (LA1/P1)** clarifies float/wash water (drops out sand) and recirculates it back to the Rafter/flotatie tank — a closed wash-water loop.
- **Blauwe vat + Pomp** feeds the extruder **laserfilter vacuum** / die cooling water.
- Pellet-side water (from **Ontwaterzeef / Centrifuge**) collects in **Tankje tussen extruders**, is pumped, joins the **Koeltoren circuit** (cooling tower), and overflow/dirty water goes to **Riool naar EOP** (sewer to effluent treatment).

## Answers to open questions
- **Q6 (Pomp zeefbocht — location & function):** **CONFIRMED.** "**Pomp zeefbocht**" is an explicit box in the Line-3b water loop (bottom-left blue group), a dedicated **pump for the zeefbocht (sieve-bend)** in the wash-water circuit, drawing from the **Blauwe tank** and returning water to the wash/float stages. It sits alongside **Pomp was 3b** and **Pomp was 4**. This resolves the earlier low-confidence guess on doc 238 — the zeefbocht pump is a real, named wash-water-loop pump. [certain]
- **Q10 (blauwe tank):** **Blauwe tank** confirmed as a **wash-water buffer tank** in the Line-3b loop, fed by **Vers kanaalwater** (fresh canal water) + **ZSS**, supplying the wash pumps (was 3b, was 4, zeefbocht). A separate **Blauwe vat** feeds extruder cooling. Volume not numerically stated here (see doc 240 layout: 5 m³/8 m³ tanks in Hal 1). [likely — function confirmed, volume from layout doc]
- **Q4 (laserfilter placement / cooling):** Laserfilter is inline at the extruder ("Extruder laserfilter vacuum") with **vacuum degassing**; its vacuum/cooling water comes from the **Blauwe vat + Pomp** loop. Downstream: **Kopfilter & heetafslag** (head filter + hot die-face cut) → ontwaterzeef → centrifuge → weegschaal → MS/LS silo. Confirms hot die-face ("heetafslag") pelletizing on 3b.
- **Q (water treatment / effluent):** Plant routes dirty water to **Riool naar EOP** (sewer to EOP effluent plant) and runs a **Koeltoren circuit** (cooling tower) + **Zandscheider (LA1/P1)** sand-separation clarification loop — a mostly closed wash-water system with fresh-canal-water make-up. Good detail for a water-management sim mechanic.
- **Q (dryers on 3b):** Line 3b drying = **Mechanische droger 310 + 311** (parallel) then a **Thermische droger** (hot-air, fed by a **Heater**) + **verdeelwals** + fans, plus final **centrifuge** on the pellet side. Distinct from Line 1 (doc 239) which used MAS dryers.
- **Equipment differences 3b vs Line 1:** 3b uses "Rafter", "Frictiescheider 210", "Intrekrol/Uittrek rol flotatie tank" (rolls, not screws), thermische droger + heater; Line 1 used HPS/SGA, maalmolen, Kufferath + MAS droger + Deltoid fans. Useful for per-line asset differentiation in the sim.
