# Operator rulings — extruder start, rpm setpoint, green button (2026-09-25)

Answers the operator gave by AskUserQuestion on 2026-09-25, in the session that
reproduced the warm-restart 318-bar trip
(`docs/audit/extruder_warm_restart_2026-09-25.md`). They are **recollections**
(CLAIMED), not documents. Where the plant's own WinCC archive speaks to the same
point it is quoted beside them, as VERIFIED with its source. Where the two
disagree, both are written down and the ruling says which one the model follows.

## 1. How an extruder start works

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

## 2. A new extruder's setpoint is 60

**Ruling:** a freshly placed extruder starts with its rpm setpoint at 60, not at
nominal. After that it keeps whatever the player sets. He was told: *"a restart
at 110 on a cold melt can still trip"*. He chose this option knowing that.

The model does not save the setpoint, so a reloaded world starts at 60 too.

## 3. The green button waits until the screw passes no lumps

**Ruling:** the preheat-ready ("green") temperature is derived from the 95 %
lump-passthrough torque as well as from the 110 % torque trip, with the same 25 %
margin: **201.875 °C** on 3A/3B (13.1 °C under 215), was 196.25 °C. At 196.25 °C
the screw sits at 97.5 % torque. That is above the point where un-melted lumps
start passing to the laserfilter. Measured: a 60-rpm restart pressed the moment
the block turned green passed 3.4 g/s of lumps and tripped 318 bar 3.3 s later.

## 4. The start ramp: 3 s to 60 rpm (his number kept against the archive)

**Ruling:** keep *"about two and a half to three seconds ... let's say three
seconds to that 60 rpm"*. The model ramps at 20 rpm/s. The rate above 60 rpm is a
modelling choice, not his: he gave no number for it.

**Unresolved difference, recorded:** in the raw archive, only 1 of the 33 starts
that land on 60 already reads 60 at the first sample (samples every ~5 s). The
first readings spread evenly over 1–59 rpm. A 3 s ramp would put about 40 % at 60
by the first sample, so the archive points at about 5 s. He was shown this and
chose 3 s.

## 5. The player sets the rpm, per line, on the HMI

**Ruling:** the player sets the rpm, and there is a line choice on the one
all-lines extruder HMI ("add a line choice now"). Before this, the web HMI's
extruder channels went to the first extruder the scene tree listed. The
touchscreen fallback had no rpm field. So no line but one could be set, and a
tripped line could not be dropped to 60. The rule covers all extruders (1, 3A,
3B, 3C, 6).

## 6. Open — start interlocks (not built)

**His words:** the screw starts only once *"the water at the front of the
extruder"*, *"the centrifuge ... to dry the pellets"* and *"the shaking sieve"*
are running. **Ruling:** record it, build it in a separate task. Also said, and
not understood yet: the start is the *"LED white ring button, the right one,
because the left one is for easy work"*. What the left button does is not known.
Asking him settles it.

## 7. Open — found while measuring, not ruled on

- **OFF cools the melt 0.5 °C/s** (`ExtruderModel._tick_off`), with no source.
  In the plant a restart 35 s to 3 min after a stop goes straight back to the
  old rpm (§1). In the model, 35 s after the stop is pressed the melt is already
  under the green temperature and the start goes through PREHEAT.
- **The lump law** (`(torque - 95) x 5 g/s`) and the cake's `2500 psi/g` have no
  source either. Together they make the green threshold a knife edge: half a
  degree decided trip or no trip (audit doc §4).
