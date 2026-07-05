# Training slide — Verschil tussen Stilstand (Downtime) en Slow Running

- **Source file:** `346_CeDo45.pdf`
- **Type:** Training presentation slide, co-branded **CeDo** (logo bottom-left) and **Newton** (logo bottom-right). Part of the slow-running / stilstand training deck (companions: `TRAIN-slow-running-definitie-oorzaken__249_CeDo46.md`, `TRAIN-slow-running-vs-stilstand-titleslide__250_CeDo44.md`, `GUIDE-slowrunning-of-stopstand-notatie__263_CeDo137.md`).
- **No SWI id / date.**

## Title
**"Wat is het Verschil tussen Stilstand (Downtime) en Slow Running"** *(What is the difference between Downtime and Slow Running.)*

## Diagram (two stacked Gantt-style timelines, X-axis = 8 uur / 8 hours)

### Top example
- Two bars: **Shredder** (top) and **Extruder** (bottom), both green across the 8-hour shift with a **red block in the middle**.
- Callout on shredder bar: **"Shredder vast"** *(shredder jammed/stuck)*.
- Extruder bar labelled **1200 kg/hr** on both green segments (before and after the red block).
- Right-side yellow box: **"WEL Stilstand • GEEN slow running"** *(This IS downtime, NOT slow running.)*
- Meaning: shredder jams → both machines fully stop (red) → clean full-stop = **stilstand**, not slow running. Output resumes at full 1200 kg/hr after.

### Bottom example
- Same Shredder bar with red block + **"Shredder vast"** callout.
- Extruder bar: **1200 kg/hr** green segments, but the middle section is a **hand-hatched blue box** with handwritten **"storing"** (fault) over it — i.e. the extruder was *slowed* rather than fully stopped.
- Y-axis start also labelled **1200 kg/hr**.
- Right-side yellow box: **"WEL Stilstand • GEEN slow running"**.
- Bottom yellow callout (arrow to the hatched box): **"Wanneer de extruder snelheid wordt teruggenomen is dit geen slow running"** *(When the extruder speed is reduced [in response to a fault], this is NOT slow running.)*

## Legend
- **Red = Stop**
- **Green = Output/Snelheid** (output/speed)

## Footer (verbatim)
**"Budget snelheid is 1200 kg/hr"** *(Budget speed is 1200 kg/hr.)*

## Answers to open questions
- **Q21 (which line has the 1200 kg/hr budget?):** The **budget snelheid (target throughput) is 1200 kg/hr** for the extruder line in this training. Not tied to a specific line number on this slide — it's stated as *the* budget speed for the extruder in the slow-running curriculum. (Note this is a target/budget, distinct from the live snapshots: CeDo4 photo = 1082 kg/h actual, CeDo7 lijn 3B = ~488 kg/h.)
- **Q20 (slow-running remedies / definitions):** Key definition captured — **reducing extruder speed deliberately (e.g. because the shredder is jammed upstream, "storing") is NOT counted as "slow running."** Slow running is specifically running below budget for other reasons; a controlled speed-take-back or a full stop (stilstand) are separate categories. This distinction drives the OEE/notation logic (see CeDo137 notatie guide).

## Notes for sim
- Core KPI anchor: **budget = 1200 kg/hr**. Sim scoring should distinguish three states — full **Stop (Stilstand)** [red], reduced-speed-due-to-upstream-fault [not penalized as slow running], and genuine **slow running** [below budget without cause]. Green bar = at/above budget output.
- Reinforces the "can't-escape-your-shift" framing: an 8-hour shift bar where every red/reduced segment is tracked and categorized.
