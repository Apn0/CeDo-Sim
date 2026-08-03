# Training flipbook slide -3- — De extruderschroef (the extruder screw)

- **Doc type:** OTHER — training presentation slide (flipbook), NOT a SWI
- **swi_id:** OTHER:training-slide
- **Title (NL):** De extruderschroef
- **Title (EN):** The extruder screw
- **Slide number:** -3-
- **Series:** Cedo Kunstofrecycling training deck, Lean Practitioner
- **Year:** 2024
- **Source file:** 100_CeDo31.pdf
- **Scope:** Full-length labelled diagram of the two-part extruder screw, showing zone layout and laserfilter position

## Content (verbatim NL + EN gloss)

**Body text -3-:**
> "Iedere soort kunststof heeft zijn eigen ontwerp van extruderschroef, wij verwerken alleen LDPE"

EN: "Every type of plastic has its own extruder-screw design; we only process LDPE."

**Diagram — a single long extruder screw drawn horizontally, split into a 1e deel (1st part) and a 2e deel (2nd part), joined by a "Schroefdraad verbinding" (threaded coupling). Zones labelled left → right:**

1. **aandrijving** (drive) — far left end (the drive coupling / gearbox end, shown with keyed shaft).
2. **Intrek / transport zone** (intake / feed-transport zone).
3. **compressie zone** (compression zone).
4. **pomp zone** (pump/metering zone).
5. **Laserfilter** — labelled at the top-center with a **blue downward arrow** pointing to the screw between the 1e deel pomp zone and the start of the 2e deel. This is the **melt filter located between the first and second screw sections** (mid-screw, after the first pump zone).
6. **Meng zone** (mixing zone) — first zone of the 2e deel, just after the laserfilter.
7. **vacuum zone** (vacuum/degassing zone).
8. **compressie zone** (second compression zone).
9. **pomp zone** (second pump/metering zone) — far right, feeding the die end.

- **Under-labels:** "1e deel" spans the left half (drive → laserfilter); "2e deel" spans the right half (laserfilter → die). "Schroefdraad verbinding" (threaded connection joining the two screw parts) sits at the mid-point.
- **Reference link printed on slide:** https://www.youtube.com/watch?v=MgWMjmdJlf8

**Footer:** "2024 — Cedo Kunstofrecycling" + LEAN PRACTITIONER badge.

## Notes / answers to open questions
- **Q15 (which extruder temp zones are before vs after the laserfilter):** **DEFINITIVE zone order.** The extruder is a **two-part (tandem) screw with the laserfilter in the middle.**
  - **BEFORE the laserfilter (1e deel):** aandrijving (drive) → **Intrek/transport zone → compressie zone → pomp zone** → [Laserfilter].
  - **AFTER the laserfilter (2e deel):** [Laserfilter] → **Meng zone (mixing) → vacuum zone (degassing) → compressie zone → pomp zone** → die.
  - So the reported temperature profile (e.g. 200-235-175-240-245-250-255 C) maps: the **early low zone (175 C, "zone 3")** corresponds to the intake/transport region where cold film crumb is still being conveyed and compacted — it is kept lower to avoid premature melting/bridging at the feed; melt is built up through the first compression + pump zone, filtered at the laserfilter, then re-homogenised (meng), degassed (vacuum), re-compressed and pumped to the die at the hottest zones. The two **pump (metering) zones** bracket the laserfilter and generate the pressure to push melt through the filter and then through the die.
- **Material:** Plant processes **only LDPE** (low-density polyethylene) — confirms the sim's LDPE-only feedstock.
- **Q33/machine:** Two-part screw joined by a threaded coupling; consistent with a large recycling extruder with a mid-line melt filter (laserfilter = Britas-style / rotary-disc melt filter per project notes).
