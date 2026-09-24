# Operator rulings — 2026-09-24 (extruder melt pressures)

Source: Arno, answering AskUserQuestion prompts in the Claude session of
2026-09-24 (worktree `clever-hypatia-945f15`, on `main` `b8bda8a`). These are
**recollections, not documents or photos**. Label them as such when citing
(CLAUDE.md Rule 1 accepts "explicit approval"; this is that). Where an answer
set a number or a wiring in code, the code cites this file.

Separate from `operator_rulings_2026-09-23.md` (rounds 1–9 of the other
thread). This file covers only the melt-pressure question.

## 1. What was asked, and why

`ExtruderModel.gd` carried one pressure, `die_pressure_psi`. Its base was
280 "psi", with the comment "operator-documented ~280 psi die-head pressure"
and no source named. `docs/DETAIL_STANDARD_audit_2026-08-18.md` H4 had already
flagged that comment as prose provenance without a file. Every plant source
gives ~280 in **bar**:

| Source | Reading |
|---|---|
| `swi/SWI-054-p1__156_CeDo31_2.md` | laserfilter 3A/3B changed "bij een druk van 280 / 300 bar" |
| `swi/OTHER-erema-hmi-bluport-lijn3C__214_CeDo61_3.md` | 3C: 280 bar before the filter, 24 after |
| `swi/PHOTO-erema-bluport-lijn3C-trend-8curves-2__293_CeDo47_3.md` | 3C: 287 / 284 bar before the filter, 26 after |
| `swi/PHOTO-erema-bluport-lijn6__226_CeDo68_3.md` | line 6: MP<MF1 279, dMP 257, MP>MF1 22 bar |
| `hmi_reference.md` §1 (3A laserfilter screen) | MP<MF 207, dMP 182, MP>MF 25 bar |
| `trends_overview.md` §2 | "Smeltdruk voor meltfilter" 3A p50 271 / p95 280, 3B p50 177 / p95 190 (one 72-min session each) |
| `trends_overview.md` §2 | "Druk voor kopfilter" (`MD_vor_SF2`) 3A p5–p95 103–173 (p50 140), 3B 106–166 (p50 143) |
| `checklist_3a_3b.md` rows 25/26 (FORM-008) | kopdruk kopfilter 3A 120–150, 3B 140–155 bar |

MEASURED 2026-09-24 on `b8bda8a`: a nominal 3B run (110 rpm, 950 kg/h) held
`die_pressure_psi = 280.0`. The BluPort showed it as 19.3 bar. The 160-bar
MP<PEL interlock sat 8.3× above nominal. The model tops out near 46 bar,
because the 110 % torque trip comes first, so neither documented trip could
fire. On 3A the laserfilter's 318-bar check read the kopfilter's dP instead,
which is at most 600 psi (41 bar). The same run put the 3A LaserFilterScope at
MP<MF 0.0 bar and MP>MF −191.5 bar.

The one number fed two trips at two different points of the line. The flow
diagrams (`lijn_3a_flow.md`, `lijn_3b_flow.md`) run
"Extruder laserfilter vacuum → Kopfilter & heetafslag". So the operator was
asked whether the 280 was bar, and at which point it applies.

## 2. The answers

- **Unit: bar.** In his words, 280 is "not per se a normal pressure". It is
  a **safe maximum** before the laserfilter, low enough that a spike from a
  change in material or temperature stays under **318 bar**, where the
  extruder makes an emergency shutdown. "Personally, I would run it rather
  at **220 bar** pressure. It's also more energy efficient. But if the laser
  filter is getting clogged, you have to exert more pressure on the material
  to get the same output."
- **Two pressures, not one.** One before the laserfilter drives the 318-bar
  trip. A second, on the die side, drives the 160-bar trip. The laserfilter
  stops reading the kopfilter's dP as its "upstream", because the kopfilter
  sits after it.
- **What raises the pressure before the laserfilter: "Both."** The melt sets
  the pressure AFTER the filter, and the screen's own dMP adds on top. So a
  caking screen climbs toward 318.
- **The line order upstream of the pelletiser: kopfilter (MF2), then the
  melt pump (MPU), then the laserfilter further up.** In his words: "if I
  look up from the pelletizer, there is head filter, and then before the head
  filter, stream up is the MPU or melt pump."
- **MP<PEL (the 160-bar interlock) = the dP ACROSS the kopfilter (MF2).**
  Asked where the trip reads, he chose "ΔP across kopfilter" over "into the
  kopfilter" and "out of the kopfilter". Note that the EREMA manual
  (`swi/EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md`) words MP<PEL as
  "smeltdruk stroomopwaarts van de pelletiseermachine", a pressure rather than
  a difference. The code follows the operator.
