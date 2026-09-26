# Operator rulings — 2026-09-26 (the wash line's timing and the VSS dosing screw)

Source: Arno, answering AskUserQuestion prompts in the Claude session of
2026-09-26 (worktree `unruffled-keller-219387`). These are **choices and
recollections, not documents or photos**. Cite them as CLAIMED (CLAUDE.md Rule 1
accepts "explicit approval"; this is that). Where an answer sets a number in
code, the code cites this file and marks the number PLACEHOLDER until he
corrects it.

Other sessions may append to this file the same day: add a lettered section,
do not rewrite this one.

## W1. How it came up, and what the sim did (MEASURED)

The session was asked to re-derive `test_extruder_silo_feed_stop` S3 ("3B's
backlog waits in the VSS, not in the stopped dosing screw"; it allowed < 1.0 kg
into the stopped screw and measured 0.96–1.20 kg by tick phase,
`docs/audit/lineflow_set_process_2026-09-26.md` §6). The operator's reply
questioned the model underneath: on 3B material takes about 10 min from the
VSS dosing screw to the extruder silo, and a full VSS runs the line about
15 min.

Measured with `src/tests/probe_3b_residence.tscn` (Godot 4.7.2, 3B alone,
LineFlow ticked by hand at 0.1 s, isolated `APPDATA` on D:):

