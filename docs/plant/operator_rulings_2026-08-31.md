# Operator rulings — 2026-08-31

Continues the thread opened in `operator_rulings_2026-08-30.md` (the line-6 wet-start video
`VID-20250912-WA0010.mp4`). These SUPERSEDE earlier notes where they conflict.

---

## 1. Line-6 extruder variant SETTLED — laserfilter on every line, Britas replaces only the head filter, melt pump on 3C AND 6

> "Yes. It runs a laser filter as well as a Britas. The laser filter is upstream. Basically, every
> extruder is the same, but instead of head filters, line six extruder has the Britas. and line
> three c and six both have a melt bum. As well. a meld pump as well. nine one nine three a and nine
> three b and nine one, I mean. Line fucking one. Yes. They have no melt pump, but the rest is the
> same."

*[Dictated; transcription artefacts left intact per the capture-verbatim convention. "melt bum" /
"meld pump" = melt pump; "nine one nine three a and nine three b" = line 1, line 3A, line 3B.]*

**Clean reading — every extruder is the same except two per-line deviations:**

| Line | Laserfilter | Final filter | Melt pump |
|---|---|---|---|
| **1, 3A, 3B** | YES | Head filter unit + safety hood | **NO** |
| **3C** | YES | Head filter unit + safety hood | **YES** (gear pump) |
| **6** | YES — **upstream of the Britas** | **BRITAS ABMF** (screen-belt) *instead of* head filters | **YES** (gear pump) |

**This CONFIRMS an existing repo doc.** `docs/plant/misc_sources.md:112-114` already carried exactly
this split and is marked "PORT THIS":

```
V1_HEAD_NO_PUMP   -> lines 1, 3A, 3B   (laserfilter, head filter, NO melt pump)
V2_HEAD_PUMP      -> line 3C           (adds a melt pump)
V3_BRITAS_PUMP    -> line 6            (Britas ... + melt pump)
```

That map is now operator-confirmed and is the port target. Its one wording flaw — calling the Britas
a "rotary" melt filter — is corrected in place at that file: the Britas is a screen-**belt** filter
(*Automatischer Bandfilter*, `hmi_screen_inventory_2026-07-28.md:149`, `Verbruikte zeefband 9645,000
m`); the **rotary disc is the laserfilter**, a different machine sitting upstream.

**This CORRECTS a different repo doc.** `docs/plant/extruder_line_layout.md:34` hedged line 6's melt
pump as "(per 1/3A/3B unless told otherwise)" — i.e. NO. We have now been told otherwise. That cell
is corrected in place, with a `CORRECTION 2026-08-31` note under the table.

**This CLOSES open question 1 of `operator_rulings_2026-08-30.md` §6** ("does line 6 run both?").
Answer: **yes — laserfilter upstream, Britas at the die.** The two were never in conflict; the
earlier framing of a "Britas vs disc" contradiction was wrong and is corrected in that file's §5.

**It also VALIDATES the `photo_audit.md` laserfilter row.** That row's Line column reads "all", which
the 2026-08-30 audit flagged as an over-generalisation from a line-3B photo that had never been
tested against line 6. It is now operator-confirmed correct: every line has the laserfilter.

---

## 2. Two code defects this ruling confirms — (a) FIXED 2026-08-31, (b) BLOCKED ON PHOTOS

Both verified by direct inspection of `src/build/PlaceableCatalog.gd` on 2026-08-31. Defect (a) was
fixed on operator instruction the same day; defect (b) needs a new machine model and stays blocked.

**a) Line 6 rendered no melt pump. FIXED 2026-08-31.** `SECTION 6: MELTPUMP` at `:11316` was guarded
by `if line_tag == "3C":` — the **only** line gate in the entire extruder builder (an `awk` sweep of
lines 10900-11500 for `line_tag ==` returned exactly one hit). `extruder_6` was therefore built
without the gear-pump block. Widened to `if line_tag in ["3C", "6"]:` (now at `:11326`), and the
stale `#225.3 spec: ONLY line 3C` comment above it — which asserted "1 / 3A / 3B / 6 feed the die
head directly" — was corrected in place rather than left to mislead the next reader.

**Proof (mutation-tested, not asserted).** A temporary probe
(`src/tests/probe_meltpump_tmp.gd` + `.tscn`, safe to delete) builds all five extruder placeables
headless and counts vertices. Surface count is useless here — the builder packs parts into
shared-material surfaces, so all five report 42 surfaces either way; vertex count is the sensitive
metric.

| Build | 1 / 3A / 3B | 3C | **6** | verdict |
|---|---|---|---|---|
| pristine baseline | 19184 | 20040 | **19184** | FAIL — 6 matched the no-pump lines |
| with the fix | 19184 | 20040 | **20040** | PASS — 6 matches 3C exactly |

The delta is **856 vertices**, identical to 3C's melt-pump block. The probe goes red on the baseline
and green on the fix, so it is measuring the change and not passing for free.

**Regression harness state at the time of the fix:** `test_nav_connectivity` fails with 2 checks
(`Abdellilah` / `Mohammed` canteen←post routes ending 14.32 m short). That failure is **pre-existing
and unrelated** — it reproduces byte-identically on the pristine `PlaceableCatalog.gd`, and
`world_layout.json` contains no extruder placeable at all, so this mesh change cannot reach it. The
full `run.sh` sweep was not run to completion (it exceeded a 9-minute cap partway through
`test_outdoor_route`); the single suite was run directly, twice, for the before/after comparison.

**b) Line 6 renders a head filter it does not have, and has no Britas to render instead.**
`SECTION 5: KOPFILTER — piston-type screen changer at the die head` at `:11189` carries **no line
gate at all**, so every extruder including `extruder_6` draws a kopfilter. Per this ruling line 6
must show a BRITAS ABMF there instead. There is **no Britas model anywhere in `src/`** — the sole hit
for `britas` in the whole source tree is an unrelated colour comment at
`src/scenes/hud/scopes/HmiScreenBase.gd:59`. So this is not a gate change but a new machine model,
and per rule 1 it needs operator photos before it may be built.

**Reference material that already exists for the Britas**, if and when it is built: three authored
HMI pages (`docs/plant/hmi_screens_2026-07-26/BRITAS ABMF Overzicht.dc.html`, `… Extruder
Interface.dc.html`, `… Trend Zeefwisselcyclus.dc.html`), transcribed from real panel photographs at
`hmi_screen_inventory_2026-07-28.md:141-155`, including the quantified filter↔extruder interlock:
**on a screen change the filter commands the extruder DOWN 10 % and the pelletiser UP 10 %**
(`:145`), a 30 min cyclical screen-change setpoint (currently switched UIT) and a pressure-triggered
change at 155 bar against a running 125 bar (`:151`).
