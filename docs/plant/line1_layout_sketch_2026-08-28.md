# Lijn 1 — operator layout sketch (transcriptie), 2026-08-28

> **⚠ AMENDMENT 2026-09-17 (operator, live chat) — drie correcties, waarvan er
> twee de vouw in dit bestand veranderen. Lees deze vóór de tabellen hieronder.**
>
> **De originele tekening is er wél.** Dit bestand waarschuwt hieronder dat het
> origineel "nergens in de repo" staat. Dat klopt voor de *plattegrond*-schets,
> maar niet voor de washing-flow-tekening: die staat gearchiveerd als
> `docs/plant/photos/line1_washing_flow_sketch_2026-08-28.png` en is de bron
> voor correctie 3. Wie de vouw van lijn 1 nakijkt, kijkt daar eerst.
>
> ### 1. De natte straat is TWEE ONAFHANKELIJKE STROMEN
>
> Operator, letterlijk: "from the first scheidingsgoot: one half of the material
> goes to the left, other half goes to the right. both streams then continue —
> by themselves independently — to: friction, glijgoot, mechanical, pipe, blower,
> pipe, cyclone. then the 2 cyclones feed the top of the mill by gravity. the
> mill is a single machine, but it splits the material left and right, so each
> side, after reaching the bottom of the mill: blower, pipe, cyclone,
> transportation screw — and then the material converges again in the flotation
> tank."
>
> Dat was **niet** wat de sim bouwde. De macro-SEQ is een plaatsingslijst, geen
> topologie, en de bedrading werd deels door de geometrie-fallback van LineFlow
> geraden. Gemeten met `src/tests/dump_line1_graph.tscn` (nieuw — het dumpt de
> echte grafiek, niet de SEQ), vóór de fix:
>
> | wat de operator zegt | wat er stond |
> |---|---|
> | scheidingsgoot splitst in 2 | **3** uitgangen; de derde ging rechtstreeks naar een mech_dryer en sloeg zijn frictiescheider over |
> | frictie → glijgoot → mechanical | **beide** frictiescheiders loosden direct in de **mill** |
> | blower → pipe → cyclone | de twee blowers voedden **elkaar** (L → R → L, een gesloten lus zonder cycloon) |
> | 2 cyclonen voeden de mill | beide pre-mill cyclonen hadden **geen enkele invoer** |
>
> Opgelost met een nieuwe macro-sleutel `{"stream": "L"/"R"}` (zie
> `_build_full_line`): entries met hetzelfde label ketenen kop-aan-staart aan
> elkaar en raken de andere stroom nooit. Een stroom **opent** op de laatste
> hoofd-entry (de splitsing) en **sluit** op de volgende (de samenvoeging) — bij
> lijn 1 dus twee keer: scheidingsgoot → mill, en mill → flotatietank.
> `parallel_branch` is van het frictie-paar af: díe sleutel koppelt zijn siblings
> aan de eerstvolgende hoofd-entry, en dat was precies de oorzaak.
>
> De **glijgoot en de pipes zijn geen machines** — LineFlow past ze per EDGE aan
> (`_make_connector`: frictie-bron → dichte glijgoot; mech_dryer → blower →
> elleboogpijp; blower → cycloon → Ø140 ronde pijp). Ze verschijnen dus vanzelf
> zodra de edges kloppen, en ze stonden fout omdat de edges fout stonden.
> De 50/50 is LineFlow's standaard 1/n bij twee uitgangen — geen coëfficiënt.
>
> Bewaakt door **`test_line1_twin_streams`** (nieuw, in de harness). T8 is de
> belangrijkste: geen enkele machine mag zijn eigen zustermachine voeden. Dat is
> de blower-lus, en die is onzichtbaar voor elke andere test — in een 2-cyclus
> heeft elke node keurig één in en één uit.
>
> ### 2. De trommel stond 2,5 m te laag
>
> Operator: "the trommel/drum is too low, increase height by 2.5 meters."
> `PlaceableCatalog.VW_TROMMEL_LIFT_M = 2.5` is de **enige** bron: de `y` van de
> drum-entry, de lift van de `sga_feed_chute` erboven, de afgeleide `incline_run`
> van `drum_feed_belt` én diens `gap` lezen allemaal dáár. Een zwaartekracht-
> machine optillen zonder zijn aanvoer mee op te tillen koppelt de lijn los — de
> mutatietest laat de bandlip 2,35 m ONDER de gootinlaat eindigen.
>
> De `gap` van `drum_feed_belt` (2.14 → 2.14 + 2.5) beweegt mee omdat deze band
> op 45° klimt, waar run == rise. Bij een andere hoek is die optelling niet meer
> geldig — zelfde val als de westa-gap bij 30°.
>
> Gemeten na de wijziging: funnel van 4,15 → **6,65 m**, alle vier de
> overdrachten 0,00 m horizontaal.
>
> ### 3. De flotatietank stond 90° verkeerd — het moet 180° zijn
>
> Operator: "the direction of travel of the material through the drum is 180 deg
> opposite of the direction of travel in the flotation tank, when looking from
> top-down view → flotation tank is wrongly positioned."
>
> Dat staat ook gewoon op de gearchiveerde tekening: de trommel loopt links→rechts
> over de bovenkant van het vel, de flotatietank ligt eronder en loopt
> rechts→links, gevoed aan zijn rechterkant door de post-mill cyclonen en
> schroeven, lozend aan zijn linkerkant in de ontwateringsschroef.
>
> Gemeten vóór de fix: **270°** verschil (een haakse bocht). Nu **180,0°**.
>
> Been E draaide `-90`; dat kon niet anders, want een 180°-bocht draait om de
> cursor en stuurt de lijn dwars terug over zijn eigen machines. Nieuwe sleutel
> **`{"leg_offset": m}`** schuift het nieuwe been zijdelings van het draaipunt af
> en maakt de U-bocht pas uitdrukbaar. `-7.45` is **afgeleid**, niet van de
> tekening afgemeten (die is uit de losse hand; zijn eigen schaal verschilt ~1,5×
> tussen de trommel en de mill):
> halve straatbreedte 3,70 + halve tankbreedte 2,25 + 1,50 loopruimte voor het
> bordes dat de tekening tussen beide tekent.
>
> **Gevolg voor been F en G.** Been E 180° draaien draait alles erachter mee. De
> ongewijzigde `+90` van been F wijst de frictie/Kuferath/MAS-trein nu naar het
> zuiden — precies zoals de tekening hem onder de tank tekent — en de tekening
> stuurt daarna lange pijpen oostwaarts naar de compactor/extruder. Daarom is er
> een **been G** bijgekomen (`turn_deg` op de cycloon ná de MAS-blowers), zodat
> extruder 1 het lange oost-west-blok tegen de zuidwand van Hal 2 blijft — dát is
> wat de operator-uitspraak "leg F is correct" beschermt.
>
> De vouw is daarmee 7 bochten over 8 benen:
> `RIGHT 90 , LEFT 90 , LEFT 90 , RIGHT 90 , REVERSE 180 , LEFT 90 , LEFT 90`.
> Plan-box 120,7 × 26,3 m → **85,2 × 40,2 m** (schil 140 × 155): de serpentine
> vouwt de lijn compacter.
>
> Bewaakt door `test_line1_flow_conformance` S1 (bocht-hoeken, niet meer alleen
> de tekens — een tekenlijst kan een 90°-hoek niet van deze 180° onderscheiden)
> en S5 (trommel↔tank 180°, tank náást de straat, been E→F→G, extruder op de
> oost-west-as). Alle vier mutatiegetest.
>
> Render: `docs/plant/renders/shot_line1_plan_annotated_2026_09_17.png`.

