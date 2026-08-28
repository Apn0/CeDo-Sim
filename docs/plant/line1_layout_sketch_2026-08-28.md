# Lijn 1 — operator layout sketch (transcriptie), 2026-08-28

**Bron:** plattegrond-schets, door de operator in de chat gestuurd op 2026-08-28
tijdens de docs×sim gap walk, als antwoord op "Where does line 1 turn, and
which way?" ("let me send you an image?").

**⚠ ORIGINEEL NOG NIET GEARCHIVEERD.** Dit bestand is Claude's transcriptie van
het ontvangen beeld; het beeldbestand zelf staat nergens in de repo of in
`CeDo_Simulator_data/`. Per de vaste regel "renders/photos go into the repo"
hoort het origineel hier naast te staan als
`docs/plant/photos/line1_layout_sketch_2026-08-28.<ext>` — **operator: sla het
origineel op.** Tot die tijd is deze transcriptie de enige schriftelijke bron
voor de vouw-benen A–E van `LINE_1_SEQ`; behandel haar zoals elke digest
(volledige transcriptie, niets verzonnen), maar met één niveau minder
zekerheid dan een gearchiveerd origineel.

## Wat de schets toont (plan-view; schermcoördinaten ≈ pixels, y omlaag)

Eén hal-uitsnede rond de kop van lijn 1. "Noord" hieronder = bovenkant van de
schets (echte oriëntatie staat er niet op).

| Element | Positie (≈) | Lezing |
|---|---|---|
| Verticale wand | x ≈ 45 | halwand; de aanvoerband kruist hem |
| Label "conveyor" + horizontale rode lijn | y ≈ 185, x 15 → 110 | aanvoer door de wand, west → oost |
| Verticale rode lijn | x ≈ 80, y 185 → 270 | afslag naar het zuiden, de shredder in |
| Shredder-blok | (57–120, 272–340) | shredder 1 |
| Horizontale rode lijn | y ≈ 300, x 120 → 152 | uitvoer oost, korte oostelijke run |
| Verticale rode lijn | x ≈ 152, y 300 → ~185 | klim terug naar het noorden (westa) |
| Blauwe goot | (135–168, 185–212) | hoekgoot bovenaan de klim, direct vóór de trommel |
| Trommel (horizontaal) | (172–330, 165–230) | VW/SGA-trommel, as oost-west |
| Y-splitsing → 2 blokken | (410–495, 145–192) en (415–497, 200–245) | Y-splitgoot naar frictie L/R |
| Samenkomst → blok | (520–545, 185–232) | ventilator/blower na de frictie-paren |
| Flotatietank | (345–490, 285–355) | ZUIDELIJK van de natte oost-west-straat, westelijk van de blower |

De schets eindigt bij de flotatietank — de staart (dewater → Kufferath/MAS →
extruder) staat er NIET op.

## Lezing → de vouw in `LINE_1_SEQ` (BuildMode.gd)

Bochtenpatroon L, L, R, R (schets) + L (aanname, staart):

| Been | Richting (schets) | Inhoud |
|---|---|---|
| A | zuid (de afslag) | opzetband → shredder |
| B | oost | uitvoerband + magneetband |
| C | noord | kort bandje → westa-klim → hoekgoot (verhoogd) |
| D | oost | trommel → Y-goot → natte straat → intrekschroeven |
| E | zuid | flotatietank + dewater (tank zuidelijk van de straat ✓ schets) |
| F | **oost — AANNAME** | frictie → Kufferath/MAS → silo → compactorband → extruder-staart. Niet op de schets; oost gekozen omdat de plattegrond (`floor_plan_edits.md`) extruder 1 als lang oost-west-blok tegen de zuidwand van Hal 2 tekent. **Operator-oordeel nog nodig.** |

De operator-uitspraak over de hoekgoot ("90 deg right turn from the conveyor
to the drum", 2026-08-28, in de ledger geciteerd) klopt met de schets: klim
noordwaarts, rechtsaf = oost, de trommel-as op.

**Verwerkt in:** `BuildMode.gd` `LINE_1_SEQ` (#fold), bewaakt door
`test_line1_flow_conformance.gd` S5. Ledger:
`DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md` consequence 1.A.
