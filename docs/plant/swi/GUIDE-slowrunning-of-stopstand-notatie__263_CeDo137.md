# Slowrunning of stopstand — how to log downtime/slowrunning (Cedo training sheet)

- **Source file:** `263_CeDo137.pdf`
- **Type:** Photo of a printed Cedo instruction/training sheet in the red ring binder. Title top: **"Slowrunning of stopstand"** (*Slowrunning vs. downtime — which is it?*). Three worked Gantt-style timeline examples showing how an operator should annotate a shift-report timeline. Colour code: **white outline bar = production plan**, **green bar = line actually running**, **red bar = stopped/downtime (storing / gepland onderhoud)**, **blue-hatched = Technische Dienst (maintenance) working**, **orange/yellow = transitional sub-activities (leegdraaien, vullen, overblazen)**.
- **HIGH VALUE for sim:** This is the ground-truth definition of the game's downtime taxonomy — it distinguishes **stopstand (full stop / storing)**, **gepland onderhoud (planned maintenance)**, and **slowrunning (line runs but cannot go faster)**, and gives real Cedo time constants for each. Directly relevant to the "can't escape your shift" survival loop and to how a shift report scores lost time.

## Example 1 — "Voorbeeld noteren storing (stopstand)" (how to log a breakdown/full stop)

Timeline axis marks: **17:00uur**, **18:00uur**, **18:45 uur**. Sub-marks **17:15uur** and **18:15**.

Bars (top→bottom):
1. Plan bar (white, outlined): **productie** → **totale tijdsduur storing incl. opstarten** (*total downtime duration incl. restart*) → **terug in productie** (*back in production*). The red "totale tijdsduur storing" span runs **17:00 → 18:45**.
2. Green run bar: line running (green) up to 17:00, then a gap (stopped) from 17:00 to 18:45, then green again (back in production after 18:45).
3. Red bar (below): **storing shredder 2** (*breakdown shredder 2*), spanning **17:00 → 18:15** (the actual fault window).
4. Sub-activity row (four coloured cells, ~17:15 → 18:45):
   - **compactor leegdraaien** (orange) — *empty out the compactor*
   - **extr stop** (white) — *extruder stop*
   - **vullen lijn** (light green) — *fill the line*
   - **vullen compactor en starten** (green) — *fill compactor and start up*

- **Span label:** **105 min** (the whole 17:00→18:45 window).
- **Notatie box (verbatim):** "**Storing shredder 2 incl vullen starten 1 3/4 uur (1,75 uur) = 105 min**" — i.e. a shredder-2 breakdown, *including* the refill-and-restart, is logged as **1¾ h = 105 min** total lost time. Key teaching point: you log the WHOLE window (fault + drain + refill + restart), not just the bare fault.

## Example 2 — "Leegdraaien voor normaal onderhoud voorbereiding en stopstand" (planned-maintenance run-down)

Timeline axis marks: **8:00uur**, **14:00uur**. Sub-marks **20 min** (left) and **30 min** (right).

Bars (top→bottom):
1. Plan bar: **productie** → **leegdraaien** (*run empty*) → **Technische Dienst** (blue-hatched, maintenance crew working) → **opstarten** (*start up*) → **terug in productie**. Technische Dienst span runs **8:00 → 14:00**.
2. Green run bar: running until leegdraaien, gap during maintenance, green again after opstarten.
3. Red bars: **overdracht** (*handover*) at each end (~20 min at start, ~30 min at end) flanking a long red **gepland onderhoud** (*planned maintenance*) span **8:00 → 14:00**.
- **Notatie box (verbatim):**
  - **Overdracht leegdraaien — 20 min**
  - **gepland onderhoud — 420 min**
  - **overdracht opstarten — 30 min**
- Teaching point: planned maintenance is logged as **20 + 420 + 30 min** with explicit **overdracht** (handover) blocks either side; 420 min = the 6-hour 8:00→14:00 TD window. Distinguishes *planned* red (onderhoud) from *unplanned* red (storing) in example 1.

## Example 3 — "Voorbeeld noteren Slowrunning, waarom kan ik niet harder draaien" (how to log slowrunning)

Timeline axis marks: **8:00uur, 10:00uur, 11:00uur, 12:00uur, 13:00uur**. Plan bar: **productie … Productie** (line never fully stops).

- Green run bar (line runs the WHOLE time — no red/stop), but annotated with reasons it couldn't go faster:
  - **Lijn draait maximaal** (*line running at max*)
  - **SR overblazen vocht** (orange cell, ~8:00–10:00) — *slowrunning: blowing off / venting moisture ("overblazen vocht")*
  - **VSS** (orange cell, ~12:00) — *[unsure: VSS = Vuilsnippersilo? matches the notatie below]*
  - **waarom kan de lijn niet harder** (*why can't the line run faster* — trailing green segment)
- **Notatie box (verbatim):**
  - **SR = 2 uur overblazen vocht** (*Slowrunning = 2 hours of moisture over-blowing/venting*)
  - **SR = 1 uur vuilsnippersilo brugvorming** (*Slowrunning = 1 hour vuilsnippersilo bridging/arch-forming*)
- Teaching point: **SR (slowrunning)** = line runs (green, no stop) but throughput is capped; operator must log the CAUSE and duration. Two real causes given: (1) 2 h spent **overblazen vocht** (excess moisture forcing the dryer/air to over-blow, limiting rate), (2) 1 h **vuilsnippersilo brugvorming** (dirty-snippet silo bridging/arching, starving feed). So **VSS** on the bar ≈ the vuilsnippersilo brugvorming event.

## Glossary captured
- **stopstand** = full stop / downtime. **storing** = breakdown (unplanned). **gepland onderhoud** = planned maintenance. **slowrunning (SR)** = running but rate-limited. **leegdraaien** = run the line empty (before maintenance/stop). **overdracht** = handover (leegdraaien / opstarten). **overblazen vocht** = over-blowing/venting moisture. **brugvorming** = bridging/arching in a silo. **Technische Dienst (TD)** = maintenance department. **opstarten** = start up. **compactor leegdraaien** / **vullen lijn** / **vullen compactor en starten** = the restart sub-steps after a stop.

## Open-question relevance
- **Downtime taxonomy for sim:** direct source. Time constants to reuse: shredder-2 storing incl restart = **105 min (1,75 h)**; planned-maintenance handover = **20 min in / 30 min out**, TD window **420 min**; slowrunning causes = **overblazen vocht (2 h)**, **vuilsnippersilo brugvorming (1 h)**.
- No numbered Q1–Q33 directly answered, but **confirms "shredder 2"** exists as a discrete stoppable unit and that **vuilsnippersilo brugvorming** is a real feed-starvation failure mode (feeds sim event design). VSS abbreviation appears (**[unsure: = vuilsnippersilo]**).
