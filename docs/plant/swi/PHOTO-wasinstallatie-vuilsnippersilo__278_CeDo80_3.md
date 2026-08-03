# PHOTO — "Wasinstallatie — werking vuilsnippersilo" (Wash installation — dirty-shred silo principle)

- **Source file:** `278_CeDo80 (3).pdf`
- **Type:** Photographed flip-chart / training poster page (Cedo Kunstofrecycling, "LEAN PRACTITIONER" badge, ~2024). Landscape schematic + explanatory caption. No SWI header, no rev.
- **Title (header):** **"Wasinstallatie"** — subtitle **"werking vuilsnippersilo"** (Wash installation — operating principle of the dirty-shred silo)
- **Scope:** Explains how the **vuilsnippersilo** (dirty shredded-film buffer silo, one per line) is fed, keeps material from bridging, and doses it out onto the uittrekschroef → frictiewasser. Shows the silos for **Lijn 3B and Lijn 3A** side by side.

## Diagram — labels (as annotated)
Two hexagonal silos drawn side by side. **Left = "Vuilsnippersilo Lijn 3 B"**, **Right = "Vuilsnippersilo Lijn 3 A"**. A shared feed conveyor runs across the top.
- **"Toevoerband 11"** (Feed conveyor 11) — top-right, brings folie from the sorting line.
- **"Band 12 kan zich verplaatsen naar L- R"** (Belt 12 can move Left–Right) — the traversing distributor conveyor over the top with a double-headed arrow; band 12 shuttles L↔R to fill either silo on demand.
- **"vleugel"** (wing/vane) — a wing mounted on the cone, spreads the film so no bridging forms above the cone.
- **"Ondersteuning en lagering"** (Support and bearing) — the cone's support + bearing.
- **"kegel"** (cone) — central cone inside the silo that prevents bridging (brugvorming) and distributes material.
- **"Vier bodem schrapers"** (Four bottom scrapers) — four bottom scrapers lift material off the floor and feed the uittrekschroef evenly.
- **"Gelijkstroom motor"** (DC motor) — drives the cone/scraper assembly [gelijkstroommotor = DC motor].
- **"Water toevoer"** (Water supply) — water added into the silo.
- **"Uittrek schroef"** (Extraction/draw-out screw) — horizontal screw at the bottom drawing material out toward the frictiewasser; driven by an electromotor whose rpm is set on the E-paneel.
- **"frictiewasser"** — the draw-out screw discharges to the frictiewasser (see `277_CeDo81`).
- **"reductor"** (gearbox) — appears twice (on the draw-out screw drive and on the cone drive).
- **"Hydraulische motor" / "Hydraulic unit"** — the cone in the silo is driven by a **hydraulic motor + reductor** (hydraulic unit shown).
- **"doseerschroef"** (dosing screw) — referenced in caption (material falls toward the dosing screw).

## Caption (verbatim Dutch, bottom of poster)
"De folie wordt aangevoerd vanuit band 11 komende vanuit de sorteerlijn en via transportband 12 verdeeld naar de vuilsnippersilo's naar gelang de vraag.
Als de vuilsnippersilo 100% materiaal vraagt kan band 12 zich verplaatsen.
De kegel zorgt er voor door zijn constructie dat er geen brugvorming in de silo ontstaat. Bodemschraper tillen het materiaal van de bodem op en gelijktijdig zorgen ze voor een regelmatige voeding op de uittrekschroef.
Op de kegel is een vleugel gemonteerd die als doel heeft de folie in de silo te verdelen en te zorgen dat er boven de kegel geen brugvorming ontstaat.
De kegel in de silo wordt aangedreven door een hydraulische motor en reductor.
Uittrekschroef wordt aangedreven door een elektromotor die men kan instellen in toeren op het E-paneel.
Door het extra water op de vuilsnippersilo zorgt ervoor dat de folie wat zwaarder word en naar beneden zakt richting doseerschroef.
Tevens zorgt het water er al voor dat vervuiling verder losweekt van de folie."
- Translation: The film is supplied from **band 11** coming from the sorting line and distributed via **conveyor 12** to the vuilsnippersilos as demanded. When a silo demands 100% material, band 12 can move (shuttle). The **cone (kegel)** by its construction prevents bridging (brugvorming) in the silo. **Bottom scrapers** lift material off the floor and simultaneously provide a regular feed to the draw-out screw. On the cone a **wing (vleugel)** is mounted to distribute the film and prevent bridging above the cone. The cone is driven by a **hydraulic motor and gearbox**. The **draw-out screw (uittrekschroef)** is driven by an electromotor whose rpm can be set on the **E-paneel**. The **extra water** added to the silo makes the film a bit heavier so it sinks down toward the dosing screw; the water also already starts loosening contamination from the film.

## Answers to open questions
- **Q4 / Q5 (wash-line routing, upstream of C1):** IMPORTANT — establishes the head of the wash line: **sorteerlijn → band 11 → traversing band 12 → vuilsnippersilo (per line, e.g. Lijn 3A / 3B) → uittrekschroef / doseerschroef → frictiewasser → C1 pomp → LA3 1e flotatie.** (Chains directly into `277_CeDo81` and `276_CeDo82`.)
- **Line identity:** confirms **separate vuilsnippersilos per line — explicitly "Lijn 3 A" and "Lijn 3 B"** (relevant to the 3A/3B/3C line split). Band 12 distributes between the two silos on demand.
- **Q16/Q18 (rpm / bunker-band units & settables):** the **uittrekschroef rpm is set in "toeren" (rpm) on the E-paneel** — another operator-settable rpm, consistent with shredder/other drives being set in toeren.
- **Anti-bridging design (kegel + vleugel + 4 bodemschrapers, hydraulic drive):** documents the silo internals — useful for a "silo bridging / verstopping" fault mechanic in the sim.
- **Water dosing purpose:** added water (a) makes film heavier so it sinks to the dosing screw, (b) pre-soaks/loosens contamination before the frictiewasser.
- Cross-ref: `277_CeDo81` (frictiewasser, fed from "Dosering vuilsnippersilo"), `276_CeDo82` (frictiescheider), `SWI-012_p1__274_CeDo111` (Lijn-1 machine chain).

## Note
- This is the upstream-most wash poster of the 276/277/278 trio. Combined they give a complete, modelable wash-line flow from sorter output to first flotation.
