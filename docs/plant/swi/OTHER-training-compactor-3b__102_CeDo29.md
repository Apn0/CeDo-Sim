# Training flipbook slide -3- (B) — De Compactor (compactor cross-section & kW zones)

- **Doc type:** OTHER — training presentation slide (flipbook), NOT a SWI
- **swi_id:** OTHER:training-slide
- **Title (NL):** De Compactor
- **Title (EN):** The compactor (film agglomerator/densifier) — cross-section & control
- **Slide number:** -3- (a second, more detailed compactor slide; distinct from 099_CeDo30 which is the RPM/T/KW triangle)
- **Series:** Cedo Kunstofrecycling training deck, Lean Practitioner
- **Year:** 2024
- **Source file:** 102_CeDo29.pdf
- **Scope:** Purpose of the compactor, the KOUD/EVENWICHT/SMELT temperature-kW ladder, and a labelled schematic

## Content (verbatim NL + EN gloss)

**Body text -3-:**
> "Het doel van de compactor is het verder verkleinen van de folie door de ontstane wrijving te verwarmen en verder te drogen, vervolgens wordt de smelt de extruderschroef ingedrukt."

EN: "The purpose of the compactor is to further reduce the film size, heat it via the friction generated and dry it further; the melt is then pressed into the extruder screw."

**Left image:** Engineering line drawing (side elevation) of the compactor vessel with viewing port (circled) and base/piping.

**Center — a vertical bar ladder (three stacked bands) with a kW scale on the right:**
- Top band: **"KOUD — afkomstig uit silo"** (COLD — coming from the silo). Cold film feed entering.
- Middle band: **"EVENWICHT IN TEMPERATUUR — materiaal koud/warm"** (temperature equilibrium — material cold/warm). Transition band.
- Bottom band: **"JUISTE 'SMELT' TEMP VOOR COMPRESSIE"** (correct 'melt' temperature for compression).
- kW scale markings on the right, aligned to the bands: **160 kW** (top of range) / **150 kW** (marked twice, the target midpoint) / **130 kW** (bottom of range). I.e. the compactor power operating window is roughly **130-160 kW, target ~150 kW**, correlated with reaching correct melt temperature for compression.

**Right — labelled schematic of the compactor bowl (rotating-disc agglomerator), callouts:**
- **"Compacter opvoerschroef brengt Materiaal (vochtig en koud) naar compacter"** — the compactor feed/elevating screw brings damp, cold material into the compactor (top-down grey arrow inlet).
- **"Stoom + lucht uitlaat"** (steam + air outlet) — red arrow up-left to a **Ventilator** (fan/extractor).
- **"Lucht inlaat rooster"** (air inlet grille) — top right.
- **"Water injectie"** (water injection) — green arrow into the bowl.
- **"Temperatuur instelling"** (temperature setting) — red.
- **"Temperatuur meeting"** (temperature measurement) — red.
- **"Extruder rpm instelling"** (extruder rpm setting) — red.
- **"Kw instelling"** (kW setting) — red, bottom.
- **"Material (droog en heet) naar extruder — Roterende schijf"** — material (dry and hot) goes to the extruder via the rotating disc.
- Bottom: **"snippers"** (film snippets/flakes) shown around the bowl walls; a motor **"M"** drives the roterende schijf (rotating disc); date stamp "f)nov.2010" [unsure: 9 nov 2010].
- Dimension **"H"** marked on the bowl height.

**Footer:** "2024 — Cedo Kunstofrecycling" + LEAN PRACTITIONER badge.

## Notes / answers to open questions
- **Q30 (power_CC units):** **CONFIRMED kW.** Compactor power ("Kw instelling") runs on a ladder of **130 / 150 / 160 kW**, target **~150 kW**, tied to reaching the correct melt temperature for compression. So compactor power in the sim (power_CC) is **kW**, with a realistic operating band ~130-160 kW.
- **Q16 (compactor / bunker speed):** Compactor has an **"Extruder rpm instelling"** and a **feed/elevating screw ("opvoerschroef")**; the main working element is a **roterende schijf (rotating disc)** driven by motor M.
- **Compactor process model (sim-ready):** Cold, damp film flakes ("snippers") enter from the silo via the feed screw → thrown against the bowl by the rotating disc → **friction heats & dries** them (steam+air extracted by fan; **water injection** trims temperature) → material passes through **KOUD → EVENWICHT → correct SMELT temp for compressie** → dry, hot melt pressed into the extruder screw. Operator controls: **temperature setpoint, kW setpoint, extruder rpm, water injection.**
- **Machine identity:** A **rotating-disc thermokinetic compactor/agglomerator** (e.g. plast-agglomerator style), motor-driven disc, ~130-160 kW, with air/steam extraction and water injection cooling.