> **⚠ AMENDMENT 2026-09-16 (operator, live chat) — supersedes leg A below.**
> There is only ONE real Westa Band, and it sits at the **shredder infeed**,
> not after the shredder. Corrected flow: `opzetband_1` (funnel feeder,
> through the wall) → 90° turn right → `westa_band_1` → `shredder_1`. The
> belt this file's leg C calls "westa" (climbing from the magnet run up to
> the hoekgoot/drum) is **not** a Westa Band — it's a plain conveyor, renamed
> `drum_feed_belt` in code. Leg A's table row below ("opzetband → shredder",
> no turn) is now wrong; everything else in this file (legs B–F) is
> unaffected. See `BuildMode.gd` `LINE_1_SEQ` (#fold 2026-09-16) and
> `PlaceableCatalog.gd` `_build_opzetband` for the corrected geometry.
>
> Leg A is now split in two: the feeder gets its own leg (east, through the
> wall) and the sketch's south afslag becomes the leg that carries the Westa
> and the shredder. The compensating LEFT turn on the first entry is what
> keeps legs B–F pointing where this file's table says they point — without
> it the new RIGHT turn rotates the whole 160 m line 90° inside the shell.
>
> De deck-hoogte en incline-run van de Westa zijn **afgeleid**, niet gemeten:
> zijn inlaat ligt één transfer-drop van 0,30 m onder de afwerplip van
> `opzetband_1` (die volgt uit de operator-opgave "10 m op 25°") en zijn eigen
> lip één drop boven de keel van `shredder_1`. De **hoek** is het enige getal
> dat de twee uiteinden niet kunnen leveren — die bepalen de stijging, niet de
> afstand waarover de band die haalt.
>
> **Hoek = 30°, operator 2026-09-17** (verving de 45°-placeholder waarmee de
> afleiding was opgezet). Bij 30° loopt de band 5,76 m horizontaal in plaats van
> 3,32 m voor dezelfde stijging van 3,32 m, dus lengte 3,92 m → **6,36 m**. De
> `gap` ná deze entry in `LINE_1_SEQ` is hiervan afgeleid en beweegt mee:
> −1,48 → **+0,957**. Wie de hoek wijzigt, herberekent die gap
> (`gap = run + flat − westa_half − shredder_half`); de `turn_advance` van −2,9
> hangt alleen van de catalogus-box af en blijft staan.
>
> Beide overdrachten in-world gemeten door `test_line1_flow_conformance` S6/S6b:
> lip → Westa-dek **horiz 0,00 m / drop 0,30 m**, Westa-lip → shredder-keel
> **horiz 0,00 m / drop 0,30 m**.
>
> Geschematiseerd (plan + opengevouwen aanzicht) in
> `docs/plant/renders/line1_head_schematic_2026_09_17.png`, getekend door
> `tools/line1_head_schematic.py` uit de meting die
> `src/tests/dump_line1_head.tscn` uitschrijft.

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
| D | oost | trommel → Y-goot → natte straat (2 stromen) → mill → intrekschroeven |
| E | **west — 180°, GECORRIGEERD 2026-09-17** | flotatietank + dewater, ANTI-PARALLEL aan de trommel en zijdelings naast de straat (`leg_offset`). Was zuid (90°); zie amendement 3 bovenaan. |
| F | **zuid — volgt uit E** | frictie → Kufferath → MAS. Ongewijzigde `+90`, maar hij wijst nu zuid doordat been E 180° draaide — en zo tekent de washing-flow-schets deze trein ook, onder de tank. |
| G | oost — **NIEUW 2026-09-17** | blowers → cycloon → extruder_silo → compactorband → extruder-staart. Bestaat zodat extruder 1 het oost-west-blok blijft dat de plattegrond (`floor_plan_edits.md`) tegen de zuidwand van Hal 2 zet — dát is wat de operator-bevestiging "leg F is correct" (2026-08-28, herbevestigd 2026-09-06) beschermt. |

## Overbandmagneet boven de uitvoerband (2026-09-16/17)

> **Operator-correctie, live chat.** De overbandmagneet is een cross-belt
> afscheider die **boven** de uitvoerband hangt, gecentreerd over de lengte —
> géén station in de rij. Het model was altijd al zo gebouwd
> (`_m_overband_magnet`: "suspended self-cleaning cross-belt separator above the
> conveyor", trommels op de X-as, schrootgoot naar +X); alleen de plaatsing was
> fout, en als rij-entry schoof hij bovendien alles ná hem ~3,5 m verder over
> been B.

Opgelost met de nieuwe macro-sleutel `{"mount_over": N}` in `BuildMode.gd`: die
ankert een entry op het geplaatste midden van entry N en **verzet de cursor
niet**. Plaatsing en flow-rol zijn bewust gescheiden (`off_cursor` stuurt
geometrie, `is_branch` stuurt topologie), zodat de magneet gewoon op het
hoofd-materiaalpad blijft. De spiegel in `save_macro_overrides` loopt mee, anders
drijft alles ná een gemonteerde entry weg bij opslaan/herladen.

**De 25 cm werkspleet.** Eerst gemeten: de standaard zijgeleiders van de
`transport_belt` stonden **0,333 m** boven het dek — hóger dan de spleet zelf,
dus 25 cm boven het dek was langs geen enkele kant haalbaar (band omhoog =
geleiders dwars door de magneettrommels; magneet omlaag = kop onder de
geleiders). Operator-besluit 2026-09-17: de geleiders zijn fout.

| | vóór | ná |
|---|---|---|
| zijgeleider boven dek | 0,333 m | 0,150 m (skirt board) |
| dek-hoogte uitvoerband | 0,675 m | 0,956 m (`y` 0,281 + `extend_legs`) |
| magneet ↔ dek | 0,567 m | **0,250 m** |
| val `shredder_1` → dek | 0,675 m | **0,394 m** |

`side_rail_y_frac` is daarvoor een spec-sleutel geworden in `BeltBuilder` (was de
kale literal 0.28), zodat alleen deze band een skirt-board-profiel krijgt en niet
elke band in de fabriek. De railhoogte zelf, `UITVOERBAND_RAIL_H_M` = 0,15 m, is
**nog niet opgemeten** — wat wél van de operator komt is de randvoorwaarde die
hem oplevert. Alles eromheen (de fracs, de lift, de shredder-val) leidt zich af
uit die ene waarde.

Bewaakt door `test_line1_overband_mount` (T2 montage, T4 been B niet opgerekt,
T5 geen doordringing, T6 de 25 cm, T7 de shredder-val). Mutatiegetest: oude
geleiders terug → T5 meldt −0,083 m, precies de 8,3 cm doordringing.

## Plan-view renders van de gebouwde lijn (2026-09-16)

`src/tests/shot_line1_plan.tscn` (WINDOWED draaien — headless heeft geen
rendering device) bouwt lijn 1 echt via `_build_full_line` en schiet hem met een
**orthografische** camera recht van boven. Orthografisch is hier het punt: onder
perspectief leunt een 120 m lange lijn aan de randen naar buiten en meet een
bocht van 90° niet als 90° op de pixels.

| Bestand in `docs/plant/renders/` | Toont |
|---|---|
| `shot_line1_plan_full_2026_09_16.png` | de hele vouw, 119.9 × 24.0 m gemeten |
| `shot_line1_plan_head_2026_09_16.png` | de gecorrigeerde kop: opzetband → bocht rechts → westa → shredder |
| `shot_line1_plan_annotated_2026_09_16.png` | schema met been-kleuren en gemeten bochten |
| `shot_line1_elevation_magnet_2026_09_16.png` | **zij-aanzicht**: de magneet boven de uitvoerband, de enige view waarin de 25 cm te zien is |
| `shot_line1_plan_2026_09_16.json` | de meting zelf (id, positie, leg-anchor, AABB per machine) |

De annotatie (`tools/line1_plan_annotate.py`) leest het **leg-anchor** dat de
macro zelf op elke node stempelt (`macro_anchor`, `BuildMode.gd:2429`), niet de
vorm van de wandeling. Dat is bewust: lijn 1 zet meerdere stations als
zij-aan-zij PAREN neer, dus de wandeling zigzagt, en de lump carts bij het
laserfilter zijn meubilair naast been 7 in plaats van een eigen been — een
differentie-pass rapporteert die als twee extra benen en plakt de twee echte
kop-benen aan elkaar.

Gemeten bochtvolgorde over de 7 **bezette** benen:
`RIGHT 90 , LEFT 90 , LEFT 90 , RIGHT 90 , RIGHT 90 , LEFT 90`.
De macro rapporteert 8 benen; het verschil is been 0, dat leeg is doordat de
compenserende LEFT-bocht vóór de eerste entry valt.

De operator-uitspraak over de hoekgoot ("90 deg right turn from the conveyor
to the drum", 2026-08-28, in de ledger geciteerd) klopt met de schets: klim
noordwaarts, rechtsaf = oost, de trommel-as op.

**Verwerkt in:** `BuildMode.gd` `LINE_1_SEQ` (#fold), bewaakt door
`test_line1_flow_conformance.gd` S5. Ledger:
`DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md` consequence 1.A.