- **Die-side nominal: per line.** 3A and 3B each get their own FORM-008
  window.

## 3. What the code carries (2026-09-24)

| Quantity | Model field | Nominal | Where the number comes from |
|---|---|---|---|
| after the laserfilter, MP>MF | `mp_after_laserfilter_bar` | 25 bar × throughput × melt factor | 3A screen (`hmi_reference.md` §1); melt factor §6 |
| laserfilter dMP | `laserfilter_dp_bar` (from LaserFilter) | 175–235 bar sawtooth × melt factor | unchanged LaserFilter calibration (#223); melt factor §7 |
| before the laserfilter, MP<MF | `mp_before_laserfilter_bar` = after + dMP | measured 197.6–260.0 bar | operator: ≤ 280 safe, 318 trip |
| die plate (out of the kopfilter) | `die_plate_bar` | 3A 120, 3B 140 bar × throughput × melt factor | **DERIVED**: bottom of each FORM-008 window |
| kopfilter dP | `kopfilter_dp_bar` (from HeadFilter) | 0 fresh → 11.5 bar after 8 h | unchanged HeadFilter rate |
| kopdruk (into the kopfilter, `MD_vor_SF2`) | `kopdruk_bar` = die plate + pack dP | 3A 120.1 → 131.5, 3B 140.1 → 151.5 bar over a shift | FORM-008 windows |
| MP<PEL | `mp_pel_bar` = kopfilter dP | 0.2 bar fresh | operator ruling above |

Assumptions the code carries that are **not** operator numbers:

- **Die plate = the bottom of the FORM-008 window.** Chosen so that one shift
  on one pack (FORM-008 row 27: "1x per dienst minimaal wisselen") stays
  inside the window at the HeadFilter's existing loading rate (1.44 bar/h at
  950 kg/h). A shared 140 would put 3A at 151.5 after a shift, outside
  120–150.
- **MP>MF 25 bar** is the one 3A screen. Line 6 shows 18–22 and 3C 24–26.
- **The laserfilter's front-face amplification** (the "right side clogged
  again" mechanism) now reads the melt-set after-filter pressure, not the
  before-filter one. The before-filter pressure contains the filter's own
  dMP, so reading it would feed the cake back into itself. The constants
  keep the old 250/280 ratio, so the curve is unchanged: +0.12 at nominal.
  On 3A this is a change, because 3A's amplification used to follow the
  kopfilter's dP.
- **The HeadFilter's 600-psi clamp is gone.** It had no source and kept the
  pack dP under 41 bar, which made the 160-bar interlock unreachable. A pack
  nobody swaps now reaches 160 bar after **111 h** at 950 kg/h. The pack
  prompt reads in bar.

## 4. Measured after the change

Source: `src/tests/test_extruder_melt_pressures.tscn`, wired into `run.sh`,
44 ok.

- 600 s at nominal on both lines, no trip. MP<MF 197.6–260.0 bar on both lines
  (the laserfilter calibration is shared).
- The 318-bar trip fires 0.1 s after a caked screen pushes MP<MF past it.
  At 308.8 bar it does not trip.
- The 318-bar trip also fires 0.2 s after all seven zone setpoints drop 20 °C.
  Torque peaks at 100 %, under the 110 % torque trip. Cold lumps cake the
  screen's front face and dMP saturates at its 350-bar clamp.
- 165 bar dP across the kopfilter trips the 160-bar interlock (Storingstabel
  5516). 155 bar dP does not, although kopdruk is 275 bar at that point.
- After an E-stop reset the 318-bar trip is armed again: a second caked
  screen in the same session trips 0.1 s later. Before this, it was not
  armed. `LaserFilter.is_tripped` cleared only on a screen change (INSERT),
  and the filter signals only on the rising edge. So once the trip could be
  reached, one reset-and-restart left it dead for the rest of the session.
  ExtruderMachine now calls `LaserFilter.rearm_upstream_trip()` at the reset
  edge, where it re-arms its own two latches. The cake stays where it is: a
  restart onto a screen that is still caked past 318 trips again, and the
  way out is the screen change.
- Six mutations turn it red: the psi scale restored (10 fail), the HeadFilter
  clamp restored (4), the trip ignoring dMP (7), the 160 trip reading
  kopdruk (3), `Extruder3A.tres` removed (2), and the re-arm call dropped (2).

## 5. Open, to ask or to look at

