# Operator rulings — 2026-09-25 (the die plate against output)

Source: Arno, answering AskUserQuestion prompts in the Claude session of
2026-09-25 (worktree `unruffled-keller-219387`, stacked on
`claude/mystifying-chandrasekhar-7a250b` at `6b28207`). These are **choices
and recollections, not documents or photos**. Cite them as such (CLAUDE.md
Rule 1 accepts "explicit approval"; this is that). Where an answer set a law in
code, the code cites this file.

It continues `docs/audit/extruder_screw_die_plate_2026-09-24.md` §5, "the open
model-form question". The fix, the gate and the measurements are in §10 of that
file.

## 1. What was asked, and what he was shown first

The June-2023 WinCC trends (`src/data/plant/trends/3a_*.json`, `3b_*.json`)
show the kopdruk (`MD_vor_SF2`, before the kopfilter) flat with output.
`tools/audit/fit_kopdruk_vs_output.py` gives these fits:

| line | pairs | log kopdruk ~ log output | log output ~ log rpm |
|---|---|---|---|
| 3A | 648 | exponent −0.129, R² 0.037 | 0.851, R² 0.775 |
| 3B | 719 | exponent 0.007, R² 0.000 | 1.013, R² 0.915 |

Both extruder models made the die plate proportional to output. The questions:
why is the plant flat, what should the MFI estimate key on, and does
ExtruderModel get the same form? Two facts went into the first question:

- **No melt pump on 3A or 3B.** `operator_rulings_2026-08-31.md` §1 records
  it: "line three c and six both have a melt pump … [1, 3A, 3B] have no melt
  pump". So "the melt pump holds the pressure" was not the easy answer the
  task prompt assumed. One contradiction stays open: on 2026-09-24 he put "the
  MPU or melt pump" upstream of the kopfilter (`operator_rulings_2026-09-24.md`
  §2), and `ExtruderModel`'s line-order comment carries it. He was not asked
  again this session. See §5.
- **The melt runs hotter at higher output.** On the same pairs the melt before
  the meltfilter rises 22.4 °C per ln-unit of output on 3B (R² 0.54) and
  10.4 °C on 3A (R² 0.45). A two-variable fit of log kopdruk on log output and
  melt temperature still explains only 5–6 % of the variance (R² 0.051 / 0.062).
  The kopdruk moves more from day to day than with output (3A shift medians
  step from 139 to 154–172 bar on 2023-06-26 afternoon).

## 2. The answers

**Q1, why the kopdruk is flat.** Verbatim, typos kept:

> "operator-specific, could even be a test experiment from the office to run
> without head fitters inzstalled"

Reading: the flat kopdruk is how particular operators ran the line, and the
June-2023 window may be an office test with **no head filters installed**. The
trend is therefore not evidence of a die law. It is a band the model should stay
inside, not a curve to fit. If no pack was installed, `MD_vor_SF2` read the die
plate directly, with no pack dP on top.

**CLAIMED, not VERIFIED.** The data cannot settle it (§3). What would: the
production or process-engineering record for 2023-06-19..28 saying whether the
3A/3B kopfilter packs were in, or a kopdruk export from an ordinary production
week to compare against this one.

**Q2, what the MFI estimate should key on.** Verbatim: *"leave as low-priority
for the beta version"*. The MFI soft sensor is not redesigned now. The one
change it gets is the exponent that keeps it consistent with the new die law
(Q4 below; he accepted that option's text, which said so).

**Q3, whether ExtruderModel gets the new form.** He chose *"Both models
(Recommended)"*: "One die plate, one law, so the BluPort and the Quality
terminal can't show two different die pressures for one line."

**Q4, which law** (a follow-up, because Q1–Q3 did not fix one). He was shown
the finding in §4 first, then chose *"P ∝ Q^0.35 (Recommended)"*. The option
read: *"Textbook die law: pressure follows the flow through the die (the melt's
own flow index 0.35, a heuristic) and melt temp, not screw rpm … MfiProxy gets
only the matching exponent, so MFI stops moving with output (3A nominal
1.42→1.31, still ACCEPT)."*

