# Guide page — Meskop controleren + Zijdelingse ondersteuning rupsband (knife-head check / crawler-track lateral support)

- **Source file:** `348_CeDo83.pdf`
- **Type:** Instruction/guide page (likely from an EREMA compactor or pelletizer maintenance manual / training). Mixed NL + EN captions. No header block, no SWI id, no date on this page.
- **Companions:** compactor knife docs (`REF-roterende-messen-HSS-HM-compactor__300_CeDo63.md`, `messen-matrijsplaat-slijtage__066_CeDo82.md`, `EREMA-compactor-vaste-messen-demonteren-naslijpen__305_CeDo64.md`, `steunplaten-schade__065_CeDo78.md`).

## Section 1 — "De kop van een mes controleren" *(checking the head of a knife/blade)*
Two photos:
- **Left photo:** a knife/blade component (roterend mes — a rotor knife with a cross/star hub) held/photographed on its own.
- **Right photo (close-up on a measuring table):** the knife head seated on a **meettafel** (measuring table), with a **red arrow** pointing to the seam where the knife meets the table.
- **Overlaid EN caption (on right photo):** **"No gap visible — Sufficient support on the measuring table"**.
- **NL caption under photos:** **"Geen spleet zichtbaar. Voldoende steun op de meettafel."** *(No gap visible. Sufficient support on the measuring table.)*
- Meaning: when checking a knife head, seat it on the measuring table and verify **no gap** between knife and table → the knife has sufficient/flat support (i.e. not worn or deformed). A visible gap = reject/regrind.

## Section 2 — "Zijdelingse ondersteuning van de rupsband" *(lateral support of the caterpillar/crawler track)*
- **Line drawing (top):** two mushroom/pin-shaped elements side by side with a dimension callout **"gap"** and small up/down arrows marking the clearance between them — schematic of the gap to inspect between adjacent track/support pieces.
- **Red circle-with-exclamation-mark (!) warning icon** at left — caution/attention marker for this check.
- **Photo (bottom):** close-up of the actual assembly — a row of rounded metal support pins/lugs (the "rupsband" lateral supports) on a curved stainless housing, showing the real gaps to inspect.
- Meaning: inspect the **lateral support of the crawler/caterpillar band (rupsband)** for the specified **gap** between support elements; the (!) flags it as a critical check.

## Interpretation / context
- "Rupsband" (crawler/caterpillar track) + "mes" (knife) + measuring-table check points to a **pelletizer / die-face cutter or a track-fed cutting assembly** where blades ride a band and must sit gap-free. The knife-head flatness check (no gap on meettafel) and the rupsband lateral-support gap check are two acceptance criteria for reused/reground knives and their guides.

## Answers to open questions
- **Q24 (densities) / Q15 (temp zones):** none.
- No direct numbered-question answers. Adds a **knife-acceptance criterion** ("no gap on measuring table = sufficient support") and a **rupsband lateral-support gap** inspection to the compactor/pelletizer maintenance corpus.

## Notes for sim
- Quality-gate mechanic: when regrinding/refitting a knife, the sim can require a "measuring table gap = 0" check to pass. A visible gap → knife rejected → downtime. The (!) rupsband gap is a second inspection point.
- [unsure] exact machine (compactor vs pelletizer) — the star-hub knife photo resembles a rotor knife; the "rupsband" wording is unusual for a die-face cutter, so possibly a specific EREMA cutter assembly.
