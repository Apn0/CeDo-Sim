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

## E6. Open — start interlocks (not built)

**His words:** the screw starts only once *"the water at the front of the
extruder"*, *"the centrifuge ... to dry the pellets"* and *"the shaking sieve"*
are running. **Ruling:** record it, build it in a separate task. Also said, and
not understood yet: the start is the *"LED white ring button, the right one,
because the left one is for easy work"*. What the left button does is not known.
Asking him settles it.

## E7. Open — found while measuring, not ruled on

- **OFF cools the melt 0.5 °C/s** (`ExtruderModel._tick_off`), with no source.
  In the plant a restart 35 s to 3 min after a stop goes straight back to the
  old rpm (§E1). In the model, 35 s after the stop is pressed the melt is already
  under the green temperature and the start goes through PREHEAT.
- **The lump law** (`(torque - 95) x 5 g/s`) and the cake's `2500 psi/g` have no
  source either. Together they make the green threshold a knife edge: half a
  degree decided trip or no trip (audit doc §2).

---

# Line 1's wet tail — fourth session, same day (the fold after the mill)

Source: Arno, answering AskUserQuestion prompts on 2026-09-25 in the session of
worktree `clever-hypatia-945f15` (branch `claude/building-frame-suites`). These
are **recollections** (CLAIMED), not documents or photos. The archived drawing
`docs/plant/photos/line1_washing_flow_sketch_2026-08-28.png` agrees with them
in plan: two screws into the tank's end wall from two cyclones outside it, the
dewatering screw at the other end at 90°, an "L-R friction separator" across it,
two Kufferaths side by side in front of it.

He was asked which is wrong, the shell or line 1's layout, because line 1 fits
nowhere inside the 3D shell (`docs/audit/building_frame_2026-09-25.md` §7). He
answered with the layout, and asked to see the top-down view again once built.
Shown first: `docs/plant/renders/line1_wet_tail_as_built_2026_09_25.png` and
`shot_line1_plan_annotated_2026_09_25.png` (the line as it was on `main`).

## L1. The intake screws into the flotation tank (line 1 only)

**His words:** "those screws in real life would be going from the bottom of the
cyclone at a 30 degree angle downwards into the flotation tank. So part of it
would be outside of the tank, and then at some point it crosses the outer wall.
And then it goes in like 50 centimeters and then it exits into the water … the
bottom of the cyclone, which would be the top of the screw, would be above the
water level. And the total length of such a screw would be like two meters,
maybe one and a half meter." Asked to confirm the rule, he picked "Yes most of
your rule is correct but it's **only the rule for line one**, not for the other
lines." (The question put the cyclones "right beside the tank's inlet end".
Which part of the rule was not correct was not said.)

**Built:** `intrekschroef` (new catalog id, line 1 only): 1.75 m tube at 30°
down, inlet under the cyclone, discharge 0.5 m inside the tank's end rim just
above the water (4.05 m; water 4.0, rim 4.1). The cyclones stand just outside
the inlet end wall. Before: two 4.6 m flat `transport_screw`s ending 2–6 m
outside the tank.

## L2. Tank → dewatering screw: a 90° LEFT turn

**His words:** "after the flotation tank at the end to the dewatering screw is a
90 degree left turn". Confirmed: "the dewatering screw runs perpendicular to the
tank and turns left relative to the tank's direction of travel and also it
sticks out on the output side of the dewatering screw about 1.5 meters", then,
restating it, "sticking out one meter to the left of the material flow inside
the flotation tank". **Two figures, 1.5 m and 1 m; the later one (1.0 m) is
built.**

**First build:** the fold's +90 moved from the friction separator to the
dewatering screw, laid across the tank's discharge end, 1.0 m past its left side.

**Corrected from the top-down view (same day):** "the flotation tank and the
dewatering screw should not be overlapping … line up the left bottom corner of
the dewatering screw with the right bottom corner of the flotation tank and also
make the dewatering screw so that it is 1.5 meters sticking out compared to the
right top of the flotation tank and the left top of the dewatering screw." So
the screw stands BESIDE the tank's discharge end, its low end flush with the
tank's right side, its high end 1.5 m past the left side: 4.5 + 1.5 = **6.0 m**,
a line-1 variant (`dewater_screw_l1`, same model). Measured on the built line:
screw edge to tank end face 0.000 m, low end to tank side 0.000 m, high end past
the other side 1.500 m.

