# EREMA reference — "Geforceerde voeding" (forced feed) + energy demand of the Compactor

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/180_CeDo57.pdf` (1 page)
**Doc type:** Not a SWI. EREMA reference on the **geforceerde voeding (forced feed)** between compactor and extruder screw, plus factors influencing compactor energy demand. Extracted exhaustively.

## Icon + title
Small icon (compactor-to-screw feed) + heading **"Geforceerde voeding"** *(forced feed / force feeding).*

## Section — "Functie:" (function)
**Bullets (verbatim):**
> - "Intensief in de schroef duwen (ongeveer **1500 keer duwen/min**.), Compactor biedt materiaal om te schroeven. Als de schroef vol is, passeert het materiaal => **zelf instellend**." *(Intensively pushing into the screw (~1500 pushes/min); the Compactor offers material to the screw. When the screw is full, the material passes by => self-regulating/self-adjusting.)*
> - "stroming geoptimaliseerde inlaat (octrooi geregistreerd)" *(flow-optimised inlet — patent registered)*
> - "schroef constant gevuld met warm, samengeperst materiaal" *(screw constantly filled with warm, compacted material)*

## Section — "Invloed op de energievraag van de Compactor" (influence on compactor energy demand)
**Left column — factors (verbatim):**
> - "Polymer" *(polymer type)*
> - "Doorvoer" *(throughput)*
> - "Fysieke verschijning" *(physical appearance)*
>   - "Bulkdichtheid" *(bulk density)*
>   - "Grootte en vorm" *(size and shape)*

**Right column — Vochtigheidsgraad (moisture content) energy figures (verbatim):**
> "Vochtigheidsgraad *(moisture level)*
> Voor verdamping: **0,72 kWh/ltr** ->
> Ca. **1 kWh/ltr** (incl. condensverliezen)
> Bijwerking: **1 ltr. water → 1673 ltr. stoom!!**"
> *(Moisture content — for evaporation: 0.72 kWh/litre → approx. 1 kWh/litre including condensation losses. Side effect: 1 litre of water → 1673 litres of steam!!)*

## Notes / open-question hits (Q24 / Q30 — HITS)
- **Q30 (units / energy):** the compactor's forced-feed screw pushes **~1500 times/min** into the extruder screw; the feed is **self-regulating ("zelf instellend")** — when the extruder screw is full, extra material passes by. Confirms the compactor→extruder handoff is a patented flow-optimised **geforceerde voeding**. Energy is quantified in **kWh/litre of water evaporated**.
- **Q24 (feed density / moisture):** DIRECT hit on the physical factors driving compactor energy: **polymer type, throughput (doorvoer), and physical form — specifically BULK DENSITY (bulkdichtheid) and size/shape.** Higher bulk density and correct size/shape feed the screw better. Moisture is expensive: **~0.72 kWh/litre to evaporate water, ~1 kWh/litre including condensation losses**, and **1 litre of water flashes to 1673 litres of steam** — the physical basis for the "sauna effect" (see `175_CeDo58`). This confirms **bulk density is a first-order input** to the compactor model and that **wet feed is a massive energy/throughput penalty** (every litre of moisture costs ~1 kWh and 1673 L of steam to manage).
- **Q20 (slow-running → remedies):** reinforces that **wet / low-bulk-density / wrong-size feed raises compactor energy demand and destabilises the screw fill** → remedy = dry the feed and control flake size/bulk density upstream. Complements `176_CeDo56` (don't overfill) and `179_CeDo55` (dry-feed kW curve).
- **Sim modelling numbers to capture:** forced-feed ~1500 pushes/min; moisture penalty ~1 kWh/L; 1 L water → 1673 L steam; compactor energy = f(polymer, throughput, bulk density, size/shape, moisture). Bulk density (bulkdichtheid) and moisture are the two operator-controllable levers.
- Completes the EREMA compactor/extruder binder set in this batch (166,167,169,171,175,176,177,178,179,180).