## 3. What the data can and cannot say about the head filters

An installed pack that is changed "1x per dienst minimaal" (FORM-008 row 27)
should leave a sawtooth: kopdruk climbing through a shift and dropping at the
change. Measured on the kopdruk curves with `tools/audit/fit_kopdruk_vs_output.py`
(the second half of its output reproduces every number in §1, §3 and §4):

- The curves are **medians per ~6-minute bucket** (`downsample` field: 2000
  buckets over the span). Anything faster than that is gone.
- There are **161 (3A) and 129 (3B) drops of ≥ 8 bar within 15 min** over nine
  days, about 15 a day. That is far more than three pack changes a day, so the
  drops are something else (rate changes, laserfilter cycles, stops).
- The 8-hour shift slopes come out both ways: median +0.39 bar/h on 3A (p10
  −2.44, p90 +2.81, 26 shifts) and +0.77 on 3B (p10 −5.94, p90 +4.57, 25
  shifts). A pack loading at the HeadFilter model's 1.44 bar/h would rise in
  every shift.

So the trend neither confirms nor rules out packs. That is why §2 labels the
answer CLAIMED.

## 4. The finding shown before Q4: the gap was the probe, not the law

The "open question" rested on `test_screw_die_plate_bar`'s ungated info line:
3B at 534 / 799 / 1263 kg/h → 96.0 / 143.7 / 227.1 bar. That probe held the
screw at **110 rpm while the output more than doubled**. The plant does not do
that. Pairing each output sample with the nearest main-motor sample (within
400 s, running pairs only) gives the median rpm at each output:

| line | output band low / p50 / high | plant rpm there |
|---|---|---|
| 3A | 595 / 908 / 1082 kg/h | 60 / 88 / 110 |
| 3B | 534 / 799 / 1263 kg/h | 60 / 80 / 120 |

The old screw law was linear in Q with the viscosity taken at the SCREW's shear
rate. Run at the plant's rpm per output, scaled onto the profile's
`rpm_nominal`, it read 3A 111.6 / 128.2 / 128.4 bar and 3B 120.2 / 143.7 /
170.0 bar (reproduced by putting the old law back into the new suite, mutation
M1 in the audit doc §10.5). The trend's kopdruk bands are 3A 103–173 and 3B 106–166 (p5–p95).
Because η(screw) ∝ rpm^(n−1) and Q ∝ rpm, that law was already roughly Q^0.35
along the plant's own path. It rose linearly only when rpm was held fixed.

## 5. Left open

- **Melt pump on 3A/3B.** 2026-08-31 says none. 2026-09-24's line order
  (kopfilter → "MPU or melt pump" → laserfilter) says there is one. Not asked
  again. If 3A/3B do have one, a pressure-controlled pump is a third
  explanation for the flat kopdruk.
- **The profiles' rpm is not the rpm at the nominal output.**
  `ExtruderScrew.PROFILES` pairs the rpm curve's own p50 (3A 95, 3B 110) with
  the output curve's own p50 (908 / 799 kg/h). Paired, the plant turns 88 / 80
  rpm at those outputs. The two p50s were taken independently. The gate in
  `test_screw_die_plate_bar` §D scales the plant's rpm by its ratio for that
  reason. The profile is unchanged.
- **The MFI's temperature sign.** `MfiProxy` divides by η(T), so a hotter melt
  at the same pressure and output reads a HIGHER MFI. A lab MFI is measured at a
  fixed 190 °C and would read that melt as stiffer. Offered as the "material
  only" option in Q2; left for the beta with the rest of the MFI.

---

# Sorteerlijn 3A/3B — second session, same day (the sort line's wiring)

Source: Arno, answering one AskUserQuestion batch in the Claude session of
2026-09-25 (worktree `wonderful-euclid-80a5da`, branch
`claude/unruffled-vaughan-c64987`). These are **choices, not documents or
photos**. The option he picked is quoted as he saw it. What he was shown first
is listed under each answer, so the choice can be read against it.