## L3. One L-R friction separator, two outlets, two Kufferaths

**His words:** "one separator; material enters in the middle on the back side
basically, then the screw that is rotating rapidly in there basically is
designed for [it]: the material that reaches the right side goes to the right,
material that reaches the left half goes to the left, so it's one separator
with two outputs, basically like a splitter … on the front side on the far left
and far right, that is where the material comes out of and goes into the
Kufferath." Earlier: the left exit is "a 90 degree right turn into the
Kufferath", the right exit "a 90 degree left turn". Asked how many Kufferaths:
**"Two sieves, one per outlet"**, and "each output of it has a separate
Kufferath and a separate MAS bak". Consistent with round 7 of 2026-09-24 ("one
separator feeds both sieves").

**Built:** `friction_sep_lr` (new catalog id, used by line 1 only): one housing
across the flow, hopper in the middle of its back, a spout at each far end of
its front. First build: the two Kufferaths inward of the spouts (x ±1.1 against
spouts at ±1.70).

**Corrected from the top-down view (same day):** "put those Kufferath machines
spaced out a bit wider, there should be about 1.5 meters of space between them,
so from the top right of the left one to the top left of the right one should be
1.5 meter distance horizontally, and then the center of the left Kufferath has
to line up with the center of the left MAS bak, and same centering for the right
side." Built: sieves and MAS baks at x ±1.65 (0.75 + half a 1.8 m sieve).
Measured: clear gap 1.500 m, sieve-to-bak centre offset 0.000 m both sides.
Asked next about the MAS dryers and blowers (still at ±2.5 / ±2.0): **"Also
centre the dryers."** Built: droger and blower at ±1.65 too; measured, all four
machines of each train on one line.

## L4. The Westa band and the shredder (line 1's head)

**His words, looking at the top-down render:** "the opzetband, it's okay; then
there is the Westa band, it is one meter too long; then also the shredder is too
far down on the image, it should be translated upwards so that the Westa band,
at the very top where it ends, sticks into the shredder hopper about 30
centimeters, because currently the material would fall next to the shredder."

**Built:** `PlaceableCatalog.WESTA_BAND_1_SHORTEN_M` = 1.0 m off the climb in
plan (same 30°, same inlet height; its run 5.757 → 4.757 m), and the shredder
moved up the leg so the lip ends `SHREDDER_1_HOPPER_OVERLAP_M` = 0.3 m inside the
hopper's flared collar (LINE_1_SEQ gap 0.957 → 2.257; the shredder and every
machine after it move 1.30 m). Measured with `dump_line1_head`: lip 0.300 m
inside the collar edge.