- **3B before the laserfilter sits ABOVE its trend band.** The sim reads
  197.6–260.0 bar, while the 3B trend p5–p95 is 7–190 (p50 177). The suite
  prints this as an `info` line and does not gate it. The 3B band comes from
  one 72-minute session at an unknown output (3B's nine-day output p50 is
  799 kg/h, the sim runs 950). The laserfilter's dMP calibration is also one
  calibration for both lines, taken from a 3A screen. What would settle it:
  the 3B laserfilter screen (MP<MF / dMP / MP>MF) photographed at a known
  output, or the operator's recollection of 3B's usual dMP.
- **The HeadFilter's loading rate has no source.** At 1.44 bar/h a pack takes
  111 h to reach the 160-bar interlock. FORM-008's 3A window (120–150) suggests
  up to ~30 bar of rise per shift. If he recalls how fast kopdruk climbs on a
  pack, that sets the rate.
- **The cold-zone path trips in 0.2 s.** That speed comes from the lump model
  (`(torque − 95) × 5 g/s`) against the cake calibration (2500 psi per g).
  Both predate this change, and neither has a source. Before this change the
  same event saturated dMP at 350 bar and ran on.
- **ANSWERED 2026-09-25, see §7: dMP rises too.** The question as it stood:
  **The melt-temperature fit is ON MP<MF, and the merged model moves MP<MF
  far less (see §6).** The fit is 6.83 bar/°C on the pressure before the
  laserfilter. In the two-pressure model the melt factor reaches MP<MF only
  through MP>MF: 25 bar × 2.44 % = 0.61 bar/°C. By the fit, a melt 12 °C colder
  adds ~82 bar (271 → ~353, past 318). The model adds ~7 bar. The two agree
  only if the laserfilter screen's dMP also rises with viscosity. No plant
  source here says whether it does. What would settle it: the operator's
  recollection of whether the laserfilter's dMP climbs when the melt runs
  colder, or a trend export that pairs dMP with melt temperature.

## 6. Merged with #275 (same evening)

A second session fixed the same finding in parallel. Its fix is #275
(`1588462`), which reached `main` before this branch (PR #278). Both agree that
280 is bar. They differed on two points, and the operator was asked again
(AskUserQuestion, 2026-09-24, late evening):

- **MP<PEL: "ΔP across kopfilter".** He chose this over #275's version, a copy
  of the pre-filter pressure scaled to 140 bar nominal, taken from the EREMA
  manual's wording. It confirms §2.
- **The melt-set pressures follow MELT temperature: "Yes, melt
  temperature".**
  - #275 records the ruling behind this: pressure follows melt temperature,
    not motor torque. On the torque proxy, one zone 30 °C down read 320 bar and
    tripped the line.
  - Its number is a fit, not the operator's. It pairs the 3A WinCC trends
    "Smeltdruk voor meltfilter" and "Smelt temperatuur voor meltfilter": slope
    −6.83 bar/°C, r = −0.76, n = 967. The fit is **weak**: one 73-minute
    pressure window, and 948 of the 967 pairs in one 5 °C bin.
  - The merged model scales the melt-set pressures (MP>MF and the die plate)
    by 6.83 / 280 = **2.44 % per °C** of melt below setpoint, as #275 did
    (`ExtruderModel.DIE_PRESSURE_BAR_PER_C` / `MELT_FIT_LEVEL_BAR`).
  - Torque still drives the lumps into the laserfilter. So the cold-zone trip
    in §4 still comes through the screen.

What the merge did to #275's suite, `test_die_pressure_bar` (the original is
kept as `.bak`):

- **Kept:**
  - the melt sensitivity check, now as a fraction of the melt-set pressures;
  - the laserfilter inlet is not the kopfilter's ΔP;
  - a nominal run latches neither trip;
  - one zone 30 °C down trips nothing. This check now runs on the wired rig
    with the filters stepped, because on the rig the other way to 318 is
    through the screen.
- **Rewritten**, because it asserted the single-pressure model:
  - a bare model reading 280 bar before the filter. With no screen there is
    no dMP.
  - MP<PEL at 120–150 bar. That band is now kopdruk's, checked against 3B's
    FORM-008 window and the 3B trend.
  - a 12 °C colder melt alone crossing 318. That is the open item in §5.

Measured on the merged tree (2026-09-24 23:47–23:53, isolated `APPDATA`):

