# Materiaal-bulkdichtheden — PCU/compactor (volledige transcriptie)

**Bron:** `C:/Users/arnod/Documents/CeDo_Simulator_data/for_claude_data_needed_densities.pdf` (1 pagina, foto van geprinte pagina in ordner; door de operator aangeleverd SPECIAAL als data-bron voor de simulator)
**Extractiedatum:** 2026-07-04

**Foto-artefacten (geen inhoud):** ringbandringen rechts, gekleurde ordnerrand links (groen/blauw), zwarte balken boven/onder. De pagina is licht gekromd maar volledig leesbaar; geen handgeschreven aantekeningen.

**Context:** de pagina is een documentatiepagina over de **PCU** (Preconditioning Unit — snijverdichter/cutter-compactor, het EREMA-voorbewerkingsdeel vóór de extruderschroef). Rechtsonder bij de opsomming staat een klein rond icoon van een compactor/vat met zijaandrijvingen en een pijp-elleboog bovenop.

---

## Sectie 1 — Functie (verbatim)

**Functie:**

- ➤ Snijden -> Frictie -> Verwarmen: vlokken krimpen en plakken lichtjes aan elkaar – samenpersen
  *(Cutting -> Friction -> Heating: flakes shrink and stick lightly together – compacting)*
- ➤ Voorbeelden: *(Examples:)*

## Sectie 2 — Dichtheden-tabel (verbatim, alle rijen)

| Materiaal | Bulkdichtheid invoer *(bulk density infeed)* | PCU uitvoer bulkdichtheid *(PCU output bulk density)* |
|---|---|---|
| BO-PP folie 10 µm *(BOPP film 10 µm)* | 25 kg/m³ | 375 kg/m³ |
| LD-Pe film 100 µm *(LDPE film 100 µm)* | 180 kg/m³ | 380 kg/m³ |
| LLD-Pe film 35 µm *(LLDPE film 35 µm)* | 110 kg/m³ | 390 kg/m³ |

Opmaak origineel: tabelrijen om-en-om lichtblauw gearceerd; kolomkoppen "Materiaal", "Bulkdichtheid invoer", "PCU uitvoer bulkdichtheid".

## Sectie 3 — Voordelen (verbatim)

**Voordelen:** *(Advantages:)*

- ➤ Vergelijkbare bulkdichtheid in de compactor **leidt tot een veelzijdiger, universeel schroefontwerp** (rood/bruin benadrukt in origineel) *(Comparable bulk density in the compactor leads to a more versatile, universal screw design)*
- ➤ Effectief vullen van de extruderschroef *(Effective filling of the extruder screw)*
- ➤ Actief gegroefd invoergedeelte *(Actively grooved intake section)*

Wanneer de invoer onderbroken wordt, is er nog steeds genoeg materiaal om de extruder te voeden voor enkele minuten.
*(When infeed is interrupted, there is still enough material to feed the extruder for several minutes.)*

De invloed van ongesneden materiaal dat in de compactor valt is gering.
*(The influence of uncut material falling into the compactor is minor.)*

---

## Sectie 4 — Confrontatie met huidige sim-aannames (2026-07-04)

| Sim-plek | Huidige waarde | Doc zegt | Oordeel |
|---|---|---|---|
| `src/sim/LineFlow.gd:31` `FEED_DENSITY = 320.0` kg/m³ ("injected feed volume") | 320 | losse gesneden film invoer = 25–180 kg/m³; PCU-uitvoer = 375–390 kg/m³ | **TEGENSPRAAK** — 320 past bij geen van beide toestanden. Als FEED_DENSITY losse film vóór de compactor voorstelt → moet ~110–180 (film) zijn; als het compactor-uitvoer (`cc_in`) voorstelt → moet ~375–390 zijn. |
| `src/scenes/world/ShredderFeedBelt.gd:93` `OUTPUT_DENSITY = 180.0` kg/m³ (coarse film-flake) | 180 | LD-Pe film 100 µm invoer = 180 kg/m³ | **BEVESTIGD** voor dik LDPE-film; dun film (LLD-Pe 35 µm) zou 110 zijn, BOPP 10 µm zelfs 25. |
| `src/sim/BaleDefs.gd:15` `BULK_DENSITY = 175.0` kg/m³ (baal) | 175 | geen baaldichtheid in dit doc | Geen uitspraak — doc gaat over losse vlokken en PCU-uitvoer, niet over balen. (NB: taakomschrijving noemde 320 kg/m³ voor balen; de code staat inmiddels op 175, gekalibreerd op operator-baalgewichten.) |
| `src/sim/FloorPile.gd:25` / `WasteContainer.gd:66` default 200 kg/m³ | 200 | — | Geen directe uitspraak; 200 ligt tussen film-invoer (110–180) en PCU-uitvoer (375–390). |

**Sim-relevantie:** de tabel geeft precies het dichtheidssprong-moment in de PCU (snijverdichter) op lijn 3A/3B: fluf van 25–180 kg/m³ wordt crumb van 375–390 kg/m³. `MaterialBatch` (massabehoud, volume verandert) kan dit exact modelleren.

## Open vragen voor operator

1. Is `FEED_DENSITY` in LineFlow bedoeld als dichtheid vóór of ná de compactor? (Doc dwingt een keuze af: ~110–180 vóór, ~375–390 ná.)
2. Welke van de drie materialen is representatief voor de normale CeDo-menging (vermoedelijk LD-Pe film 100 µm)? Draaide er ooit BOPP op 3A/3B?
3. Bestaat er een vergelijkbare tabel met **baal**-bulkdichtheden per herkomst (Alba Marl, Zwolle, …)? Dit doc geeft die niet.
