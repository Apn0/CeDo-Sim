# REFERENCE — Roterende messen (rotating cutter knives) HSS vs HM, for the Compactor

- **Source file:** `300_CeDo63.pdf` (1 page scan of a reference/spec sheet with knife photos + dimensioned drawings)
- **Type:** Equipment reference sheet — rotating cutter-knife (compactor cutter) selection guide. Two knife families compared.
- **Faint watermark:** "...sen..." (likely a supplier/brand watermark; illegible). [unsure]

## Section 1 — "Roterende messen HSS 3mm en 5mm" (HSS rotating knives 3 mm & 5 mm) — VERBATIM
- `De 5mm HSS messen kunnen harde stukken veel beter aan. Daarom kunnen dikwandige stukken, grote brokken verwerkt worden. We raden ook de HSS-messen aan voor alle laserfilter toepassingen.`
  (The 5 mm HSS knives handle hard pieces much better. Therefore thick-walled pieces / large chunks can be processed. We also recommend the HSS knives for all laserfilter applications.)
- Drawing callouts: blade thickness `5` (mm); detail "DETAIL A M10:1"; cutting-edge geometry **60°** and **40°** angles; tolerance `0,2 -0/+2` [unsure exact tolerance format] on a face.

## Section 2 — "Roterende messen HM" (HM = hardmetal / carbide rotating knives) — VERBATIM
- `De 5mm HM messen mogen alleen worden gebruikt voor: schoon productieafval zoals PP-folie, vezels of niet-geweven materiaal.`
  (The 5 mm HM knives may only be used for: clean production waste such as PP film, fibres, or non-woven material.)
- `Deze messen worden beschadigd door Harde stukjes die in de Compator komen.`
  (These knives are damaged by hard pieces that enter the Compactor.) — "Compator" = Compactor [sic].
- Drawing callouts: width `7`; edge dims `1,5`, angle `45°` [unsure], `(6)`, `(2,5)`, thickness `5`, bore/spec `⌀ 6±0.2` (6 mm ±0.2 hole).

## Answers to open questions
- **Q15 (laserfilter / cutter feed):** Explicit guidance: **"We raden ook de HSS-messen aan voor alle laserfilter toepassingen"** — HSS (not HM/carbide) knives are recommended for ALL laserfilter applications, because HSS 5 mm tolerates hard/thick chunks. → In the plant, the compactor cutter feeding the laserfilter line runs **5 mm HSS** knives. Carbide (HM) is reserved for clean PP film / fibre / non-woven, and is damaged by hard bits entering the compactor.
- **Q (material grades / contamination):** Clean-vs-dirty stream distinction is real: **HM knives only for clean production waste (PP-folie, vezels, niet-geweven)**; anything with hard contaminant chunks must use HSS. Maps directly to a sim mechanic where feeding contaminated/hard material with the wrong (carbide) knife causes knife damage/wear events.
- **Compactor confirmed** as the cutter housing upstream of the extruder/laserfilter (the knives sit "in de Compactor"). Corroborates the compactor-extraction interlock ("Afzuiging compactor AAN") seen on the 3C HMI photos.

## Notes for sim
- Knife/consumable model: two knife types — **HSS 5 mm** (tough, for hard/thick + all laserfilter feed) and **HM/carbide 5 mm** (only clean PP film/fibre/non-woven; breaks on hard bits). Wrong knife + contaminated feed → accelerated wear / breakage event. Also a 3 mm HSS variant exists.
- Reinforces contamination sensitivity: hard chunks in the compactor damage tooling → a quality/contamination cost lever.