The fix they settle, the guard, and the before/after graphs are in
`docs/audit/sort_line_topology_2026-09-25.md`.

## S1. The two sorters of a lane run in series

**Picked:** "Series per lane (Recommended)": Titech 1 → Titech 2 on one lane,
Tomra 1 → Tomra 2 on the other, so every flake is scanned twice.

Shown first:

- four units, named "Titech 1 en 2" and "Tomra 1 en 2" in SWI-015 p5 steps
  18–19;
- two lanes: the SOP sends the film to "beide sorteerlijnen" with button
  2040/2035 (`hmi_reference.md` §21);
- CEDO.xlsx's loss cascade, 4300 → ×0.7 → 3010 → ×0.7 → 2107 kg/h
  (`misc_sources.md` §2e), which reads as two stages in series.

The alternatives offered were parallel within a lane and crossed stages
(stage 1 = Titech 1 + Tomra 1, the lanes merge, then stage 2).

In code: streams `"titech"` / `"tomra"` on `LINE_SORT_SEQ` entries 9, 11, 12
and 10, 13, 14, which chain each lane head to tail.

## S2. The reject belts run to the balenpers

**Picked:** "Reject belt → bale press": the reject belts carry the removed
fraction to the balenpers in Hal 8.

Shown first: in the sim a sorter's reject leaves as a counted loss
(`LineFlow.poly_rejected`) and no belt carries it, so the two reject belts
leave the flow graph whatever the answer.

In code: `{"flow": false}` on entries 15 and 16. They are placed and are not
flow nodes. The balenpers leg is recorded here and not modelled. It would
need a second (reject) output on the sorter node.

Consistent with, not proof of: the bunker HMI's "Pers alleen" feed mode
(`hmi_reference.md` §22), `floor_plan_edits.md` (balenpers at the east end of
sorteerlijn 3, "possible downstream of sorted fraction - ask operator"), and
CEDO.xlsx's "16 reject → 48 balen".

## S3. Deferred: "lets discuss the sorting line tomorrow"

He gave that answer to both of these. Nothing was changed for either.

- **The trilzeef.** His own notes (`misc_sources.md` §1b) say the trilzeef
  keeps shaking so film "goes through Titech/Tomra 1+2 → Shredder 2". The sort
  macro has had no trilzeef since `9d16514` (2026-08-16). Before that commit it
  had two, one per lane, at x ±2.5. Open: whether each lane has one, and where.
  `LineFlow._PACK_UP_ORDER` already names a trilzeef.
- **Tomra's model.** `tomra_sort` has no MachineFlow profile, so it defaults
  to `process = "convey"` and the Tomra lane passes film unsorted. Titech
  removes 60 % of "other" polymer and 20 % of HDPE (sim constants; no source
  is recorded).

Also for that discussion (found while measuring, not asked):

- The macro's geometry does not match its flow. The opzetband discharges 6 m
  past shredder 1. The incline tops sit 6 m above the sorter inlets. The
  accept conveyor and the long transfer are main entries, so their `"z"` is
  never read, and they stand under the sorter lanes.
- The split belt is the intake's `switch_belt` (it jogs ±1.5 m toward VSS
  3A/3B), not a model of the 2040/2035 diverter.

---

# Extruder start, rpm setpoint, green button — third session, same day

Answers the operator gave by AskUserQuestion on 2026-09-25, in the session that
reproduced the warm-restart 318-bar trip
(`docs/audit/extruder_warm_restart_2026-09-25.md`). They are **recollections**
(CLAIMED), not documents. Where the plant's own WinCC archive speaks to the same
point it is quoted beside them, as VERIFIED with its source. Where the two
disagree, both are written down and the ruling says which one the model follows.

## E1. How an extruder start works