- **Parse sweep:** 449 ok, 0 fail.
- **Suites:**

  | Suite | Result |
  |---|---|
  | `test_extruder_melt_pressures` | 44 ok; §4's numbers unchanged, since the melt factor is 1.0 at setpoint |
  | `test_die_pressure_bar` | 20 ok |
  | `test_extruder_bluport_scope` | 20 ok |
  | `test_laser_filter_scope` | 8 ok |
  | `test_laserscope_pressure_box` | PASS |
  | `test_extruder_screw` | 12 ok |
  | `test_extruder_brain_wired` | 24 ok |
  | `test_hmi_ack_rearm` | 7 ok |
  | `test_legacy_props_spawner` | 5 ok |
  | `test_legacy_props_unconfigured_boot` | 35 ok |
  | `test_tag_snapshot` | 28 ok, 1 data-gated skip: no `allernieuwste_*.json` in the isolated copy |

  Every suite had 0 `^SCRIPT ERROR` lines.
- **One zone 30 °C down on the wired rig:** torque 60.0 → 68.6 %, under the
  95 % lump threshold. MP<MF peaked at 260.0 bar (the normal sawtooth top),
  no trip.
- **1 °C colder melt:** +2.37 % (fit 2.44 %). That is MP>MF +0.59 bar and die
  plate +3.31 bar.
- **Mutations of `test_die_pressure_bar`:**

  | Mutation | Red checks |
  |---|---|
  | Torque proxy restored | 1 (A7c, 3.23 %/°C) |
  | Laserfilter fed the kopfilter's ΔP | 2 (B1, B2) |

  The zone-drop check (C2) does not catch the torque proxy on its own. In the
  two-pressure model, torque scales only the 25-bar melt-set part, so neither
  factor lets one zone reach 318. A7c is the check that tells them apart.

## 7. The laserfilter's dMP follows the melt too (2026-09-25)

Asked right after the merge (AskUserQuestion, same session, just after
midnight): when the melt runs colder, does the laserfilter's own dMP rise
too? **"Yes, dMP rises too."** This is a recollection, like the rest of this
file.

**What the code does**

- `ExtruderModel.melt_viscosity_factor` is the melt's viscosity relative to
  setpoint: 1.0 at setpoint, +2.44 % per °C colder (the §6 fit).
  ExtruderMachine forwards it to the LaserFilter every tick.
- The LaserFilter multiplies both faces' ΔP by it, the clean-screen part and
  the cake alike. A colder, thicker melt needs more pressure through the
  same screen.
- Two things do not change:
  - the M1 disc-motor load reads the cake's `loading_g` directly;
  - the disc advances on a timer, not on dMP.
- MP<MF therefore moves about 6.6 bar/°C at a 271-bar reading, close to the
  fit's 6.83 at 280.

**Measured on the wired 3B rig** (a temporary probe for before and after, and
the suite for after):

| Case | Before | After |
|---|---|---|
| Melt held 5 °C under setpoint, 60–120 s | peak 271.9 bar | peak 301.5 bar, no trip |
| Melt held 9 °C under | peak 281.5 bar, no trip | **318 trip after 6.6 s** |
| Melt held 12 °C under | peak 288.8 bar, no trip | 318 trip after 4.8 s |
| Start at the preheat-ready melt (196.25 °C, 18.75 °C under) | peak 260.0 bar, no trip | peak 267.9 bar, no trip |
| Normal stop from nominal | not measured | peak 222.0 bar, OFF after 21.7 s, no trip |

Notes on the table:

- The fit predicts ~332 bar for a melt 9 °C cold (271 + 9 × 6.83), so the
  9 °C trip is what the fit implies.
- During the stop the factor reaches 2.36 as the melt cools, but the no-flow
  gate holds dMP at 0.
- The 5 °C case peaks above his 280-bar safe maximum and under 318. That
  matches his description of 280 as the level that keeps a
  temperature-driven spike clear of the shutdown.

**Guards**

- `test_extruder_melt_pressures`, a new section, now 53 ok:
  - 5 °C cold holds;
  - 9 °C cold trips through the screen, with torque under the lump
    threshold and no lumps;
  - a start at the preheat-ready melt does not trip.
- `test_die_pressure_bar` A7d checks that the model exposes the factor
  (21 ok).
- Mutations:

  | Mutation | Checks red |
  |---|---|
  | The screen ignores the factor | 1 |
  | The extruder never forwards it | 3 |

**Limits, measured, not changed**

- While RUNNING, the model's melt drifts back to the GLOBAL setpoint
  (0.3 °C/s) whatever the zones do. So today only the start and an injected
  melt exercise this path. A zone drop raises torque and lumps, not melt
  cold.
- The factor compares the melt with its setpoint, not with an absolute
  temperature (#275's formula). If gameplay could ever raise the setpoint
  while running, the lagging melt would read as cold and could trip.
  Nothing writes `melt_temp_setpoint` at runtime today (grep of `src/`).
- The kopfilter pack's dP does not scale with the melt. That was not asked.
