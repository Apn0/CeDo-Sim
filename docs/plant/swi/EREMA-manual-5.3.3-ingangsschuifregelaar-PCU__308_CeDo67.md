# EREMA manual 5.3.3 — De ingangsschuifregelaar instellen in de PCU (setting the infeed-slider regulator)

- **Source file:** `308_CeDo67.pdf` (single page, EREMA manual excerpt, scanned; Fig. 89)
- **SWI id:** none (EREMA manual section **5.3.3**)
- **Title:** De ingangsschuifregelaar instellen in de PCU
- **Title (EN gloss):** Setting the infeed-slider regulator (*ingangsschuifregelaar* / *invoerschuif* = infeed slider) in the PCU (Process Control Unit)
- **Scope:** How the infeed slider between cutter-compactor and extruder screw controls material intake; adjust to material type to avoid overfeeding the extruder screw.
- **References:** Fig. 89 "Compactor – invoerschijf"; complements EREMA-manual-5.3.2-instelprocedure and EREMA-geforceerde-voeding; PCU family (EREMA-compactor-PCU).

## Text (verbatim NL + EN gloss)
Section: "**5.3.3 De ingangsschuifregelaar instellen in de PCU**"

"Afhankelijk van het type grondstof (granulaat, folie, enz.) worden verschillende hoeveelheden materiaal in de extruder gezogen. Door de invoerschuif (1) omhoog of omlaag te bewegen, wordt de vulopening naar de extruderschroef (2) vergroot of verkleind; dit varieert op zijn beurt de hoeveelheid toevoer."
- EN: *Depending on the type of raw material (granulate, film, etc.), different amounts of material are drawn into the extruder. By moving the infeed slider (1) up or down, the fill opening to the extruder screw (2) is enlarged or reduced; this in turn varies the amount of feed.*

**info pictogram (blue "i" box):** "Om overlopen van de extruderschroef (2) te voorkomen, moet de invoerschuif (1) worden ingesteld op de eigenschappen van het te verwerken materiaal!"
- EN: *To prevent overflowing/flooding of the extruder screw (2), the infeed slider (1) must be set to the properties of the material being processed!*

## Fig. 89 (description) — "Compactor – invoerschijf"
Photo (metallic interior, looking into the transition throat between compactor and extruder). Callouts:
- **(1)** invoerschuif (infeed slider) — with a double-headed vertical arrow (↕) indicating up/down travel.
- **(2)** extruderschroef (extruder screw), lower part of image (dark opening / mechanism at bottom).
Bright galvanized side panels with bolt rows.

## Adjustment rule (verbatim)
- "materiaalinname verhogen: schuifregelaar omhoog" = *increase material intake: slider regulator UP.*
- "materiaalinname verlagen: schuifregelaar omlaag" = *decrease material intake: slider regulator DOWN.*

## Q&A hits
- **Q30 (units — slider):** infeed slider position is the "slider %" seen on the overview HMI (307_CeDo53). This page explains its physical meaning: up = more intake, down = less; set to material type to avoid extruder-screw overflow.
- Reinforces the operator lever set from 307 (Positie invoerschuif). No direct numbered-question answer beyond slider mechanics.