**Ruling (his words, corrected in the same session):** a start ramps the screw
to the rpm SETPOINT the operator left; the setpoint does not change on a stop.
*"When it then stops and gets restarted, it will ramp up to that 80. It will not
be 80 instantly."* 60 rpm is the lowest value that can be set. It is also the
remedy after a 318-bar trip: at 100 rpm *"as it ramps up, it reaches the 318
plus bar again ... So you can put it at 60 RPM. And then hope that it is able to
start."*

A first reading of his first answer ("the minimum value possible to set 60 rpm
... then that's it basically extruder is running at 60 rpm") built "every start
goes to 60". He rejected that: *"It is not, if you push the button, it always
goes to 60 ... That's not how operating works."* Commit `72bf069` carries the
wrong reading. The commit after it carries the ruling.

**VERIFIED, EREMA Archivspeicher, raw ~5 s export** (`F:/Citizen/Documents/CeDo`,
"Gegevens extruder 3A/3B / Snelheid hoofdmotor", the files
`tools/audit/fit_stop_load_vs_rpm.py` reads; 126 starts from 0 rpm, the reading
20 s after the last 0-rpm sample):

| where the start went | 3A | 3B | median stop before it |
|---|---|---|---|
| 60 rpm | 10 | 23 | 1.3 h (3A), 16 min (3B) |
| back to the rpm it ran at before the stop (±3) | 11 | 26 | 3 min (3A), 35 s (3B) |
| elsewhere (often stopped again at once) | 11 | 45 | 20–35 s |

That fits his account: the drive goes back to its setpoint, and after a long
stop (or trouble) the operator had set 60. No reading between 0 and 60 rpm
appears in either the raw export or the 6-minute trend medians
(`src/data/plant/trends/3{a,b}_snelheid_hoofdmotor.json`, 2023-06-19..28),
which agrees with 60 as the floor.

## E2. A new extruder's setpoint is 60

**Ruling:** a freshly placed extruder starts with its rpm setpoint at 60, not at
nominal. After that it keeps whatever the player sets. He was told: *"a restart
at 110 on a cold melt can still trip"*. He chose this option knowing that.

The model does not save the setpoint, so a reloaded world starts at 60 too.

## E3. The green button waits until the screw passes no lumps

**Ruling:** the preheat-ready ("green") temperature is derived from the 95 %
lump-passthrough torque as well as from the 110 % torque trip, with the same 25 %
margin: **201.875 °C** on 3A/3B (13.1 °C under 215), was 196.25 °C. At 196.25 °C
the screw sits at 97.5 % torque. That is above the point where un-melted lumps
start passing to the laserfilter. Measured: a 60-rpm restart pressed the moment
the block turned green passed 3.4 g/s of lumps and tripped 318 bar 3.3 s later.

## E4. The start ramp: 3 s to 60 rpm (his number kept against the archive)

**Ruling:** keep *"about two and a half to three seconds ... let's say three
seconds to that 60 rpm"*. The model ramps at 20 rpm/s. The rate above 60 rpm is a
modelling choice, not his: he gave no number for it.

**Unresolved difference, recorded:** in the raw archive, only 1 of the 33 starts
that land on 60 already reads 60 at the first sample (samples every ~5 s). The
first readings spread evenly over 1–59 rpm. A 3 s ramp would put about 40 % at 60
by the first sample, so the archive points at about 5 s. He was shown this and
chose 3 s.

## E5. The player sets the rpm, per line, on the HMI

**Ruling:** the player sets the rpm, and there is a line choice on the one
all-lines extruder HMI ("add a line choice now"). Before this, the web HMI's
extruder channels went to the first extruder the scene tree listed. The
touchscreen fallback had no rpm field. So no line but one could be set, and a
tripped line could not be dropped to 60. The rule covers all extruders (1, 3A,
3B, 3C, 6).

## E6. Start interlocks — settled in the fourth session (§I1-§I10 below)

**His words:** the screw starts only once *"the water at the front of the
extruder"*, *"the centrifuge ... to dry the pellets"* and *"the shaking sieve"*
are running. **Ruling:** record it, build it in a separate task. Also said, and
not understood yet: the start is the *"LED white ring button, the right one,
because the left one is for easy work"*. What the left button does is not known.
Asking him settles it. **Asked and built the same day: §I1-§I10.** The left
button starts the PCU (§I8).

## E7. Open — found while measuring, not ruled on

- **OFF cools the melt 0.5 °C/s** (`ExtruderModel._tick_off`), with no source.
  In the plant a restart 35 s to 3 min after a stop goes straight back to the
  old rpm (§E1). In the model, 35 s after the stop is pressed the melt is already
  under the green temperature and the start goes through PREHEAT.
- **The lump law** (`(torque - 95) x 5 g/s`) and the cake's `2500 psi/g` have no
  source either. Together they make the green threshold a knife edge: half a
  degree decided trip or no trip (audit doc §2).

---

# Extruder start button and its natraject — fourth session, same day

Asked on 2026-09-25 with AskUserQuestion, in two rounds, after the code and
the plant docs had been searched. The build, the suite and the measurements
are in `docs/audit/extruder_start_interlock_2026-09-25.md`.

What was on the table before the first question:

- **No plant document lists the extruder's start conditions** (VERIFIED, by
  search of `docs/plant/`). SWI-042 p4 rows 19-20 say *"Nog SWI maken opstarten
  extruders"*. Line 1's SWI-012 p7-p8 is the only written start sequence, and
  it names no start condition.
