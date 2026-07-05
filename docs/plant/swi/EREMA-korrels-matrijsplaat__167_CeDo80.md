# EREMA Pelletising reference — "Korrels van de hete matrijsplaat tillen" & "Transport van de korrels"

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/167_CeDo80.pdf` (1 page)
**Doc type:** Not a SWI. EREMA die-face pelletiser (hot-die-face cutting) reference page — knife-geometry theory + pellet water-transport schematic. Machine-spec content extracted exhaustively.

## Section 1 — "Korrels van de hete matrijsplaat tillen"
> *Lifting the pellets/granules off the hot die plate*

**Embedded schematic** — cross-section of a die-face cutter knife meeting the die plate, with three labelled angles on the knife/pellet:
- **rake angle** ("draaihoek")
- **cutting angle** ("snijhoek")
- **clearance angle** ("vrijloophoek")
- **stress angle** [unsure — small labelled angle near the knife tip]

English annotations on the schematic (verbatim):
- "Lifting the particle from the die plate via the rake angle"
- "No further contact with the knife with optimum angular guidance"
- "If knife speed is too low => insufficient acceleration"
- "No lift-off and/or no acceleration => pellets stick together"
- "If contact pressure is too high => cutting edge too flat => material not lifted off fast enough"

**Dutch body text (verbatim):**
> "Het deeltje van de matrijs tillen via de draaihoek. Geen verder contact met het mes met optimale hoekgeleiding.
> Als de snij snelheid te laag is: => onvoldoende acceleratie
> Geen lift-off en/of geen acceleratie: => korrels kleven aan elkaar
> Wanneer contactdruk te hoog is: => snijkant te vlak => materiaal wordt niet snel genoeg opgetild"

*(Gloss: Lift the particle off the die via the rake angle; no further knife contact with optimal angular guidance. If cutting speed too low → insufficient acceleration. No lift-off/acceleration → pellets stick together. If contact pressure too high → cutting edge too flat → material not lifted off fast enough.)*

## Section 2 — "Transport van de korrels van de matrijsplaat"
> *Transport of the pellets away from the die plate*

**Dutch text (verbatim):**
> "Zorg ervoor dat het water vrij stroomt!!  Intake  Sproeiers  Uitlaat"
> *(Ensure the water flows freely!! Intake / Sprayers / Outlet.)*

**Embedded cutaway diagram** of the knifehead / water-ring housing with airflow + waterflow arrows. English labels on the diagram (verbatim):
- "airflow thru knifehead"
- "airflow thru waterring"
- "air inlet"
- "waterring" (two positions labelled)
- "knifehead"
- "water inlet"
- "Outlet air, water and pellets" (large blue arrow pointing down out the bottom into a hopper/pipe)

Flow logic shown: cooling **water enters via a waterring** around the knifehead; **air** assists through the knifehead and waterring; cut pellets are entrained in the water and blown out the **outlet (air + water + pellets)** downward toward the dewatering stage.

## Notes / open-question hits
- **Q5 (granuleerwater loop):** Direct hit on pelletiser water routing. The die-face cutter uses a **waterring** with a **water inlet** and a combined **"Outlet air, water and pellets"** — this is the head end of the granuleerwater (pellet water) loop. Water must "vrij stromen" (flow freely) through Intake → Sproeiers (sprayers) → Uitlaat. Downstream this outlet feeds the dewatering (Ontwaterzeef / centrifuge) which the sim ties into the tankje-tussen-extruders loop.
- **Q15/Q33 (extruder/pelletiser):** confirms CeDo pelletising is **hot-die-face cutting under water** (EREMA style) — pellet quality depends on knife speed (acceleration), contact pressure, and rake/clearance angle. Sticking pellets ("korrels kleven aan elkaar") is a defined failure mode when knife speed too low → relevant to sim quality/defect modelling and to Q20 (slow-running causes/remedies): remedy for stuck pellets = increase knife speed / check contact pressure / ensure free water flow.
- Reinforces the EREMA machine family for the CeDo extruder line (companion to `166_CeDo69` screw-speed & temperature sheet).
