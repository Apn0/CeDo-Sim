# Training slide — "De weegschaal" (The weighing scale), slide -6c-

- **Source file:** 117_CeDo39.pdf (D:/drive-download-20251124T130330Z-1-001)
- **Doc id:** OTHER:training-slide (Cedo Kunststofrecycling training deck, "Lean Practitioner")
- **Title (nl):** De weegschaal
- **Title (en):** The weighing scale
- **Slide number:** -6c- (part of the extruder/granulate output sequence)
- **Year/footer:** 2024 — "Cedo Kunststofrecycling" — badge: "LEAN PRACTITIONER"
- **Scope:** Explains the granulate weighing scale used to measure production, with a SCADA screenshot showing live weight and the batch-valve logic. One slide, one screenshot. HIGH value — has real numbers.
- **Line:** general (extruder output / granulate weighing — the "Weegschaal" box from the De Flow diagram 116_CeDo7)

## Body text (verbatim, Dutch)

> -6c-
> Om te bepalen hoeveel men produceert gaat het granulaat over een weegschaal heen en vervolgens opgeslagen in een voorraad silo .
>
> Bij 25 kg gaat bovenste klep dicht en onderste klep open. Bij 0 kg wisselen de stand van de kleppen weer

**English gloss:** "To determine how much is produced, the **granulate passes over a weighing scale** and is then stored in a stock silo. **At 25 kg the upper valve closes and the lower valve opens. At 0 kg the valve positions switch again.**"

## Screenshot description (embedded SCADA image, right side)

Blue SCADA/HMI mimic of the **weigh hopper**: a central hopper/vessel with an inlet at top (green down-arrow = incoming granulate flow) and a conical discharge at the bottom with valves (an **upper klep** at the inlet and a **lower klep** at the discharge). A digital readout box reads **"Meetcont. gewicht  11,3 kg"** ("measured continuous weight 11.3 kg"). Green horizontal arrow indicates product infeed direction; red bar at the bottom = lower valve/gate. Frame/limit switches drawn on the sides.

## Values (verbatim)

- Live/measured weight shown: **11,3 kg** ("Meetcont. gewicht 11,3 kg")
- **Batch trip point: 25 kg** → upper klep (inlet valve) closes, lower klep (discharge valve) opens (dumps the batch to the storage silo).
- **Reset point: 0 kg** → valves switch back (upper opens to refill, lower closes). → i.e. **automatic 25 kg batch weigh-and-dump cycle.**

## Notes / relevance to open questions — HITS

- **Q19 (Stortgewicht / bulk weight — unit + typical value) — PARTIAL/CONTEXT.** The weighing scale measures **granulate weight in kg** ("Meetcont. gewicht 11,3 kg"); production is batched in **25 kg increments**. This is the production-weighing station (not directly a bulk-density measurement), but confirms **kg** as the unit and that output is metered in **25 kg batches** through the weegschaal into the voorraad silo. Evidence: "Bij 25 kg gaat bovenste klep dicht..."; readout "11,3 kg".
- **Q30 (units).** Confirms the weighing readout is in **kg** (mass), batch logic 0→25 kg.
- **Plant map:** ties to the "Weegschaal" box in the De Flow master diagram (116_CeDo7): granulate → weegschaal (25 kg batch cycle) → voorraad silo (stock silo) / bigbag station.
- Explains the game-relevant mechanic: production counting is done by counting 25 kg weigh-dumps (each dump = 25 kg produced).
