# Water circuit vers kanaal water — verse kanaalwatertoevoer (volledige transcriptie)

**Bron:** `C:/Users/arnod/Documents/CeDo_Simulator_data/Water_circuit_kanaalwater.pdf` (1 pagina, foto van geprinte slide in rode ordner)
**Extractiedatum:** 2026-07-04
**Jaartal op slide:** 2024 (linksonder in voettekstbalk)
**Voettekst:** donkerblauwe balk met "2024" links en "Cedo Kunst..." [gecentreerd, deels overstraald; vermoedelijk "Cedo Kunstofrecycling" zoals op de andere slides]; rechtsonder badge "LEAN PRACTITIONER".

**Titel verbatim:** "**Water circuit vers** kanaal **water**" — "vers" en "water" groot, "kanaal" kleiner ertussen; lees: water circuit vers kanaalwater (fresh canal water).

**Tekstblok linksboven (verbatim):** "**Het vers kanaalwater wordt toegevoegd aan bestaande circuits**" (the fresh canal water is added to existing circuits).

**Foto-artefacten (geen diagraminhoud):** ringbandringen bovenaan, gekleurde tabbladen onderaan, rode ordnerrand. Vage doordruk van een volgende pagina rechts op de slide (onleesbaar).

**Er staan geen volumes, debieten, drukken of niveau-setpoints op dit diagram.** Geen pomp-id's op deze slide.

---

## Layout

Donkerblauwe cirkelboog met **4 oranjegele stippen** (knooppunten), genummerd **1 t/m 4 met de klok mee**: 1 boven (12:00), 2 rechts (3:00), 3 onder (6:00), 4 links (9:00). In het midden een blauw recirculatie-icoon (drie gebogen pijlen), **zonder** tekstlabel (anders dan bij La1/La2).

**De cirkel is niet gesloten:** de boog is onderbroken linksboven. Het boogsegment vanaf knooppunt 4 eindigt met een omhoog krullend uiteinde rond ~10:00; daarna volgt een opening; het bovensegment begint pas weer links van knooppunt 1 (~11:30). Passend bij de tekst: het is een **toevoerketen** (vers water erin), geen gesloten kringloop — na 4 loopt het water de bestaande circuits in en komt het niet terug bij 1.

## Legenda (verbatim, linksonder op de slide)

1. **hoofd leiding vanuit kelder** (main supply line from the cellar/basement)
2. **blauwe tank** (blue tank)
3. **oa koeling op hydrauliek units** (o.a. = onder andere; i.a. cooling on the hydraulic units)
4. **naar wasinstallaties** (to the washing installations)

## Keten (kanten, met de klok mee)

Open keten: 1 → 2 → 3 → 4 → (bestaande circuits).

| # | Van | Naar | Medium |
|---|-----|------|--------|
| 1 | hoofd leiding vanuit kelder (1) | blauwe tank (2) | water (vers kanaalwater) |
| 2 | blauwe tank (2) | oa koeling op hydrauliek units (3) | water |
| 3 | oa koeling op hydrauliek units (3) | naar wasinstallaties (4) | water |

## Kruisverwijzingen

- Knooppunt 2 **is** de blauwe tank uit `water_circuit_blauwe_tank.md` (expliciete koppeling tussen beide slides). Daar is de kanaalwater-inname als apart blok "Kanaalwater" getekend met o.a. een directe pijl in de tank.
- Knooppunt 3 ("oa koeling op hydrauliek units") komt overeen met de kanaalwatervoeding van "Extruder 3a, 3b en lijn 1 koelwater van warmte wisselaars" en "vacuum en centrifuge water" op de blauwe-tank-slide (koeling van extruder-hulpsystemen van lijn 1, 3A en 3B).
- Knooppunt 4 ("naar wasinstallaties") = de was-verbruikers (was 1, was 3a, was 3b) die de blauwe tank voedt.
- Het lijn 1 flow diagram (`docs/plant/lijn_1_flow.md`) noemt daarnaast "Koeltoren circuit inclusief voorbehandeld kanaalwater" — de koeltorenroute staat **niet** op deze slide. [unsure: of "koeling op hydrauliek units" hier het koeltorencircuit omvat]
- "hoofd leiding vanuit kelder": de kelder (basement, onder de hal) is het binnenkomstpunt van het kanaalwater. [unsure: exacte locatie/inhoud van de kelder — operator vragen]
