# SIMATIC WinCC — wash-line SCADA mimic (German labels)

- **Source file:** `256_CeDo51.pdf`
- **Type:** Single photo of a SCADA HMI screen. Title bar: "SIMATIC WinCC flexible Runtime" [unsure: "SIMATIC WinCC flexible Runtime"]. "TOUCH" watermark down the right edge (touch-panel). NOT a Cedo-PROD-SWI.
- **Language:** German (this is the OEM wash-line control system — likely the Herbold/other DE-made washing installation). Windows XP-style window chrome.
- **Scope:** Full process mimic of the **voorwas + wasstraat (pre-wash + wash line)** — from Aufgabeband (infeed belt) through shredder, friction separators, washers, to the EREMA end. Highly relevant to Q5 (water routing) and general wash-line topology.

## Legend (verbatim numbered list, top-right of screen — German → English gloss)

| Nr | German | English gloss |
|----|--------|---------------|
| 01 | Aufgabeband | infeed / feed belt |
| 02 | Shredder | shredder |
| 03 | Austragband | discharge belt |
| 04 | Magnetscheider | magnetic separator |
| 05 | Friktionsabscheider | friction separator |
| 06 | Friktionsabscheider | friction separator |
| 07 | Intensivwäscher | intensive washer |
| 08 | Fördereinheit | conveying unit |
| 09 | Schneidmühle | granulator / cutting mill |
| 10 | Fördereinheit | conveying unit |
| 11 | Trennbehälter | separation tank (float/sink) |
| 12 | Friktionsabscheider | friction separator |
| 13 | Schneckenpresse | screw press |
| 14 | Förderventilator | conveying fan / blower |
| 15 | Silo | silo |
| 16 | Entwässerungssieb | dewatering screen |
| 17 | Cantileverpumpe | cantilever pump |
| 20 | Vorwaschtrommel | pre-wash drum |

(Note: legend skips 18, 19 — not shown.)

## Status indicator groups (colored dot columns, verbatim)

Each equipment cluster has a 4-state status legend block (bereit / Betrieb / Störung / Notaus):
- **Weima:** bereit / Betrieb / Störung / Notaus  → (Weima = shredder brand, near items 01–03)
- **Delta Impax:** bereit / Betrieb / Störung / Notaus → (near item 20 Vorwaschtrommel)
- **MAS:** bereit / Betrieb / Störung / Notaus → (MAS = MAS extruder/separator brand, near items 14–15, right side)
- **Kufferath:** bereit / Betrieb / Störung / Notaus → (Kufferath = GKD/Kufferath screen mesh, near item 13 Schneckenpresse)
- **EREMA:** bereit / Störung → (bottom-right, the EREMA extruder end — only 2 states shown)

Gloss: bereit = ready, Betrieb = running/operation, Störung = fault, Notaus = emergency-stop.

## Water & flow annotations on the mimic (verbatim German)

- **Wasseraufbereitung (Grobstufe)** — water treatment (coarse stage) — labeled box upper-left with valves.
- **Wasseraufbereitung** — water treatment (upper-left).
- **Frischwasser** — fresh water (labeled feed line running across the middle, top).
- **zur Wasseraufbereitung** — "to water treatment" (return arrow, bottom-left).
- **Schwergut** — heavy fraction / sink material (labeled tank near item 16/17, center-top). = the heavies rejected in the float-sink.
- **Entwässerungssieb** — dewatering screen (item 16, center-top, feeds from Schwergut area).
- **Metall** — metal (reject bin near item 04 Magnetscheider, upper-left) — magnetic separator ejects to a "Metall" box.

## Equipment placement / instance tags (as drawn, left→right, top→bottom)

- Upper band: green down-arrows (infeed) → ① Aufgabeband → ② Shredder → ③ (Austragband/Metall reject) → Magnetscheider → valves → **⑳ Vorwaschtrommel** (large horizontal drum, top-center) → discharge (red arrow right) → ⑰ Cantileverpumpe (pump symbol) + Schwergut tank + ⑯ Entwässerungssieb.
- Mid/lower field (yellow-green): friction separators **6a, 6b** (inclined screw washers, left), pumps **7a, 7a1, 7b, 7b1**, pumps **08a, 08b**, granulators/units **09, 09a**, **10a, 10b** (pumps, red-circled P markers = P2/P3 alarms?), separators **11a, 11B, 11c, 11d, 11e, 11f**, mixer/trennbehälter block **m11a / m11 / m11c / m11d** (red-highlighted = the Trennbehälter float-sink cluster), item **12** Friktionsabscheider (right), **13** Schneckenpresse (×2, right-center), **14** Förderventilator, silos **15a, 15b, 15c, 15d, 15e, 15f** (right stack of 6 silos), and the EREMA feed (green arrows into extruder bottom-right, red "P" marker).
- Many valve symbols and orange (material/warm) vs blue (water) piping arrows throughout.

## Pipe color convention (as drawn)
- **Orange/red arrows** = material or warm/process flow (and pump discharge).
- **Blue arrows** = water flow (fresh water down-feeds, returns "zur Wasseraufbereitung").
- Fresh water (Frischwasser) enters top-center and branches down (blue) to washers; spent water returns bottom-left (blue) to Wasseraufbereitung.

## Open-question relevance
- **Q5 (water routing):** Confirms wash-line water topology in German terms — Frischwasser feeds in at top, distributes (blue) to Intensivwäscher/Friktionsabscheider/Trennbehälter, and spent water returns "zur Wasseraufbereitung" (bottom-left). Grobstufe = coarse water-treatment stage. Schwergut (heavies) go to Entwässerungssieb via Cantileverpumpe(17). Not the ZSS/blauwe-tank Dutch loop specifically, but the OEM (German) equivalent map.
- **Q6 (Pomp zeefbocht):** No "zeefbocht" term here; nearest is Entwässerungssieb (16) + Cantileverpumpe (17) dewatering the Schwergut/heavies.
- General: This mimic uses German OEM naming (Weima shredder, Delta Impax, MAS, Kufferath, EREMA) — a different vendor-labeling layer than the Dutch SWIs. Item 11 **Trennbehälter** = the float/sink separation tank (matches Dutch "flotatietank"/"scheider"). No direct Dutch line-number (3A/3B) mapping shown.
- No numeric throughput/kg-h values (Q9, Q21) on this screen.