- **The raw WinCC archive logs none of these machines** (VERIFIED).
  `F:/Citizen/Documents/CeDo/Gegevens extruder 3A|3B` hold screw speed and load,
  melt pressures and temperatures, output and the compactor. The 3C tag list
  (`Random Exports/3c_tags.xlsx`) covers the wash side only.
- In the docs **"trilzeef" is the sort-line screen**. The sieve after the
  pelletizer is the **ontwaterzeef** (`lijn_1_flow.md`, `lijn_3a_flow.md`,
  `lijn_3b_flow.md`). His "shaking sieve" was taken to be the ontwaterzeef, and
  he did not correct it.
- In the sim, only the barrel temperature could refuse a start. The line's
  start powered the pellet side and pushed material through the extruder
  whether or not it had been started (LineFlow and ExtruderModel never read
  each other).

Everything below is his recollection (CLAIMED), quoted where it matters. He
said himself: *"don't quote me on this because I might forget something here
and there"*.

## I1. The button runs safety checks first, and an alarm blocks it until reset

If a check fails, nothing starts: *"if the pelletizer head is not closed, the
lid, and locked securely, with the lever ... if you push the button, it will not
do anything, nothing will be started ... it will just immediately ring the
alarm"*. The operator puts it right and **resets the alarm**: *"That's
important. If you don't reset the alarm, still nothing's going to happen."*
Other checks he named: the extruder zones within a minimum and a maximum
temperature, and pressures at several measuring points (*"before the filter
after the filter"*). A failed check *"will sound an alarm. And it will show what
the problem is."* The limits are in the deep EREMA settings (*"advanced EREMA
settings"*), not on the overview pages and not in any data we have.

## I2. The start order

With every check passed (his best recollection):

1. the blower that carries the granulate from the centrifuge to the top of the
   weighing scale;
2. *"after a few seconds like when that blower is started up"*, the centrifuge;
3. *"if that's spinning"*, the sieve starts shaking;
4. the water to the pelletizer head;
5. the pelletizer's four knives;
6. *"probably in short sequence ... logically I would start the laser filter
   scraper first And then the extruder screw"*, and the vacuum pump.

Depending on the PCU belt's mode (auto, continuous, off, manual) it may also
start that belt and the dosing screw (*"I'm not sure"*). The fume hood is
probably running already. **Not the extruder's:** the pneumatic conveying after
the scale (the WISSEL station in the basement, out to the silos) is *"always
running"* and sits *"after the part where the PLC are responsible for the
extruder"*.

## I3. The ring

There are two white LED rings. The right one blinks through the start
sequence: *"for now we can do 0.5 seconds off ... 0.5 seconds on"* (he has the
exact ratio somewhere). *"when the extruder screw is starting to spin ... that
LED ring is solid white."* On a trip, for example the 318-320 bar laser-filter
pressure, *"the extruder screw obviously is stopped first"*. The ring blinks
again while the rest stops, *"about the same not exactly in reverse"*, and goes
off once everything stands.

## I4. Ruling on the sim: the extruder runs its natraject

He was asked who runs these machines, given that the line's start used to run
them. **Ruling: the extruder.** The extruder, its laser filter and the pellet
side run only when the extruder's sequence runs them. While the extruder is off
the silos fill (SWI-042 p4 §19).

## I5. Ruling on the sim: a natraject machine that stops trips the extruder

First answer: he was not in the technical department. An extruder CAN run with
the pelletizer head open, on some extruders only by bridging a safety sensor.
The shift leader decides that when the centrifuge or the sieve has a problem
that would take too long. The reason is that a PCU full of hot material cannot
sit for hours: *"like a hundred kilograms of material at like 115 degrees"* at
about 180 kW (*"a very rough guess"*). The strands then run into lump carts
under the die, emptied by forklift, until the PCU runs empty. **Ruling (second
round):** the extruder trips. The screw stops first, the alarm names the
machine, and the rest runs down with the ring blinking.

## I6. The alarm is reset on the HMI

Offered "E at the extruder", he refused: *"it can only be done via the HMI
because I can't press E in real life by looking at the extruder and then that
it would restart. That doesn't happen."*

## I7. The "natraject" setting

*"somewhere in the settings menu, you can ... either enable, which is actually
the default state ... I think they call it N-A-T-R-A-J, ECT"*: natraject, the
tail of the process. Disabled, *"it will not check whether those are running or
not. In fact, it will not even start them. But it will then start the
extruder."* It is not used: *"I think it was even not allowed to do it. And it
was a bit like hidden."* **Ruling:** the player can switch it on the extruder
panel, and it is ON by default.

## I8. The left button starts the PCU

*"the other LED ring is the one on the left and that's ... the one to start the
PCU"*: on or off, no blinking. It checks its own safeties (door closed, motor
amperage, optical sensors) and is separate from the extruder. A deep setting
can stop the PCU when an extruder failure stops the extruder. This settles
§E6's *"the left one is for easy work"*, most likely a transcription of "for
the PCU" (a reading, not his words).