| | sim before this | operator |
|---|---|---|
| VSS → extruder silo, first kg (fed 950 kg/h) | **38.8 s** | ~10 min, revised to ~3 min (W3) |
| kg in the wash line while running at 950 kg/h | **9.6 kg** (0.6 in 14 machines, 9.0 on connectors) | — |
| a VSS holding 150 kg (the sim's "full"), no supply | empty in **15.0 s**, at 10 kg/s (36 000 kg/h) | ~15 min |

Why: every wash machine's MachineFlow `rate` is the 6 kg/s default
(21 600 kg/h) and the VSS's is 10 kg/s. Nothing in the line meters it to the
plant's ~800–1200 kg/h, and no machine holds material for longer than one
tick; the only delay is the connectors at `TRANSPORT_MPS` 1.3 m/s.

What the docs hold (search of `docs/`, `MachineFlow.gd`, `ProcessModel.gd`):
- VERIFIED: 3B extruder output p50 799 kg/h, p5–p95 534–1263
  (`docs/plant/trends_overview.md:39`, WinCC June 2023); FORM-008 VSS pressure
  3B full 7–9 bar, empty 2 bar (`docs/plant/checklist_3a_3b.md:43-46`);
  CEDO.xlsx "Doseerschroef VSS 50-100", no unit (`docs/plant/misc_sources.md:191`);
  SWI-042 p4 §19, the silos keep filling through the 30-min compactor warm-up.
- CLAIMED: line 3C "Doseer Silo → Extruder Silo ≈ 10 min (8–12)"
  (`src/sim/ProcessModel.gd:145-147`); a full PCU ~100 kg
  (`operator_rulings_2026-09-25.md`).
- Not documented anywhere: the VSS's volume, any wash machine's hold-up or
  residence, the 3A/3B extruder silo's capacity.

## W2. The answers

1. **A stopped dosing screw takes nothing more.** Asked how much may still
   enter M11a once the full extruder silo stops it: *"if it is full/blocked by
   non-rotating ... screw, then LOGICALLY no more material can enter"*, and
   when asked again, *"i told you in my last message"*. So: 0 kg. The ~1 kg
   S3 measured is a sim artifact: `vss_silo` and M11a are two nodes with a
   5.9 m / 4.5 s connector between them, while `lijn_3b_flow.md` has nothing
   between them (Vuilsnipper silo 3b → Doseerschroef M11a).
2. **Order: the wash line's timing first, S3 after.** (*"Do it first"*.) S3
   stays parked on frame time until then.
3. **Scope: all lines.**
4. **Plug flow.** When the meter starts feeding an empty line, *the first kg
   reaches the extruder silo after the line's transit time*; after the meter
   stops, the line keeps delivering for that time.
5. **The time sits mostly in the tanks, and the flotation tank holds most.**
   He picked the option "the flotation tank gets 2/3 of the tanks' time and the
   rafter 1/3" over an equal share.
6. **M11a's setting is screw rpm.** *"50-100 setting is rpm of the screw, at
   100 like 1800-2000kg/h"*. Restated as a law in the next question and not
   objected to: linear, 19 kg/h per rpm (100 rpm = 1900 kg/h, 50 rpm =
   950 kg/h); 3A's M11a the same.
7. **The setpoint is the operator's, on the HMI** (*"setpoint in HMI set by
   operator"*). A newly built line starts at **50 rpm = 950 kg/h**, and that is
   also the rate the sizes below are measured at.
8. **A full VSS = 15 min of M11a at 50 rpm** = 237.5 kg (the sim had 150 kg).
9. **The extruder silo: "15-20 min of feeding fills extruder silo"**, i.e. its
   100 % = 15–20 min at 950 kg/h = 238–317 kg (taken as 17.5 min = 277 kg; the
   sim had 150 kg).

## W3. The conflict, and his choice: the line holds less than 10 min

Answers 4, 9 and his §I11 recollection (*"114%, 120%"* when the silo overfills
with the compactor belt stopped) do not fit together with ~10 min in the line:
10 min of feed (158 kg at 950 kg/h) landing on a 277 kg silo reads ~157 %. He
was shown three ways out (keep both and accept ~155 %; a bigger silo; a line
that holds less) and chose **"line holds less"**: the silo stays at 15–20 min
of feed and the overshoot at 114–120 %, so the line holds 14–20 % of 17.5 min
= 2.45–3.5 min of feed. Built as **3 min** (117 %): the first kg reaches the
extruder silo ~3 min after M11a starts. This **replaces his first estimate of
~10 min**, which he gave before the sizes were on the table.

His arithmetic in the first answer, for the record: 1200 kg/h is 20 kg/min
(he wrote 33.3), so 10 min would have been 200 kg, not 333.

## W4. The rule as built (numbers PLACEHOLDER)

For every wash line, from its meter to its extruder silo, 3 min to the first kg:
- the connectors keep their geometry transit (1.3 m/s, as before);
- every machine that is not a tank holds 5 s (the 15 s in the question no
  longer fits in 3 min: on 3B seven such machines would hold 105 of the
  180 s, more than the tanks, against answer 5);
- the tanks hold the rest: the flotation tank 2/3, the other tanks share 1/3.

On 3B that is (connectors measured 38.2 s):

| machine | holds |
|---|---|
| M11a (transport_screw after the vuilsnippersilo) | 5 s |
| rafter | 1/3 of the tanks' time |
| ontwaterschroef (rafter's), frictiescheider 210, ontwaterschroef, frictiescheider L/R, mech. drogers 310/311, plasmaq | 5 s each |
| flotatietank | 2/3 of the tanks' time |
| connectors, blowers, cyclones | as before |

## W5. Scope after the last round: 3B now, the others later

Asked per line after W4:
- **3A: "3A differs"** (the option "3A's time is not 3 min or not split this
  way"; no detail given). 3A keeps its old timing, its VSS its 150 kg "full"
  (FORM-008 gives 3A's VSS other pressures than 3B's: full 12–14 bar against
  7–9), and its M11a its old rate, until he says how 3A differs.
- **Line 1: "Later"** (its meter is the shredder, §I13).
- **3C: "later"**, with its extruder-silo feed stop; the committed ≈ 10 min
  note is the starting point then.

Answer 1 (a stopped dosing screw takes nothing more) is physics, not a 3B
number, so it is built wherever the extruder silo's feed stop holds a screw fed
straight from a VSS: 3A and 3B.

## W6. The meter's "drive" slider: left as it is

A parallel session found the same day that LineFlow counts one HMI speed
setting more than once, and the operator ruled to keep that for machines in
general (*"don't touch the base"*, `docs/audit/hmi_rpm_rate_2026-09-26.md`).
On the meter it means (measured with `probe_3b_residence.tscn -- slider`, kg/h
over 60 s): the master rpm slider at 50 gives 950 kg/h and at 80 gives
1520 kg/h, as ruled, but the MACHINES screen's "drive" row at 50 halves that
again, to 475 kg/h, and while it stays at 50 the master at 100 rpm gives
950 kg/h. Asked whether the meter should get an exception (both sliders set
its rpm), he answered **"Leave it"**. The master rpm slider is the setpoint;
the "drive" row multiplies on top, as for every other machine.

## W7. Open

- **3A, line 1, 3C** (W5): how 3A differs, which of their machines are tanks,
  and what meters line 1 (§I13: its "dosing screw" is the shredder) and 3C (the
  doseersilo screws, 8/8/9 Hz on the L3C.1 photo).
- **The VSS's and the silos' overflow**: LineFlow's 250 kg overload e-stop was
  sized against the 150 kg "full" of both.
- **The pipes**: every connector moves at 1.3 m/s, pneumatic runs included
  (3B's 15 m plasmaq → tussenventilator pipe takes 12.4 s).
- **The VSS pressure in bar** (FORM-008, §I13) is still not modelled.
