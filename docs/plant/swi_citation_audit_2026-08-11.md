# SWI citation audit — 2026-08-11

Every `SWI-0xx` reference in `src/` and `tools/` checked against
`docs/plant/swi/INDEX.md` and, where the claim was specific, against the digested
page itself.

Prompted by a real defect: `ExtruderMachine._ready()` cited **SWI-049** for the
extruder's start-up. SWI-049 is *"Opstarten sorteerlijn"* — the **sorting line**.
Anyone implementing from that comment would have modelled a 15-second extruder
preheat off a document about a different machine. That one is fixed; this audit
asks how many others there are.

**Scope:** 54 citation sites, 11 distinct SWI ids.
**Result:** every cited id exists in the index. **2 wrong attributions**, **1
overstated claim** (introduced by me the same day, in the fix for the first
one), 2 scope notes, and the rest verified correct.

---

## Corrected

### 1. `ExtruderGauntlet.gd:11` — SWI-049 attributed to the extruder bench

> `SWI-049 startup flow, SimTick ticking and the FAULT cascade all run against the real sim`

Same error as the original defect, in a second file. SWI-049 is the sorting
line. The extruder bench does not run an SWI-049 flow. Citation removed, with a
note pointing at SWI-042 p4 §19 for the extruder's own warm-up.

### 2. `ShredderMachine.gd:25` — SWI-042 attributed to cleaning shredder 2

> `- CLEAN + close (SWI-034 sh1 / SWI-042 sh2)`

SWI-034 *is* "Lijn 3 reinigen shredder 1", so the sh1 half is right. But SWI-042
is **"Leegdraaien lijn 3 voor meswissel"** — empty-running line 3 for a knife
change. It is not a shredder-2 cleaning procedure.

Checked further: the index has **no** shredder-2 cleaning SWI at all. The only
shredder-2 document is SWI-040 "Lijn 3 openen shredder 2" (opening, not
cleaning). The comment now says sh2 cleaning is undocumented, which is the true
state and flags it for the operator rather than hiding it behind a plausible id.

### 3. `MachineBrains.gd` + `test_extruder_brain_wired.gd` — overstated, mine

The 2026-08-11 wiring fix claimed that among the things dark without an extruder
brain was *"the SWI-049 startup flow that SorteerlijnScope drives against that
same group"*.

`SorteerlijnScope.gd` contains **no reference to extruders at all** — verified by
grep, zero hits for `extruder` or `extruder_machine`. The claim was wrong in
exactly the way the bug it documented was wrong.

Replaced with what is actually true and checkable:
`HmiOverlay._find_laser_filter_for_scope()` resolves a scope's laser filter by
finding that scope's extruder first and taking the nearest filter to it. With no
extruders in the world it always fell through to `filters[0]`, so every scope
pointed at the same filter.

---

## Verified correct — no change

| citation | doc title | verdict |
|---|---|---|
| `SWI-027` — open shredder 1 | Lijn 3 openen shredder 1 | ✅ |
| `SWI-040` — open shredder 2 | Lijn 3 openen shredder 2 | ✅ |
| `SWI-033` — rotor block bar | Lijn 3 rotor blokkeren shredder 1 | ✅ (see note) |
| `SWI-034` — clean shredder 1 | Lijn 3 reinigen shredder 1 | ✅ |
| `SWI-035` — line stop | Lijn 3 leegdraaien | ✅ |
| `SWI-039` — bunkerrol | Lijn 3 Bunker rol reinigen | ✅ |
| `SWI-048/049` in `SorteerlijnScope`, `HmiOverlay`, `ShredderFeedBelt`, bunker doors | Voor opstarten deel sorteerlijn / Opstarten sorteerlijn | ✅ all sorting-line contexts |
| `SWI-074` — laser filter change (11 sites in `LaserFilter.gd`) | Laserfilter wissel LF 2 – 406 | ✅ |
| `SWI-084` — 500 Nm click-wrench | Momentsleutel tbv laserfilter type 406 | ✅ **and the 500 Nm figure matches the doc** |
| `SWI-042 p4 §19` — 30-minute extruder warm-up | Leegdraaien lijn 3 voor meswissel | ✅ (see note) |

---

## Scope notes — not errors, worth knowing

**SWI-033 is shredder-1 specific.** `ShredderMachine.gd` is a generic controller
used for both shredders and cites SWI-033 for the rotor block bar without a
qualifier (lines 51, 195, 216). The index has no shredder-2 rotor-block
document. Either the same bar and procedure serve both — plausible, and worth one
operator question — or shredder 2 is undocumented here too.

**SWI-042's title does not describe its page 4.** The doc is
*"Leegdraaien lijn 3 voor meswissel"*, but page 4 is explicitly *"the timed
start-up sequence (08:35 → 15:00) with role tags"*, rows 14–20, carrying an
**Extruder operator** role tag. Step 19 is the 3a/3b compactor start-up with the
"minimaal 30 minuten" warm-up now encoded in `ExtruderConfig.preheat_min_s`. The
citation is correct but reads wrong from the title alone, so code citing it
should always name the page and step — as `ExtruderConfig` and `ExtruderModel`
now do. Step 19 also records *"Nog SWI maken opstarten extruders"*: there is no
dedicated extruder start-up SWI, which is why a page-4 schedule row is the
authority.

**SWI-035 for component ORDER.** Three sites cite SWI-035 for the front-end
layout order (`shredder 1 → belt → bunker → belt 1040`). SWI-035 is an
empty-running procedure; it walks the line and does mention the bunker
repeatedly, so it is reasonable corroboration, but the primary source for the
ordering is the operator interview those comments also cite. Left as is — the
comments already say "interview; SWI-035".

---

## How to re-run this

```bash
grep -rnoiE "(cedo-prod-)?swi[ _-]?0?[0-9]{2,3}" src/ tools/ --include=*.gd --include=*.py
```

then check each id's title in `docs/plant/swi/INDEX.md`. The failure mode is not
a citation to a non-existent document — all 11 ids existed. It is a citation to a
**real document about a different machine**, which reads as authoritative and
survives review. Both defects found here were of that kind, and so was the one
that started it.