## I9. HMI wishes, raised in the same answer (separate tasks, not built here)

- Closing an HMI with its X leaves the keyboard dead until an Alt+Tab /
  Shift+Tab dance. *"that is annoying and it has to be fixed."*
- The HMI screens should stay open in the world, like the real ones: a page
  left open is still open when you come back, readable from 3-5 m. They should
  be operated by aiming a centre dot while holding F (*"like in Star
  Citizen"*), and dropping tools moves from E to Q.

## I10. Built, and not built

Built (see the audit doc): the checks the sim can make, the start order, the
ring, the trip, the run-down, the HMI reset, the natraject switch, and the
extruder owning its LineFlow node and natraject.

Not built, and why:

- **The pelletizer lid and its lever.** The sim has no lid.
- **Zone and pressure limits.** The numbers are in the deep settings, and we
  have none.
- **The blower** has no machine in the sim. The weegschaal step stands for "up
  to the scale".
- **Water, then knives, as two steps.** The heetafslag is one LineFlow node, so
  it is one step.
- **The vacuum pump, the PCU belt and the dosing screw.** No run state in the
  sim, or *"not sure"*.
- **Running with the head open into lump carts.** A gameplay feature of its own.
- **The left (PCU) button.**
- **The ring as a physical button.** Where the two buttons sit on 3A/3B is not
  documented. The ring shows on the HMI and in the prompt.
- **Lines 3C and 6.** The 3C macro runs `extruder_screw`, which has no brain,
  so its pellet side still runs on the line's PLC. Line 6 has no macro.
