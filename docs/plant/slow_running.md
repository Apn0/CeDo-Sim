# Slow Running — definitie en oorzaken (definition and causes)

> **Sources:**
> - `C:/Users/arnod/Documents/CeDo_Simulator_data/Slow_running.pdf` (1 page, photo of a printed CeDo/Newton training slide in binder)
> - `C:/Users/arnod/Documents/CeDo_Simulator_data/Slow_running_2.pdf` (1 page, photo of the follow-up slide in the same binder)
> **Extraction date:** 2026-07-04
> Both slides carry the CeDo logo (bottom left), the Newton logo (bottom right) and the footer line **"Budget snelheid is 1200 kg/hr"** (budget speed is 1200 kg/hr).

---

## Source 1: Slow_running.pdf — "Wat is het Verschil tussen Stilstand (Downtime) en Slow Running"

(What is the difference between Stilstand (Downtime) and Slow Running)

Slide with two stacked chart panels, each showing two horizontal bar timelines ("Shredder" and "Extruder") along a time axis that ends at **"8uur"** (8 hours — one shift). Legend bottom right: red square = **"Stop"**, green square = **"Output/Snelheid"** (output/speed).

### Panel 1 (top)

- **Shredder** bar: green from the start, then a **red segment** roughly 1/5 along the bar, then green to the end of the 8 hours.
- Callout box above the red segment: **"Shredder vast"** (shredder jammed/stuck) with an arrow pointing down-left into the red segment.
- **Extruder** bar directly below: green labelled **"1200kg/hr"** at the left, then a **red segment vertically aligned with the shredder's red segment** (extruder also stopped), then green labelled **"1200kg/hr"** for the rest of the 8 hours.
- Yellow note box to the right of both bars:
  - **"WEL Stilstand"** (IS downtime)
  - **"GEEN slow running"** (NOT slow running)
- Interpretation as drawn: shredder jams, the extruder is stopped for the same window, then both resume at full budget speed. The lost window is booked as stilstand (downtime), not slow running.

### Panel 2 (bottom)

- **Shredder** bar: green, then a **red segment** (same position as panel 1), callout **"Shredder vast"** with arrow into the red segment, then green.
- **Extruder** bar: green labelled **"1200kg/hr"**, then — aligned with the shredder stop — a segment that is **hatched over by hand in blue pen** with the handwritten annotation **"storing"** (fault/malfunction) written above it, then green labelled **"1200kg/hr"**.
- X-axis labels: **"1200kg/hr"** at the far left under the axis, **"8uur"** at the right arrowhead.
- Yellow note box to the right (same as panel 1):
  - **"WEL Stilstand"**
  - **"GEEN slow running"**
- Yellow box at the bottom, with a long arrow pointing up to the hatched extruder segment:
  **"Wanneer de extruder snelheid wordt terug genomen is dit geen slow running"** (when the extruder speed is deliberately reduced, this is **not** slow running — "geen slow running" printed bold).
- Interpretation as drawn: if the extruder is slowed down / throttled back because of a fault elsewhere (here: shredder vast), that reduced-output window still counts as **stilstand**, not slow running. The handwritten "storing" + hatching marks the throttled window on the printed slide.

### Footer

- **"Budget snelheid is 1200 kg/hr"** — the budget (target) line speed for this extruder line.

---

## Source 2: Slow_running_2.pdf — "Wat is dan Slow Running?"

(So what IS slow running?)

Single chart panel plus a cause list. Legend bottom right: orange square = **"Slow running"**, red square = **"Stop"**, green square = **"Output/Snelheid"**.

### Chart

- One horizontal bar for **"Extruder"** spanning the full time axis to **"8uur"**.
- Y-axis reference at top left of the bar: **"1200kg/hr"** (the budget level).
- The bar is **green** for its full 8-hour length, labelled **"1000kg/hr"** — actual output.
- On top of the green bar, a thin **orange strip** fills the gap up to the 1200 kg/hr budget line for the full 8 hours.
- Callout box top right: **"Slow Running – 200kg per uur"** (slow running — 200 kg per hour) with an arrow pointing to the orange strip.
- Meaning as drawn: running the whole shift at 1000 kg/hr against a 1200 kg/hr budget = 200 kg/hr of slow running, continuously, with no stop.

### Definition box (yellow, centre)

> **"Slow running"**
> "Wat is de reden dat er niet meer gemaakt kan worden tijdens normale productie?"
> (What is the reason that no more can be produced during normal production?)

### "Mogelijke redenen:" (possible reasons) — bulleted list, verbatim

1. **"Shredder brengt niet genoeg (extruder silo leeg)"** — shredder does not deliver enough (extruder silo empty)
2. **"Maalmolen gaat continue in overload"** — granulator/grinding mill continuously goes into overload
3. **"Extruder filter wisseltijd te kort"** — extruder filter change interval too short
4. **"Extruder filter druk te hoog"** — extruder filter pressure too high
5. **"Extruder Max RPM"** — extruder at maximum RPM (screw speed maxed out, output ceiling reached)

### Footer

- **"Budget snelheid is 1200 kg/hr"**

---

## Combined decision logic (as taught by the two slides)

- **Stop / stilstand (downtime):** the extruder produces nothing for a window (red), OR the extruder is deliberately throttled back because of a storing (fault) elsewhere in the line. Both cases: **WEL stilstand, GEEN slow running.**
- **Slow running:** the line runs "normally" (no stop, no registered storing) but steady output is below the 1200 kg/hr budget speed. The shortfall (e.g. 1200 − 1000 = **200 kg per uur**) is the slow-running loss, and the question to answer is *why* full budget speed cannot be reached — see the five possible reasons above.

## Notes on the scans

- Both pages are photos of laminated/printed slides on binder rings; Slow_running_2.pdf shows ghosting/bleed-through of the first slide behind the printed content (mirrored "Extruder"/"Shredder" text and yellow boxes faintly visible). No extra legible content in the ghosting.
- The only handwriting is "storing" plus the pen hatching in panel 2 of Slow_running.pdf.