**Found, not his figure:** at 30° that lip was 7.37 m high, the hopper rim 9.0 m
(the 9 m `shredder_1` model's collar); before the change it was 7.95 m, over the
shredder's centre. So the band ended inside the hopper's side wall either way,
which the top-down view cannot show
(`docs/plant/renders/line1_head_side_view_2026_09_25.png`). Asked which is
wrong (the shredder's height, or the band's climb), he picked **"Westa should
climb steeper"**. Built: the plan run is now the given number
(`WESTA_BAND_1_RUN_M` = 4.757 m) and the lip clears the rim by one transfer drop;
the angle follows, **44.49°** (supersedes his 30° of 2026-09-17). Measured: lip
9.30 m, 0.300 m inside the collar edge
(`line1_head_side_view_v6_2026_09_25.png`).

## L5. The uitvoerband under shredder 1

**His words, from the top-down view:** the output conveyor "is going from bottom
to top while the rotors are going from left to right, so the material will be
falling from left to right where the rotors are, with a bit of spread … so that
conveyor should be going from right to left, starting with the center of the
conveyor aligned with the center of the two rotors, 10 centimeters to the right
of the rotors … then the length of the rotors, underneath which the conveyor is
as well, and then the conveyor extends from the end of the rotors to the left
further, 2.5 meters … it is a single conveyor, it runs from underneath the
shredder horizontally, then after it exits the shredder at a distance of 30
centimeters it goes in a slight incline upwards, about 20 degrees." Restated
back and confirmed ("Yes, that's it"), including that the shredder's own
bottom-to-top conveyor goes on line 1.

**Magnet:** "Over the climb, level" (25 cm above the deck at its closest point).

**What it discharges onto:** the receiving belt's centre, along the flow, at
"the center of the spread" of the material: "what is the speed of the conveyor,
what is the drop … using standard deviation, what is the minimum distance and the
maximum distance". Across, its tail "starting 30 centimeters before" the
uitvoerband's edge "as a safe zone".

**Built:**
- `uitvoerband_1` (new id, feed-belt model): 4.12 m flat at 0.956 m, 1.87 m at
  20°, a 5 cm tray; 6.04 m in plan; lip at 1.64 m; 0.15 m skirt boards (a new
  `guard_h` on the feed belt, 0.30 m everywhere else); 1.0 m/s, the speed of
  the transport belt it replaces.
- `shredder_1` on line 1 loses its built-in conveyor
  (`{"no_discharge_conveyor": true}`, re-applied when a saved line reloads);
  the same shredder on 3A/3B and 3C/6 keeps it.
- The receiving belt: centred 0.450 m past the discharge end, the mean throw
  from `tools/audit/line1_uitvoerband_throw.py` (1.0 m/s, 0.962 m drop, leaving
  at 20°, no air drag, so the particle mass cancels; ±2σ 0.262–0.650 m with an
  ASSUMED speed σ of 20 %); its tail 0.8 m across from the uitvoerband's
  centre line.
- The magnet, first build: level, lowest part 0.25 m over the lip, its 3.0 m
  length ALONG the uitvoerband. That put its scrap skip (the ContainerGuide
  marker) on top of the receiving belt. Asked about it, he corrected the magnet
  itself: it is a CROSS-belt magnet, "situated at about 75% the length of the
  outgoing belt from the shredder, starting at 0% on the right … that is
  basically the center line for the magnet", with the container on the bottom
  side of the image, the magnet belt's "underside moving in the direction of
  the bottom of the image, towards the skip and container below it". Built as
  `overband_magnet_l1` (line 1 only; the sort line's two magnets keep the shared
  model): the same magnet turned so its own belt runs ACROSS the uitvoerband,
  the scrap chute moved to the end the underside runs toward (its drums already
  turn that way), the skip slot under that end. Centre at 75.0 % of the 6.04 m
  (4.53 m from the right end), level, y 0.30: its lowest part over the belt
  0.25 m above the highest deck under it. Its near legs stand 0.04 m clear of
  the shredder's chamber wall (0.01 m of its base plates).
- **Corrected from the next render:** "the magnet 75% line was wrong, I
  miscalculated … take the coordinates of the top right of [the receiving belt],
  take the coordinates of the top left of the shredder, find out horizontally
  the center and use that as the center line for the magnet … and then also
  move the magnet towards the top of the image about 20 centimeters". And: "line
  up … the conveyor to which the output conveyor discharges with the conveyor
  after it, like a seamless transition between those, and move the rest of the
  line that follows accordingly so that all links up again." Built: magnet
  centre on the midpoint of the receiving belt's right edge and the shredder's
  hopper-collar face, 0.20 m toward the top, raised to keep 0.25 m over the
  deck under it (y 0.48); the receiving belt's discharge end on the drum-feed
  belt's tail, on one centre line, its deck 0.75 m, 5 cm above the drum-feed
  inlet (y 0.075). The mean throw was recomputed for that deck (0.887 m drop:
  0.434 m, ±2σ 0.252–0.627 m). Measured: magnet centre 0.000 m off the
  midpoint, 0.200 m toward the top; both belts centred on x −161.411; every
  machine from the drum-feed belt to the voorraad silo moved as one block,
  4.40 m toward the top (and 0.016 m sideways, the throw's change).

**Measured on the built line:** tail 0.100 m past the rotors' right end, end
2.500 m past their left end, centred on the rotor gap (0.000 m); receiving belt
centre 0.450 m past the end; its tail 0.29 m past the uitvoerband's guard edge
(0.33 m past its deck edge); magnet legs 0.10 m clear of the receiving belt and
0.62 m clear of the shredder.

## L6. The drum's stair, the wet street, and every pneumatic pipe

**His words, from the full render:** "the walkway next to the rotating drum is
oriented correctly. But the stairs currently seem to have their lowest step on
the right side of the image and the highest on the left. The highest point of
the stairs should sit on the right upward side of the walkway and the bottom
stair would be upwards of that, so it has to do a 90 degree turn." Then: "after
the drum that very next component needs to sit flush with the end of the drum,
and then the friction separators and mechanical dryers have to sit flush against
each other, and the friction separators have to sit flush against the right and
left side … to the component after the drum. And lastly for now, the blowers are
sitting slightly off center outwards from the mechanical dryer on the floor and
the motor is pointing outwards, so you have to flip one of the two blowers 180
degrees. Then for the pipelines, please use round smoothly curved pipelines for
the connections between the blowers and the cyclones, not only here but
everywhere in the CeDo simulator." He also asked what the "several thin
rectangles … going from the bottom right to the top left" in the renders are.

Asked (AskUserQuestion, with a side view showing the goot back to front):
- the goot: **"Yes, rebuild it that way"**: starts right under the drum's
  discharge, splits in two, each leg slopes down sideways into the inlet hopper
  of the friction separator beside it;
- "flush against each other": **"End to end, per side"**;
- how far outward the blowers stand: **"so that there is 30cm space between the
  output-chute of the dryer and the blower encasing"**;
- the dryer→blower duct (an L with a sharp corner): **"Curve those too"**.

**Built and measured** (`shot_line1_plan_*_2026_09_25_v10/v11`, and the new
wet-street plan and side views of `shot_line1_plan`):
- The thin rectangles are the overhead TL light fixtures (1.7 m, 9.6 m up, along
  the halls). Their projected positions matched the five in the first full render
  to a few pixels. Plan renders now hide them.
- **Stair:** its top at the walkway's upstream end on the outer side,
  descending away from the drum. It was also built from the model's floor, so on
  the lifted drum (VW_TROMMEL_LIFT_M) it hung 2.5 m up; it now hangs from the
  walkway and `extend_machine_legs` rebuilds it to the real floor (17 steps,
  4.6 m). The walkway's own legs reach the floor too. The outer railing opens
  where the stair lands; a railing closes the upstream end instead.
- **Scheidingsgoot:** found BACK TO FRONT (its high inlet at the far end,
  draining toward the drum, 1.2 m under the drum's lip). Rebuilt: inlet under
  the lip, flush against the drum shell's end (0.000 m), a 12° stem, two legs
  (28°) sideways over the separators' hoppers. His 2026-08-28 angles (30°, then
  60°) fall 1.37 m; only 0.59 m is left since the drum was lifted.
- **Separators:** flush against the goot's sides (0.000 m), their upstream ends
  at the drum's discharge-hood end. The right-hand one is mirrored so its motor
  stands outside, not in the goot.
- **Dryers:** each starts where its separator ends (0.000 m), same centre line.
- **Blowers:** each housing 0.300 m clear of its dryer's air-outlet stub (the
  "output chute" read as the stub the blower's suction connects to, the one
  part of the dryer that sticks out of its end), against the dryer's skid end;
  the left one turned 180° (both motors outward).
- **Pipes:** every blower→anything, cyclone→blower and dryer→blower duct is a
  round tube swept along a smooth curve, leaving the blower upward and arriving
  in the cyclone's inlet box or the blower's inlet eye.
- Everything after the blowers moved 5.57 m upstream with them.

**The friction separator's slope.** The side view showed its housing high at the
inlet (the goot's end) and low at the dryer, with its inlet hopper buried inside
the housing. Asked, he picked **"Low at inlet, rising"**, on every line (the
model is shared with 3B/3C). Built: `_m_friction`'s tube is tipped the other
way (it was the `PI/2 + tilt` sign mistake `_m_transport_screw` records), its
legs follow the rising underside; the hopper stands 0.38 m proud of the housing
and the goot's legs end 0.08 m above it.

## L7. The shared walkway, the tank beside the separators, the mill, J pipes

**His words, from revision 12:** "the walkway from the washing drum is actually
shared with the one from the flotation tank. So first step, remove the stairs and
walkway from the flotation tank. Second step, move the flotation tank so that
where the walkway used to be lines up perfectly with the walkway from the
washing drum. The walkway from the washing drum currently has very thin stairs,
I think. Make it wider towards the right of the image. And then lastly, with the
flotation tank placed at the new location: leftmost point of flotation tank to
rightmost point of mill: 6 meters. Center line vertically … line it up with the
mill. Move the mill up so that the center line of the mill lines up with the
flotation tank center line at the new location. Adjust the piping." And: the
pipes from the dryers' blowers "are entering the cyclones about halfway. Should be
about 85% up. And the curvature … looks more like parentheses. It should look
more like the letter J." (The transcript read "Leftmost point of flotation tank:
2. Rightmost point of mill: 6 meters"; read as "to".)

**Built and measured** (`shot_line1_plan_*_2026_09_25_v14`):
- The tank's own catwalk, posts and stair come off on line 1
  (`{"no_catwalk": true}`, re-applied on reload); the same tank elsewhere keeps
  them.
- Tank moved: its former catwalk's centre line on the drum walkway's centre line
  (measured 0.000 m). Lining up the tank-facing edges instead would have stood
  the tank's legs 0.07 m into the right-hand dryer's skid; it clears the dryer by
  0.049 m. It now lies north of the separators and dryers, its discharge end
  level with the drum's end.
- Tank's west end 6.000 m from the mill's east end (measured). Its westmost
  point is its box face (4.5 m from its centre), not the rim (4.32).
- Mill on the tank's centre line (0.000 m), moved 4.905 m north with its two
  cyclones and two blowers. A new SEQ key, `shift_x`, moves a main-line machine
  sideways without turning it into a branch, so the mill still merges and splits
  the two trains.
- The tank's inlet cyclones and screws moved with it (same rule as L1).
- Stair 1.2 m wide (was 0.76). **1.2 m is my figure, not his.** First grown
  toward the right with the walkway 0.44 m longer there; then, from revision 14:
  **"right side of dewatering screw should be aligned against the left side of
  the stairs to the washing drum"**. The stair now leaves the walkway 1.679 m
  past the drum's centre (`VW_TROMMEL_STAIR_Z_M`), the walkway is back to its
  length, and the railing opens where the stair lands. Measured: screw's right
  side to the stair's left side 0.000 m (`_2026_09_25_v15`). The tank's
  reject-container floor marker (ContainerGuide, 5.6 m past its outlet end)
  now lies partly under the stair's foot.
- Cyclone inlet at 85 % of the barrel (was 65 %), on every cyclone; the duct
  aims at it (`cyclone_inlet_local`). The MachineFlow port is unchanged.
- Blower → cyclone ducts shaped like a J: straight up out of the blower, one
  bend at the top (radius half the level distance), a level run, a short
  straight into the inlet. Dryer → blower and cyclone → blower keep a smooth
  curve.
- In the render, 17 machine legs are hidden (the drum, the corner chute, the
  tank's inlet cyclones): at his line-1 start those spots sit on the building
  shell's own surface 1.0–1.6 m up. The plan tool now reports each hidden leg
  and what it hits. Part of the known "line 1 fits nowhere in this shell".

## L8. Open

- **The separator → dryer glijgoot runs uphill.** The separator discharges at
  its high end (~1.7 m); the dryer's inlet is on its top (2.77 m).
- **The pre-mill cyclones stand beside the mill, not on it** (on 4.6 m legs,
  0.2 m short of its upstream face), though the SEQ comment says "ON the mill".
- **The cyclone's flow port is 1.6 m under its inlet box** (0.8·size.y = 2.4 m
  vs 4.02 m). The ducts use the box; the port steers the flow linker and was
  left alone.
- **Heights of the L-R separator.** Nothing here gives the separator's height or
  how the dewatering screw (discharging at ~5.4 m) feeds it. Built: separator on the floor,
  housing raised so its spouts fall into the Kufferaths; a 2.7 m chute from the
  screw down into its hopper.
- **The MAS trains** after the Kufferaths are one per side (bak, dryer, blower),
  now centred on their Kufferaths (L3). The 2026-08-28 drawing shows ONE
  "heather thing" under both Kufferaths; he said "a separate MAS bak" per side.
  Not asked further.
- **Lines 3B and 3C** also have an "L-R" friction separator (3B's "throws
  material both ways", L3C.13). They still use the end-fed `friction_sep`
  model. Whether his description applies to them was not asked.
- **Line 1 in the building shell.** At his line-1 start the line still crosses
  the shell (`docs/audit/building_frame_2026-09-25.md` §7): 17 legs stop on the
  shell's surface in the render.
