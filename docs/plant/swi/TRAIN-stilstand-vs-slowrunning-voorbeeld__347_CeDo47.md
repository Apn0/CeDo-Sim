# Training slide — "Voorbeeld" Stilstand vs Slow Running (with slow-running case)

- **Source file:** `347_CeDo47.pdf`
- **Type:** Training presentation slide, **CeDo** + **Newton** co-branded. Direct sequel to `TRAIN-stilstand-vs-slowrunning-1200kgh__346_CeDo45.md`; this one adds the **yellow "Slow running"** category to the legend.
- **No SWI id / date.**

## Title
**"Voorbeeld"** *(Example)*

## Diagram (two stacked Gantt timelines, X-axis = 8 uur)

### Top example
- **Shredder** bar: green with a **red block** in the middle; callout **"Shredder vast"** *(shredder jammed)*.
- **Extruder** bar: green, **1000 kg/hr** labelled on both segments, a **red block** aligned with the shredder jam, AND a thin **yellow strip along the top** of the green running segments with callout **"Slow Running"**.
- Right yellow box: **"Stilstand (Shredder) • Slow Running (kan andere redenen hebben dan shredder)"** *(Downtime (shredder) • Slow running (can have reasons other than the shredder)).*
- Meaning: the red block = Stilstand caused by shredder; the yellow strip = Slow Running, running at **1000 kg/hr instead of the 1200 kg/hr budget** — a genuine slow-running loss that can have causes unrelated to the shredder.

### Bottom example
- **Shredder** bar: green + red block + **"Shredder vast"**.
- **Extruder** bar: green segments at **1000 kg/hr**, with a **white notched gap** (step-down) in the middle and yellow slow-running strips; Y-axis start labelled **1200 kg/hr**.
- Callout (arrow to the white notch): **"Dit is GEEN Slow Running"** *(This is NOT slow running)* — the deliberate step-down / gap aligned with the shredder stop is downtime, not slow running.
- Right yellow box: same **"Stilstand (Shredder) • Slow Running (kan andere redenen hebben dan shredder)"**.

## Legend
- **Yellow = Slow running**
- **Red = Stop**
- **Green = Output/Snelheid**

## Footer
**"Budget snelheid is 1200 kg/hr"**

## Answers to open questions
- **Q20 (slow-running definition/remedies):** Definitive category model:
  - **Green** = running at/above budget (Output/Snelheid).
  - **Yellow (Slow Running)** = running **below the 1200 kg/hr budget** (here 1000 kg/hr) for reasons that **can be other than the shredder** ("kan andere redenen hebben dan shredder").
  - **Red (Stop / Stilstand)** = full stop, e.g. shredder jam.
  - A deliberate speed take-back / gap that mirrors an upstream stop is **NOT** slow running ("Dit is GEEN Slow Running").
- **Q21 (1200 kg/hr budget):** Reconfirmed — **budget snelheid = 1200 kg/hr**; running at 1000 kg/hr is the illustrative slow-running example (a ~200 kg/hr / ~17 % shortfall).

## Notes for sim
- Completes the OEE state machine for the sim: three colour-coded states (Green=on-budget, Yellow=slow-running below 1200, Red=stopped) plus the special "not slow running" exemption when a reduction is caused by an upstream stop. Slow running is the sneaky loss the operator is graded on because it "kan andere redenen hebben."
