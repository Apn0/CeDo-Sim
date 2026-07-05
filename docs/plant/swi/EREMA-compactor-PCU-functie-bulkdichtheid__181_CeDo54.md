# EREMA Compactor (PCU) — Functie & Bulkdichtheid tabel

- **Source file:** 181_CeDo54.pdf (1 page, scanned, EREMA/CeDo training slide)
- **Doc id / slug:** EREMA-compactor-PCU-functie-bulkdichtheid
- **Doc type:** EREMA compactor (PreConditioning Unit / PCU) training slide — machine function + density reference table
- **Scope:** Compactor stage on extruder line(s) (PCU feeds extruder screw)
- **Language:** Dutch verbatim, English gloss on first use
- **Photo/graphic:** Bottom-right pictogram = stylized compactor/tank vessel with rotor icon (dumbbell-like symbol). Right margin shows a metal ring-binder spiral (scan artifact, part of the physical binder).

## Functie (Function)
- **Snijden -> Frictie -> Verwarmen** (Cut -> Friction -> Heat): *"vlokken krimpen en plakken lichtjes aan elkaar - samenpersen"* — flakes shrink and stick lightly together, then are compacted/pressed together.
- **Voorbeelden** (Examples): see table.

## Bulkdichtheid tabel (Bulk density table) — VERBATIM
| Materiaal (Material) | Bulkdichtheid invoer (Infeed bulk density) | PCU uitvoer bulkdichtheid (PCU output bulk density) |
|---|---|---|
| BO-PP folie 10 µm (BOPP film 10 µm) | 25 kg/m³ | 375 kg/m³ |
| LD-Pe film 100 µm (LDPE film 100 µm) | 180 kg/m³ | 380 kg/m³ |
| LLD-Pe film 35 µm (LLDPE film 35 µm) | 110 kg/m³ | 390 kg/m³ |

## Voordelen (Advantages) — VERBATIM
- *"Vergelijkbare bulkdichtheid in de compactor **leidt tot een veelzijdiger, universeel schroefontwerp**"* — Comparable bulk density in the compactor leads to a more versatile, universal screw design.
- *"Effectief vullen van de extruderschroef"* — Effective filling of the extruder screw.
- *"Actief gegroefd invoergedeelte"* — Actively grooved feed section.
- *"Wanneer de invoer onderbroken wordt, is er nog steeds genoeg materiaal om de extruder te voeden voor enkele minuten."* — When infeed is interrupted, there is still enough material to feed the extruder for several minutes.
- *"De invloed van ongesneden materiaal dat in de compactor valt is gering."* — The influence of uncut material falling into the compactor is small.

## Answers to open questions
- **Q24 (feed density: film vs crumb; per-origin densities) — DIRECT ANSWER.** The "Bulkdichtheid invoer" (infeed) figures are **pre-compactor FILM**, not crumb: BOPP 10µm = 25 kg/m³, LDPE 100µm = 180 kg/m³, LLDPE 35µm = 110 kg/m³. The **PCU output** (post-compactor crumb/agglomerate) converges to ~375–390 kg/m³ regardless of input (BOPP 375, LDPE 380, LLDPE 390). Quote: *"Vergelijkbare bulkdichtheid in de compactor leidt tot een veelzijdiger, universeel schroefontwerp."* So the sim's ~110–180 range = loose film infeed; ~375–390 = compacted crumb output. Note BOPP infeed is far lighter (25 kg/m³) but still compacts to 375.
- **Q25 (did BOPP run on 3A/3B?) — HINT.** BO-PP folie 10 µm is listed as a processed material example in this CeDo EREMA compactor doc, implying BOPP was among run materials. Line not specified here.
