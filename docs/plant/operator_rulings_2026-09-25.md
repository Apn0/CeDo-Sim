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
