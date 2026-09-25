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

# Transportbanden 3A/3B — fourth session, same day (the intake macro's head and conveyor 8)

Source: Arno, answering two AskUserQuestion rounds in the Claude session of
2026-09-25 (worktree `mystifying-franklin-db632a`, branch
`claude/focused-jackson-bff053`). The first round asked in terms Arno did not
recognise ("macro head", "C8/C9"). Arno asked for an explanation of both, got
it, and answered the reworded round. The answers are quoted as typed or
picked. They are **recollections and choices, not documents**.

The fix they settle, the guard and the before/after graphs are in
`docs/audit/intake_3a3b_topology_2026-09-25.md`.

## T1. The belt into shredder 2 is a plain conveyor, and shredder 2 is mill-like

**Asked:** where film should enter the Transportbanden 3A/3B section when it
is placed on its own. Shown first: in the plant the opzetband feeds shredder 1
on the sort line, and shredder 2 is fed by the sort line's long belt; the
macro's opzetband in front of shredder 2 was added 2026-06-14 (commit
`a3fa4b4`, "D4") with no source; today it skips shredder 2 and drops straight
onto the climb belt. Options: keep the opzetband as the section's feed point,
or leave it standing and let film enter at shredder 2.

**Answered (typed, not an option):** "the conveyor that is feeding into
Shredder 2 is actually not an offset band. Op Z band. … O P Z E T B A N D.
It is called Shredder 2, but it is actually more similar like uh, a mill on
the other lines. So it's just a conveyor that feeds it. And there is no bills
being placed anywhere on that conveyor."

Read as: the belt into shredder 2 is a plain conveyor, not an opzetband; no
bale is ever put on it; shredder 2 behaves like the mills on the other lines.

In code: `INTAKE_3A3B_SEQ` entry 0 is `transport_belt` (the id the sort line
uses for the same belt, `LINE_SORT_SEQ` 18), pinned into shredder 2. Nothing
was changed about how shredder 2 itself is modelled (MachineFlow process
`shred`); "more like a mill" is recorded here, not built.

## T2. Conveyor 8 forward to 9, reversed to 8.5 → U, and the U feeds nothing

**Picked:** "Yes, fix it now (Recommended)", on: "Wire conveyor 8 / 8.5 / U
as your notes describe, in this same change? Normal: conveyor 8 → conveyor 9.
Both VSSs full: conveyor 8 reverses → 8.5 → U, and the U feeds nothing (the
Merlo empties it)."

Shown first: the operator's own notes (`misc_sources.md` §1b) and the measured graph,
where conveyor 8 only ever fed 8.5, 8.5 fed conveyor 9, and the U got nothing
yet fed conveyor 9.

In code: the `overflow` stream on entries 11–12, which ends at the U-bay;
MachineFlow `no_outlet` on `u_bay`.

## T3. Found while measuring, not asked

