# Guide page — Snijproces / Juiste contactdruk mes op matrijsplaat (correct knife-to-die-plate contact pressure)

- **Source file:** `350_CeDo81.pdf`
- **Type:** Training/manual page (EREMA pelletizer), direct continuation of `GUIDE-HDFP-werkingsprincipe-snijproces__349_CeDo79.md`. NL text. Ring-binder page (punch holes). No SWI header/id/date.
- **Companions:** `messen-matrijsplaat-slijtage__066_CeDo82.md`, `EREMA-korrels-matrijsplaat__167_CeDo80.md`, `GUIDE-mes-kop-controleren-rupsband-ondersteuning__348_CeDo83.md`.

## Section 1 — "Snijproces" (continued)
Diagram: a hatched blade/spatel cross-section with a **yellow contact band** where a thin blade crosses a thick blade (the cutting interface highlighted in yellow).

Body text (verbatim NL):
> "Een dergelijk snijproces wordt ook aangetroffen op de matrijsplaat van de pelletizer. De matrijsplaat werkt als een vast mes."
*(A similar cutting process is also found on the die plate (matrijsplaat) of the pelletizer. The die plate acts as a fixed knife.)*

Key concept: the **matrijsplaat (die plate) = the fixed/stationary knife**; the rotating mes shears against it.

## Section 2 — "Juiste contactdruk" *(correct contact pressure)*
Subtitle: **"contactdruk van het mes op de matrijsplaat (geïllustreerd met een spatel)"** *(contact pressure of the knife on the die plate, illustrated with a spatula.)*

Three side-by-side cases — each a yellow spatula-on-hatched-block schematic (top) over a real photo of a cut blade edge (bottom):

| Case | Schematic label | Photo caption | Meaning |
|------|-----------------|---------------|---------|
| **Left — too little** | **"Onvoldoende: creëert een gat"** — with a **"gap"** dimension arrow between spatula and block | **"Materiaal is afgescheurd"** *(material is torn off)* | Insufficient contact pressure → a **gap** remains → material tears instead of cleanly cutting → torn/ragged pellets. |
| **Middle — just right** | **"precies goed"** *(precisely right)* — spatula flush on block, small clean chips | **"Zuivere snee met max. levensduur"** *(clean cut with maximum service life)* | Correct contact pressure → clean shear, minimal wear, longest knife life. |
| **Right — too much** | **"te veel"** *(too much)* — spatula pressed hard, spray of debris | **"Hoge slijtage"** *(high wear)* | Excessive contact pressure → clean cut but **high wear** → short knife/die life. |

## Answers to open questions
- **Q24 (densities):** none.
- No numbered-question answers, but this is the **canonical knife-contact-pressure quality rule** for the pelletizer:
  - **matrijsplaat = vast mes** (die plate acts as the fixed counter-knife).
  - **Too little pressure → gap → torn material (afgescheurd).**
  - **Correct pressure → clean cut + max knife life.**
  - **Too much pressure → clean cut but excessive wear (hoge slijtage).**
  Complements the die-plate wear doc (CeDo82) and the "no gap on measuring table" knife-acceptance check (CeDo83).

## Notes for sim
- Strong quality/maintenance mechanic: a **contact-pressure setting** with a sweet spot. Below it → torn pellets (quality reject). Above it → accelerated knife+die wear → more frequent messenwissel (downtime/cost). "precies goed" = clean cut + max levensduur. This is exactly the kind of tunable the sim can expose to the operator with a penalty on either side.
