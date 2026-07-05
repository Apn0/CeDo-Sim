# TRAIN — "Wat is dan Slow Running?" (slow-running definition + causes)

- **Source file:** 249_CeDo46.pdf
- **Type:** Training slide (CeDo x Newton training deck; CeDo logo bottom-left, "Newton" logo bottom-right)
- **Title (as printed):** "Wat is dan Slow Running?" ("So what is Slow Running?")
- **Scope:** Defines slow running vs budget throughput on the extruder; lists possible causes.

## Bar chart (extruder output over an 8-hour shift)
- Y-axis top mark: **1200 kg/hr** (labeled "Extruder")
- X-axis: **8 uur** ("8 hours")
- Green band (Output/Snelheid) labeled **1000 kg/hr** (actual sustained output)
- Yellow band on top labeled (callout): **"Slow Running – 200kg per uur"** (the ~200 kg/h shortfall vs budget)
- So: budget 1200 kg/hr − actual 1000 kg/hr = **200 kg/h lost to slow running**.

## Legend (color key, bottom-right)
- **Yellow = Slow running**
- **Red = Stop**
- **Green = Output/Snelheid** ("Output/speed")

## Callout box (yellow)
"**Slow running** — Wat is de reden dat er niet meer gemaakt kan worden tijdens normale productie?" ("Slow running — what is the reason that no more can be made during normal production?")

## Mogelijke redenen ("Possible reasons") — bullet list — Q20 ANSWER
- **Shredder brengt niet genoeg (extruder silo leeg)** — "shredder isn't delivering enough (extruder silo empty)" → infeed-starved
- **Maalmolen gaat continue in overload** — "grinding mill keeps going into overload"
- **Extruder filter wisseltijd te kort** — "extruder filter change interval too short" (too-frequent screen changes)
- **Extruder filter druk te hoog** — "extruder filter pressure too high"
- **Extruder Max RPM** — "extruder at max RPM" (speed-capped, can't go faster)

## Footer
"**Budget snelheid is 1200 kg/hr**" ("Budget speed is 1200 kg/hr")

## Answers hunted
- **Q9 (line throughput kg/h):** Budget/target throughput = **1200 kg/hr**; realistic sustained output shown = **1000 kg/hr**; slow-running shortfall = **200 kg/h**. Doc 249_CeDo46. (Cross-check: live snapshot in 247_CeDo3 showed 1087 kg/h — between the 1000 and 1200 figures.)
- **Q20 (slow-running remedies per cause):** This slide gives the **CAUSES** (5 listed above), which map directly to remedies:
  - silo leeg / shredder too slow → ensure shredder/infeed keeps extruder silo full
  - maalmolen overload → reduce mill loading / clear overload
  - filter wisseltijd te kort → dirty material / screen fouling; extend screen life / improve upstream cleaning
  - filter druk te hoog → change screen / reduce contamination
  - extruder max RPM → already speed-limited; only more throughput via bigger bite / cleaner melt
  (Explicit remedy text is not on this slide — only causes; the remedies are the inverse of each cause.) Doc 249_CeDo46.
- **Q21 (1200 kg/hr budget — which line):** Footer states budget = 1200 kg/hr for "Extruder" generically in this Newton training. Not line-tagged on this slide (applies to the extruder throughput concept; likely the main line-1/3 extruders). The 1087 kg/h live value (247_CeDo3) is on an EREMA line. Doc 249_CeDo46. [Line attribution NOT specified — training-generic.]
- **Q16 (Bunker speed 200-800 unit):** Not on this slide (this is extruder kg/hr, not bunker rpm). No info.
- **Newton:** third-party training provider ("Newton" logo) — CeDo used Newton for operator OEE/slow-running training. Relevant: the sim's "slow running" loss category comes from this real training framework (Yellow=Slow running, Red=Stop, Green=Output).