- **The pack-up cascade does not match the operator's notes.** The notes: when both VSSs
  are FULL, "every conveyor up to the trilzeef pauses in 1s sequence from the
  bunker", the trilzeef keeps shaking, and the flakes still coming through
  shredder 2 go C8 (reversed) → 8.5 → U. `LineFlow._PACK_UP_ORDER` instead
  pauses C11, C10, C9, **C8.5 at 3 s, C8 at 4 s**, then C7 … C1, the trilzeef
  and the bunker. So in the sim the U can take at most a few seconds of flow
  (C8's reversal alone takes 2 + 2 s). Read from the code, not driven.
- **The geometry does not match the flow.** The feed conveyor discharges at
  0.8 m, 5.1 m from shredder 2's inlet at 5.1 m high; C8.5 stands beside C8's
  forward half, while the operator's notes put it "on one side of conveyor 8, and conveyor
  9 … on the other end". The pins make the flow right; the layout is the operator's pass.

---

# In-world HMI screens and interact keys — fifth session, same day

Source: Arno's request of 2026-09-25, relayed to the Claude session as a
written brief (worktree `inworld-hmi`, branch
`docs/inworld-hmi-survey-2026-09-25`), then four AskUserQuestion rounds. It is a **recollection of how the plant works, not a document
or a photo**. Everything in §H1 is labelled **CLAIMED** for that reason. The
"today in the sim" column is **VERIFIED**: each cell was read from the code
at `4c1fb12` and cites the file it was read from. The citations were re-checked against `main`
`256f828` (131 commits later) on the same day, and the line numbers are main's. The survey behind this section
is `docs/DESIGN_inworld_hmi_2026-09-25.md`. Nothing has been built yet.

## H1. The request (CLAIMED — operator recollection)

| # | what he said | what the sim does today (VERIFIED) |
|---|---|---|
| 1 | In the plant, if you open a page on an HMI (his example: the **PCU overview**) and walk away, **it is still open when you come back**. | Every open resets the page to the main menu: `HmiOverlay.open_for()` ends in `_show_screen(Screen.HOOFDMENU)` (`src/scenes/hud/HmiOverlay.gd:397`). All 11 non-relay panels share ONE overlay instance (`Hmi.gd:37-41`), so the page is not even per panel. The web pages reload the scope's start page on every open (`HmiWebOverlay.gd:154-156`). |
| 2 | You can **read the display from 3–5 m** away. | Nothing is drawn on the panel's screen. It is a flat emissive box, 0.49 × 0.315 m (`PlaceableCatalog._m_hmi`, `PlaceableCatalog.gd:6414`, material `_screen_mat` `:6383`). |
| 3 | In the sim you press **E**, get a **2D pop-up**, and have to **navigate to the right screen every time**. That is annoying. | Correct. The crosshair ray plus E calls `Hmi.crosshair_interact` → `_open_overlay` (`Hmi.gd:110-112, 124`), which opens a full-screen CanvasLayer (layer 45, `HmiOverlay.gd:338`) or a native WebView window (layer 46, `HmiWebOverlay.gd:141`). The mouse is freed, and walking stops while it is open (`PlayerController.gd:343-356`). |
| 4 | He wants the HMI **rendered in the world, on the panel's own screen**, with the page **kept per panel**, and **no 2D pop-up**. | There is no in-world screen of any kind in `src/`: no SubViewport on a mesh, no ViewportTexture, no `push_input`; `src/` searched for all three on 2026-09-25. |
| 5 | **Drop goes to Q**; E must stop dropping tools. | **Q already drops.** `hotbar_drop` is Q (`project.godot:402`), handled at `PlayerController.gd:1067-1071`. E ALSO drops, through each held tool's own `_unhandled_input` when the crosshair has no target: ShovelTool `:85`, WireCutter `:111`, BarcodeScanner, SocketWrench7, LineCouplerTool, LeafBlower, CabinProp, LabelItem, ChargingPlug, LPGTank (`docs/DESIGN_inworld_hmi_2026-09-25.md` §4). |
| 6 | **Hold F → "interact mode"**, as in Star Citizen: a **small centre dot** to aim with. Aiming at an HMI button **within arm's reach** and **clicking** operates it, straight from walking mode. | There is no hold-F. F is bound to four actions: `flashlight` on foot (`project.godot:140`), `forklift_lift_down` (`:180`), `build_lower` (`:257`) and `hose_advance_back` (`SettingsManager.gd:769`). The HUD crosshair is a fixed 5×5 dot (`HUD.gd:124-133`). The interact ray is 3.75 m (`PlayerController.gd:49`) and forwards only the collider, not a hit point (`:1179-1225`). |
| 7 | This also removes the **keyboard-focus bug** of the 2D overlay (tracked separately). | Not investigated here. The only focus handling in the HMI code is in `HmiWebOverlay.close()` (`:172-180`). HmiOverlay has no focus calls at all. |

## H2. Answers to the design questions

Asked with AskUserQuestion on 2026-09-25. These are design choices, not plant
facts, so they are rulings rather than CLAIMED/VERIFIED statements.

### Round 1

| question | answer | what it means for the build |
|---|---|---|
| The 7 web panels cannot paint their `.dc.html` design onto a 3D screen (the WebView is a native window). What goes on those screens in the world? | **"Godot pages now"** (the recommended option) | Each web panel's in-world screen shows the Godot-built page that already exists, with the same live data and an older look. The web designs get redrawn as Godot pages one at a time afterwards, starting with the extruder/PCU. |
| Which panel is built first, for play-testing? | **"Extruder/PCU first"** (the recommended option) | `hmi_extruder_all` gets its in-world screen first, on the Godot `ExtruderBluPortScope` page. |
| Reading from 3–5 m (the screen is ~115 × 74 px at 3 m on 1080p) | **Free text, verbatim:** "if you press the F key, as long as you hold it down, it should, if the camera is in third person view, it should switch to first person view while remembering the location of the third person view camera. So it can switch back to the exact same location if the F key is released. And if it is already in first person, it will zoom in by 20% or so. And then you can use the scroll wheel to zoom in further. So if you're scrolling forwards, which would be up normally, then the zoom increases, uh, I don't know, to like a value like, uh, I don't know what would be good uh, value, uh, I think maybe 30x zoom or something." | Hold-F is ALSO the reading zoom, not only the interact mode. In a third-person camera (`CameraRig` ORBIT / FREE_MOVE), holding F switches to first person and remembers the rig's exact state; releasing F restores it. Already in first person, holding F zooms in by ~20 %. Wheel up while F is held zooms further, up to a maximum he put at **"maybe 30x"**. He said he does not know the right value, so 30× is **his placeholder, not a ruling**. For scale: to show a 1280-px design 1:1 at 5 m on 1080p needs ~18.5× (1280 / 69 px). Today the wheel on foot cycles the hotbar (`PlayerController.gd:1059-1063`), and F4 + wheel zooms the orbit camera (`CameraRig.gd:305-309`), so wheel-while-F-held must zoom and must NOT cycle the hotbar. |
| Reach for pressing an on-screen button in F-mode | **"About 1.5 m"** | The click ray in F-mode is ~1.5 m. Today's E ray (3.75 m, `PlayerController.gd:49`) is unchanged for everything else. |

### Round 2

| question | answer | what it means for the build |
|---|---|---|
| What should E on an HMI still do once the screens are in the world? | **Free text, verbatim:** "the F key would be the interaction key. So also picking up, like, for instance, the leaf blower. Or opening a door from a vehicle. Or pushing a button from a gate to make the gate go up or down or something. Or pushing an emergency button, anything like that, would be... Done with the F key. Then the E key. Is basically free or something. Please check if the. If there are any other bindings to the E key, if there are, please let me know. If there are not, we could maybe use the E key to pick up things like the leaf blower and the shovel and stuff, and the hoses. That way, it's also possible to interact with stuff without per se picking it up, which might be useful for some cases. Not all, of course. You shouldn't be able to shovel without holding the shovel just by interacting with it while it's on the ground, but you know what I mean. So indeed, E on the HMI would not do anything." | **F becomes THE interaction key** (doors, gate buttons, e-stops, vehicle doors), and **E becomes pick-up**, a separate verb. E on an HMI does nothing, so **no pop-up at all**. The consequence he did not state: the 7 web designs cannot be seen in-game until they are redrawn in Godot (round 1). **E is NOT free today**; the answer to his check is in §H3 below. |
| Flashlight, now that F is F-mode | **"Move flashlight to L"** (the recommended option) | On foot L = flashlight. In a cab L stays `vehicle_lights` (`SettingsManager.gd:760`). |
| Panel page after save / load | **"Saved with the game"** (the recommended option) | Each panel's current page is part of the save. |
| Can you walk while F is held? | **Free text, verbatim:** "Yes, keep walking uh, is possible. Jumping as well. Crouching and lying down as well. Looking using the mouse, for instance, would also still be possible. […] the more zoomed in the view is, the less sensitive the look direction and stuff would be. So walking would remain the same speed and stuff. But if I move […] my mouse to the left, instead of, you know, turning 45 degrees with the same movement when zoomed in, it would do only one tenth or something" — then the crosshair, below. | All movement stays live in F-mode: walk, jump, crouch, prone and mouse-look. Walking speed is unchanged. **Look sensitivity scales down with zoom.** His "one tenth" is an example, not a number to type in. |
| (same answer, continued) **the F-mode crosshair** | **Verbatim:** "the center dot would already be there. […] when you press and hold down the F key, a like slightly, slightly larger glowing between like gold and like translucent dot would appear at the exact same location in the center and then using the mouse […] if you move left with the mouse 100 pixels your view would […] change by like seventy five percent, so like seventy pix seventy five pixels, and that glowing golden translucent dot crosshair kind of thing would only move. 33 percent so about 33 pixels from the center […] that golden dot thing is of course still the aim target so do not use the center as the aim target it should of course be the point where the golden dot Crosshair thing is pointing." | The existing 5×5 centre dot (`HUD.gd:124-133`) stays. Holding F adds a **slightly larger, glowing, gold, translucent dot** at the centre. Mouse movement is split: **the view turns ~75 %** of its normal amount and **the gold dot moves ~33 %** of the mouse movement away from the centre. **The ray goes through the gold dot, not the centre.** 75 % and 33 % are his "like" figures and are tunables. What happens at the dot's edge limit, and whether it re-centres on release, was not said; the default is re-centre on each F press. |
| (same answer, continued) **an options menu** | **Verbatim:** "if there are multiple options for something, like in Star Citizen […] you point at the gun laying on the floor, you hold the F key, you move the dot over it. You can choose like equip or store or inspect, you know, several options. Maybe we can use that uh, mechanic too. If not, then maybe uh, just document it and write it for later." | A context menu when the gold dot is on a target that has more than one action. **Build or defer is asked in round 3.** |

### Round 3

| question | answer | what it means for the build |
|---|---|---|
| How do you do a simple action (door, gate button, e-stop) with F? | **Free text, verbatim:** "a combination of holding F, aiming the dot and clicking for, for instance, uh, operating a gate because there is three buttons, you know, the arrow up to open it, the button in the middle below it to stop opening or closing it and the button at the bottom, the third button, which is the arrow down, which is to close it. Just pressing F will not be good enough because it's not known exactly where you're aiming and what control to pick, right? So then holding F would be good because you can aim at the up arrow and make the gate go open, you know? But if there is only one option available, for instance, opening a door, then tapping F would also be sufficient, but it should like show this. So it has to like show some kind of like small tooltip when you're aiming at the door." | **Two gestures, chosen by the target.** (1) A target with **several controls** (the gate station's ▲ / stop / ▼, an HMI screen) is used with **hold F + gold dot + left click**. (2) A target with **exactly one action** (a door) also accepts a **tap of F**, and it must show a **small tooltip** while you aim at it. That is the existing interaction prompt (`EventBus.interaction_prompt_show`), which today reads "E"; it will read "F". Consequence: a tap must be told apart from a hold, which is asked in round 4. |
| In a cab, F is lift/boom down. What should F do there? | **"F interacts in cab too"** | F is the interaction key in the cab as well (vehicle doors, getting out). **Lift/boom down (`forklift_lift_down`, F today) needs a new key.** He named none; asked in round 4. |
| Hold jobs (vacuum-pot lid, knife replace, shaft cut) | **"F-mode + hold left mouse"** (the recommended option) | Hold F, gold dot on the lid, knife or shaft, then **hold the left mouse** for the timed job. They replace hold-E (`PlayerController.gd:1360-1367, 1520-1526, 2018-2038`). |
| Star Citizen-style options menu | **"Write down, build later"** (the recommended option) | Not built. The design is recorded in §H4 below and gets built when an object gets a second action. |

### Round 4

| question | answer | what it means for the build |
|---|---|---|
| Tap vs hold, and the camera | **Free text, verbatim:** "I want the F mode to temporarily switch to third person view because if you're in third person view, your character is blocking the view of what your character is looking at, right? So that's why holding down the F key causes first person view. And since the F key is activated, it would activate actually the interaction mode, slightly zoomed in version of the first person view. But when you release the F key, which I might have for forgotten to uh, tell you, is that it should undo the slight zoom of the interaction mode. And in case that before pressing the F key, the camera was in third person mode, it should go back to that. If you start in first person mode and you hold F and then you release F, you should still be in first person mode at the correct FOV that was set before you press the F key. Uh, FOV would also be the same before and after pressing the F key if you were in third person mode." Then, asked again: **"No jump: F-mode after ~0.2 s"** (the recommended option). | His first words say "third person"; the rest of the answer means FIRST person (third person blocks the view, "holding down the F key causes first person view"). Read that way: **F-mode = first person + the ~20 % interaction zoom, whatever camera you started in.** **Releasing F restores the exact prior state**: the camera mode (and, in third person, the rig's exact position) and the FOV as it was, including any wheel zoom. **A tap under ~0.2 s** does the single action and never moves the camera. **Held longer, F-mode starts.** 0.2 s is a tunable. |
| Lift/boom down, now that F interacts in the cab | **"E"** (the recommended option) | In a cab: **R = lift/boom up, E = lift/boom down, F = interact/exit.** |
| Hose nozzle "unanchor / return tip to reel" (F today) | **"R"** (the recommended option) | `hose_advance_back` moves from F to R. On foot R is otherwise unbound; build mode's R (`build_raise`) is a different context. |

Not asked, kept by default (say so if wrong): **build mode keys are
unchanged** (E/Q rotate, R/F raise/lower). F-mode and the new interaction key
are for walking and the cab only.

## H3. What E is bound to today (his round-2 check) — VERIFIED

E is **not** free. It is the `interact` action (`project.godot:135`), and every
"do something with what I look at" in the game goes through it:

- **Crosshair targets** (everything with `crosshair_interact`): HMIs, gate
  buttons, boarding vehicles on foot (`BaseVehicle.gd:859-871`) and the other
  crosshair objects (`PlayerController.gd:997-1001`).
- **Proximity handlers** that run when the crosshair did not take the press:
  - Door, Gate and PushGate. These read `KEY_E` **directly**, so a rebind
    would not move them (`Door.gd:136`, `Gate.gd:97`, `PushGate.gd:171`).
  - Hose reel and hose nozzle, LPG tank, charging plug, jerrycan.
  - Extruder, bezinktank, waste container, service station, shift-leader
    desk, quality bench.
- **Hold-E actions**: knife replace, shaft cut, and the vacuum-pot lid
  mini-game (`PlayerController.gd:1360-1367, 1520-1526, 2018-2038`;
  `VacuumPotInteract.gd:66-133`).
- **In a cab**: E exits the vehicle (`OperatorContext.gd:55-76`). On the Merlo
  P40, E opens the door (`MerloP40.gd:730`). On the mast lift, holding E
  lowers it (`MastLift.gd:302`).
- **Dropping**: 10 held tools drop on E when nothing is targeted, for example
  `ShovelTool.gd:85` and `WireCutter.gd:111`. Q already drops (`hotbar_drop`,
  `project.godot:402`).
- **Build mode**: E is `build_rotate_cw` (`project.godot:246`); Q is its
  counter-clockwise pair.

Under his plan, F takes every item above except build mode's rotate. E is
left with pick-up, which is a new verb.

F's own current bindings also have to move or stay by context:

| context | F today |
|---|---|
| on foot | `flashlight` → moves to L (round 2) |
| in a cab | `forklift_lift_down` (forklift, bale clamp, Merlo) — R is lift up |
| build mode | `build_lower` |
| holding the hose nozzle | `hose_advance_back` ("return tip to reel") |

## H4. Deferred: the options menu (his round-2 idea, "write down, build later")

When the gold dot rests on a target that offers more than one action, a
small menu lists them, for example "equip / store / inspect" on an item on the
floor, as in Star Citizen. The player picks one with the gold dot and a click.
**Build it when the first object gets a second action.** Under the E/F split,
almost every object has one F action and, if it can be carried, one E action.

## H5. The spec these answers add up to (nothing built yet)

1. **In-world HMI screens.** Each placed panel shows its page on its own
   0.49 × 0.315 m screen. The page belongs to that panel, persists while
   playing, and is **saved with the game**. There is **no 2D pop-up**, and
   **E on an HMI does nothing**. The 7 web panels show their existing Godot
   page. Their `.dc.html` designs are redrawn in Godot one at a time
   afterwards, extruder/PCU first, and cannot be seen in-game until then.
2. **First to build:** `hmi_extruder_all` on `ExtruderBluPortScope`.
3. **F-mode** (hold F longer than ~0.2 s, on foot and in a cab):
   - It switches to first person with a ~20 % zoom, whatever camera you
     started in.
   - Wheel up zooms further. His placeholder maximum is "maybe 30x" (~18.5×
     shows a 1280-px design 1:1 at 5 m on 1080p).
   - Look sensitivity scales down with zoom. Walk, jump, crouch, prone and
     mouse-look all stay live, and walking speed is unchanged.
   - A slightly larger, glowing, gold, translucent dot appears over the
     existing 5×5 centre dot. The view turns ~75 % of the mouse movement and
     the gold dot moves ~33 % of it off centre.
   - **The interaction ray goes through the gold dot.** Its reach is ~1.5 m
     for pressing screen controls.
   - Left click presses the control under the gold dot. **Holding the left
     mouse** does the timed jobs: vacuum-pot lid, knife replace, shaft cut.
   - Releasing F restores the exact camera mode, third-person rig position
     and FOV from before.
4. **Tap F** (under ~0.2 s) does the single action of a one-action target
   (a door). A small tooltip shows while you aim at such a target. A
   multi-control target (the gate's ▲ / stop / ▼, a screen) needs F-mode.
5. **Keys:**

   | context | E | F | Q | R | L |
   |---|---|---|---|---|---|
   | on foot | **pick up** (tools, hoses, the leaf blower) | interact: tap = single action, hold = F-mode | drop (already) | hose: unanchor / return tip to reel | flashlight |
   | in a cab | lift/boom **down** | interact / get out / vehicle door | — | lift/boom up | vehicle lights (already) |
   | build mode | rotate (unchanged) | lower (unchanged) | rotate (unchanged) | raise (unchanged) | — |

   E no longer drops anything, so the E branch in the 10 tool scripts goes.
   Door, Gate and PushGate read `KEY_E` directly and must move to the action.
   Saved bindings in `user://settings.cfg` override defaults per action, so
   the change needs a settings migration (as `_migrate_legacy_keybinds` did).
   It also needs the F1 sheet's labels (`SettingsManager.gd` `ACTION_LABELS`)
   updated.

### Open — not asked yet, and not to be guessed

- **Where the 12 panels stand.** `HmiScopes.MOUNTS` is 0 of 12 set. An
  in-world screen shows only on a panel he has placed.
- **The real panel's physical size.** The sim's 0.49 × 0.315 m face is not
  sourced. A photo with a known object beside the panel, or the SIMATIC model
  number, would settle it.
- **The gold dot's travel limit** (how far off centre it can go), and what
  happens when F is released mid-click.
- **Alarm acknowledgement.** Since 2026-09-25 a panel beeps until KWITTEREN
  (`Hmi._setup_alarm_sound`), and that count reads the ONE shared overlay's
  fault list. With twelve in-world screens, does KWITTEREN on one panel
  silence the others that show the same fault? INFERRED: yes, as in a PLC.
  To confirm.
- **Automaat / hand mode per panel or per machine.** Today it lives on the
  one shared overlay (`HmiOverlay.gd:206-209`). In the plant it is the PLC's
  state, so two panels showing one machine should agree. INFERRED; to confirm.
