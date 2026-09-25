# LineFlow's extruder screw: die plate in bar, rpm and melt from the trends (2026-09-24)

Scope: `src/sim/ExtruderScrew.gd`. This is the screw model LineFlow attaches to
every extruder node, and it is **separate from `ExtruderModel`**. It feeds the
MFI soft-sensor (`MfiProxy`), the Quality terminal (`QualityAnalysisTerminal`),
the QA bench's grading (`QaLab` → `QaSpec`) and the SCADA panel's melt and MFI
rows. The ExtruderModel's own pressures (BluPort, interlocks) are not touched
here. They were fixed in #275 and #278 (see §6).

## 1. What was measured before the fix

`src/tests/probe_screw_die_pressure.tscn` was run on `main` `fcb53e1`. It builds
one macro line through the production path (`BuildMode._build_full_line` →
`LineFlow.rebuild` → `start_line` → `tick(0.1)`), feeds the extruder's input
buffer at 950 kg/h for 300 s, and prints every node that carries a screw model.

| line | nodes with a screw model | screw | melt | `die_pressure` | MFI | QaSpec | terminal + SCADA read |
|---|---|---|---|---|---|---|---|
| 1 | `extruder_silo` #36, `extruder_1` #38 | 200 rpm | 195.0 °C | **0.1056 bar** | **1490.9** | REJECT | the silo |
| 3A | `extruder_silo` #22, `extruder_3a` #24 | 200 rpm | 195.0 °C | 0.1056 bar | 1490.9 | REJECT | the silo |
| 3B | `extruder_silo` #16, `extruder_3b` #18 | 200 rpm | 195.0 °C | 0.1056 bar | 1490.9 | REJECT | the silo |
| 3C | `extruder_screw` #22 | 200 rpm | 195.0 °C | 0.1056 bar | 1490.9 | REJECT | the extruder |

Four defects, all live in a real line:

1. **Scale.** `die_pressure = DIE_RESISTANCE (6.5e-4) · eta · throughput/0.5`,
   labelled bar. Every plant source puts die-side melt pressure in the hundreds
   of bar (§3), so this was about 1/1300 of the plant.
2. **MFI.** `MfiProxy` computes `MFI_GAIN · Q / (P · η(T))`. That is an
   **absolute** value, not a ratio: `QaSpec` grades it against fixed limits
   (ACCEPT 0.4–3.5, REJECT outside 0.2–5.0) and SCADA draws it against 0.3–2.0.
   A 0.1-bar P gave 1491 g/10min, and every QA sample from a running line graded
   REJECT (`mfi_high`). An unfed node reads MFI 0.0, which also grades REJECT.
3. **The silo.** `LineFlow._is_extruder()` was `id.begins_with("extruder")`,
   which also matches `extruder_silo`. On lines 1, 3A and 3B the silo got a screw
   and an MFI proxy, and it sits before the extruder in `_nodes`. The terminal
   (its own `begins_with("extruder_")`) and SCADA (`LineFlow._first_extruder_node`)
   both showed the silo: a buffer reporting "melt 195 °C" and its own die pressure.
4. **Operating point.** `rpm_pct × 200` put every screw at 200 rpm. The melt
   window was a fixed 190–200 °C. The plant runs 95–110 rpm with the melt at
   246–257 °C before the meltfilter (§3).

Why nothing caught it: `test_extruder_screw` asserted `die_pressure > 0` and an
ordering. `test_mfi_proxy` asserts only proportions (20 checks, all ratios), and
it is not wired into `run.sh`. A 1300× scale error passes both.

## 2. Operator rulings (AskUserQuestion, 2026-09-24)

These are choices the operator made from options, not recalled numbers.

- **Which pressure:** *"Die plate, after kopfilter"*. The option said it has
  no documented number, so it is derived as kopdruk minus the kopfilter's dP.
  The alternatives offered were kopdruk before the kopfilter (`MD_vor_SF2`) and
  the pressure before the laserfilter (MP<MF).
- **The silo:** *"Yes, fix it here"*. Only the real extruders get the screw model.
- **rpm and melt:** *"Fix them too"*. Bring rpm and melt temperature to the
  trend bands, then calibrate the pressure at that point.

"Spuitkop" (the terminal's old row label) appears in no plant document. The
row now reads **"Matrijsdruk (na kopfilter)"**, using *matrijs*, the plant's word
for the die plate (EREMA pelletiser docs, `messen-matrijsplaat-slijtage`).

## 3. Sources for every number

| Quantity | 3A | 3B | Source |
|---|---|---|---|
| screw rpm at `rpm_pct` 1.0 | 95 | 110 | "Snelheid hoofdmotor" p50, EREMA WinCC archive 2023-06-19..28 (`trends_overview.md` §2, `src/data/plant/trends/extruder_trends_summary.json`) |
| melt window / setpoint | 247–265 / 257 °C | 230–257 / 246 °C | "Smelt temperatuur voor meltfilter" operating band (p5–p95 of running data) / p50, same archive |
| nominal output | 908 kg/h | 799 kg/h | "Output" p50, same archive |
| die plate at nominal | 120 bar | 140 bar | **DERIVED.** FORM-008 rows 25/26, "Kopdruk kopfilter" 3A 120–150 / 3B 140–155 bar (`checklist_3a_3b.md`). kopdruk = die plate + the kopfilter's dP, and a fresh pack's dP is about 0, so the bottom of the window is the die plate |
| MFI anchor | — | 799 kg/h, 140 bar, 246 °C → 1.0 | the 3B row above. **The 1.0 is not a plant number**: no document gives CeDo's granulaat MFI, and `QaSpec`'s band is a labelled placeholder. 1.0 was the proxy's own design target and is kept |

Lines 1, 3C and 6 have no trend export and no FORM-008 kopdruk row. They
**carry the 3B profile**, and the screw says so (`profile_carried = true`,
printed by the guard as `info`, never gated). The docs do hold single-frame
readings that could seed their own profiles: 3C BluPort 105 rpm at 1376 kg/h
and 217 °C before the meltfilter (`PHOTO-erema-bluport-lijn3C-trend-8curves-2`),
3C at the recipe max 130 rpm / 1636 kg/h (`OTHER-erema-hmi-bluport-lijn3C`),
and line 6 at 110 rpm / 1186 kg/h (`PHOTO-erema-bluport-lijn6`). Line 1's
checklist gives only a 165 °C laserfilter zone. One frame each is not a band.

What stayed heuristic (no source, unchanged): the rheology (`CONSISTENCY_K`,
n = 0.35, Arrhenius coefficient) and the heat couplings. At a ~250 °C melt the
shear heat barely beats the ambient loss. At the screw's 200-rpm ceiling the
melt overshoots its barrel by only +7.5 °C, and the cooling fan settles at 1.5 %.
The lumped barrel setpoint is the trend p50, because FORM-008 rows 23/24 give
seven zone setpoints (200-235-175-240-245-250-255) that a one-node model
cannot place.

## 4. What changed

- `ExtruderScrew`: `PROFILES` (3A, 3B) with the numbers above, and
  `configure_for_extruder(id)`, which sets `profile_carried` for lines without
  their own profile. `die_pressure = die_plate_nominal_bar · (eta/eta_nominal) ·
  (throughput/nominal)`. This is the same drag-flow form as before, anchored at
  the nominal point instead of a free resistance constant. The fan's PI setpoint
  and `melt_in_target_band()` read the profile's window.
- `LineFlow`: `_is_extruder(id, process)` also requires process `meltfilter`,
  so the silo is out. A new screw is configured for its extruder id. The rpm is
  `rpm_pct × rpm_nominal`. The SCADA melt band is the line's window, not 185–205.
- `MfiProxy`: `MFI_GAIN` is solved from the `CAL_*` anchor (0.0856, was 0.263).
- `QualityAnalysisTerminal`: reads the first node that carries the screw model
  (the same pick SCADA makes), and the row is relabelled.
- `test_extruder_screw`: runs at the profile's barrel. "Hard-driving" is the
  screw's 200-rpm ceiling. A new check verifies the fan pulls the melt toward its setpoint.

## 5. Measured after

`src/tests/test_screw_die_plate_bar.tscn` (wired into `run.sh`) puts four macro
lines on one LineFlow, 400 m apart. It feeds each extruder at its profile's
nominal output for 300 s. Result: **PASS (34 ok, 0 fail)**, 68 s, on the
pre-merge tree. After merging `main` (#278) and adding A4b: **PASS (36 ok, 0 fail)**.

| extruder | profile | screw | output | melt | die plate | MFI | QaSpec |
|---|---|---|---|---|---|---|---|
| `extruder_3a` | 3A | 95 rpm | 908 kg/h | 251.9 °C (band 247–265) | **128.2 bar** (FORM-008 120–150) | 1.42 | ACCEPT |
| `extruder_3b` | 3B | 110 rpm | 799 kg/h | 244.0 °C (band 230–257) | **143.7 bar** (FORM-008 140–155) | 0.93 | ACCEPT |
| `extruder_1` | 3B, carried | 110 rpm | 799 kg/h | 244.0 °C | 143.7 bar | 0.93 | info only |
| `extruder_screw` (3C) | 3B, carried | 110 rpm | 799 kg/h | 244.0 °C | 143.7 bar | 0.93 | info only |

The melt settles a few °C under its p50 because the fan can only cool. So the
die plate reads a little above the window's bottom, not on it. The terminal and
SCADA read `extruder_1`, the first extruder in the world, and no silo carries a
screw (0 of 3).

Mutation proofs are in §7.

### The open model-form question: the plant's die-side pressure does not follow output

> **Answered 2026-09-25, see §10.** The 96 / 227 bar below came from a probe
> that held the screw at 110 rpm while the output more than doubled. Both
> models now carry a power-law die, P ∝ Q^0.35, by operator ruling
> (`docs/plant/operator_rulings_2026-09-25.md`).

`tools/audit/fit_kopdruk_vs_output.py` pairs every kopdruk sample with the
nearest output and rpm samples from the downsampled WinCC curves (running
samples only):

| line | pairs | log kopdruk ~ log output | log output ~ log rpm | kopdruk median by output (300–600 / 600–800 / 800–1000 / 1000–1400 kg/h) |
|---|---|---|---|---|
| 3A | 648 | exponent −0.129, R² 0.037 | 0.851, R² 0.775 | 156 / 153 / 162 / 142 bar |
| 3B | 719 | exponent 0.007, R² 0.000 | 1.013, R² 0.915 | 145 / 149 / 152 / 145 bar |

Output follows the screw, but the pressure before the kopfilter stays flat
across the whole output range. The screw model's die plate is **proportional**
to output: 3B reads 96.0 bar at the band's 534 kg/h, 143.7 at 799 and 227.1 at
1263. The plant's kopdruk band is 106–166. The guard prints this as `info` and
does not gate it.

It is left as it is on purpose. The proportionality is what keeps the MFI
estimate independent of output: with P ∝ η·Q, Q cancels in `Q / (P·η)`. A flat
or power-law die makes MFI climb with output at an unchanged melt, so the die
form and `MfiProxy` have to change together. Two things would settle it: the
operator's word on *why* the plant's pressure is flat (does the melt pump hold
it?), and a decision on what the MFI estimate should key on once it is.

## 6. Other open items

- **Two models carry the same die plate.** #278 (merged while this change was
  in review) gave ExtruderModel `die_plate_bar`, `kopdruk_bar` and
  `mp_before_laserfilter_bar` (`docs/plant/operator_rulings_2026-09-24.md`),
  with the same derivation: `Extruder3A/3B.tres` `die_plate_nominal_bar` 120 /
  140 bar. Check A4b of the guard asserts the two numbers agree, so a change
  to one without the other goes red.
- **`test_mfi_proxy` is not in `run.sh`.** It is a `--script` suite, and every
  check it makes is a ratio. The absolute level is now guarded by B8 and A6 of
  `test_screw_die_plate_bar`.
- **The silo does not feed the extruder on 3A or 3B.** In the first probe,
  feeding 3A's `extruder_silo` at 950 kg/h showed the silo moving 6.0 kg/s (its
  full rate) while `extruder_3a` read 0 kg/h. The edges explain it: a
  silo ↔ compactorband 2-cycle on 3A, and a silo with no in-edge on 3B (§8).
  Measured, not fixed: it is a flow-graph defect, not the screw.
- **The MFI band itself is a placeholder** (`QaSpec`, `needs-operator`).

## 7. Mutation proofs

Each mutation was applied alone to the fixed tree, the guard was run, and the
file was restored from a saved copy (verified byte-identical afterwards). All
eight turn it red with 0 SCRIPT ERROR lines.

| # | mutation | result | what went red |
|---|---|---|---|
| M1 | old die formula `6.5e-4 · eta · throughput/0.5` | 27 ok, **7 fail** | B6/B7 (0.1 bar), B8 (MFI 2335 / 1930), C2 (row "0.07 bar") |
| M2 | `_is_extruder` back to the id prefix | 13 ok, **2 fail** | B1 (3 of 3 silos carry a screw), B1b; the suite stops there |
| M3 | `rpm_pct × 200` | 27 ok, **7 fail** | B4 (200 rpm), and through shear-thinning B6/B7 (74 / 95 bar), C2 |
| M4 | barrel setpoint back to 195 °C | 26 ok, **8 fail** | B5 (melt 200 / 203 °C), B6/B7 (252 / 246 bar), B8 (MFI 0.22 / 0.21) |
| M5 | `MFI_GAIN` back to 0.263 | 32 ok, **2 fail** | A6 (anchor reads 3.07), B8 (3A MFI 4.37 → REGRADE) |
| M6 | terminal back to `begins_with("extruder_")` | 31 ok, **3 fail** | C1 (reads the silo), C2 ("0.00 bar"), C3 (SCADA reads another node) |
| M7 | LineFlow skips `configure_for_extruder` | 29 ok, **5 fail** | B2 ×3 (profiles not set / not flagged), B4 (3A at 110 rpm), B5 (3A melt 244 °C) |
| M8 | `Extruder3A.tres` `die_plate_nominal_bar` 120 → 125 (after the merge) | 35 ok, **1 fail** | A4b (screw 120 vs ExtruderModel 125) |

## 8. The extruder_silo's edges (measured, not fixed)

`probe_screw_die_pressure -- <line> 950 silo` feeds the `extruder_silo` at
950 kg/h for 300 s on the fixed tree and prints its graph edges:

| line | silo in-edges | silo out-edges | extruder after 300 s |
|---|---|---|---|
| 1 | `cyclone#35` | `compactorband#37` | `extruder_1` 1203 kg/h (reached) |
| 3A | `blower#21`, **`compactorband#23`** | **`compactorband#23`** | `extruder_3a` **0 kg/h** |
| 3B | **none** | `compactorband#17` | `extruder_3b` **0 kg/h** |

On 3A the silo and its compactorband feed each other. That is the sibling
2-cycle in CLAUDE.md's traps, and it explains the silo "moving" 6 kg/s in the
first probe. On 3B nothing feeds the silo, and 300 s of feed into it did not
reach the extruder. Both are flow-graph defects in the line tails, separate from
the screw model, and left for their own change.

## 9. Verification run (2026-09-25, fixed tree)

| step | result |
|---|---|
| parse sweep | `Result: 450 ok, 0 fail`, `RESULT: PASS` (the 127 SCRIPT ERROR lines are the sweep's documented autoload-identifier noise, and none names a changed file) |
| `test_screw_die_plate_bar` | PASS (34 ok, 0 fail) |
| `test_extruder_screw` | 13 ok, 0 fail |
| `test_mfi_proxy` | 20 ok, 0 fail |
| `test_tag_snapshot` | PASS (28 ok, 0 fail, 1 skip). The skip is data-gated: no `allernieuwste_*.json` exists in `app_userdata` to guard |
| `test_qa_loop` | PASS (14 ok, 0 fail, 0 skip) |
| `test_qa_spec` | 24 ok, 0 fail |
| `test_qa_terminal` | Failures: 0 |
| `test_die_pressure_bar` | PASS (23 ok, 0 fail) |
| `lint_unused_params` | 0 unused parameters |

`user://world_layout.json` hashed identical before and after the two MainWorld
suites, and matches the `.bak` taken first.

After merging `origin/main` (`bae70ee`, which brought #278's ExtruderModel
rework): parse sweep `Result: 454 ok, 0 fail`; `test_screw_die_plate_bar`
PASS (36 ok); `test_extruder_screw` 13 ok; `test_mfi_proxy` 20 ok;
`test_die_pressure_bar` PASS (20 ok, main's revision); `test_extruder_melt_pressures`
PASS (44 ok); `test_qa_spec` PASS; `lint_unused_params` 0.

## 10. The model-form question, answered (2026-09-25)

Operator rulings, with his words and what the data could and could not settle:
`docs/plant/operator_rulings_2026-09-25.md`. Every trend number below is
printed by `tools/audit/fit_kopdruk_vs_output.py`.

### 10.1 The gap was the probe

§5's 96.0 / 143.7 / 227.1 bar came from the old section D. It fed a 3B screw
534, 799 and 1263 kg/h while holding it at **110 rpm**. The plant does not run
that way. Pair each output sample with the nearest main-motor sample and the
plant turns **60 / 80 / 120 rpm** at those three outputs (3A: 60 / 88 / 110 at
595 / 908 / 1082 kg/h). The old law took the viscosity at the SCREW's shear
rate, which falls as rpm^(n−1). Along the plant's own rpm path it therefore
read roughly Q^0.35 already: **3A 111.6 / 128.2 / 128.4 bar, 3B 120.2 / 143.7 /
170.0 bar**, against kopdruk bands of 103–173 and 106–166. These are the D1
lines of mutation M1 below, which puts the old law back into the new suite.

§5's other claim, that "with P ∝ η·Q, Q cancels in Q / (P·η)", held only at a
fixed rpm. The η in the die was the screw's, so along the plant's path the MFI
climbed as rpm^0.65.

### 10.2 The ruling

- Why the plant is flat: *"operator-specific, could even be a test experiment
  from the office to run without head fitters inzstalled"*. So the trend is a
  band to stay inside, not a law to fit. CLAIMED. The downsampled curves can
  neither confirm nor rule out the packs (rulings doc §3).
- What the MFI should key on: *"leave as low-priority for the beta version"*.
- ExtruderModel: *"Both models"*.
- Which law, asked after he saw 10.1: *"P ∝ Q^0.35"*, with MfiProxy taking
  only the matching exponent.

No melt pump explains it on 3A/3B: `operator_rulings_2026-08-31.md` §1 says
lines 1, 3A and 3B have none. `operator_rulings_2026-09-24.md` §2 puts "the MPU
or melt pump" upstream of the kopfilter. That contradiction is still open.

### 10.3 What changed

| file | change |
|---|---|
| `ExtruderScrew.gd` | `die_pressure = die_plate_nominal · K(T)/K(T_mid) · (Q/Q_nom)^n`, n = `POWER_LAW_N`. K(T) is the melt's viscosity at ONE shear rate (the nominal screw's), so only the melt temperature moves it; the screw's rpm enters only through the heat it puts in the melt |
| `ExtruderModel.gd` | `DIE_FLOW_INDEX` = `ExtruderScrew.POWER_LAW_N` (preloaded, one number). `_set_melt_pressures(throughput_norm, melt_factor)`: the die plate is `nominal · throughput_norm^n · melt_factor`; MP>MF stays linear in throughput |
| `MfiProxy.gd` | `MFI = MFI_GAIN · Q^n / (P · η(T))`, `DIE_FLOW_INDEX` from the screw, `MFI_GAIN` re-solved so the anchor still reads exactly 1.0. Nothing else: the MFI is the operator's "low priority" |
| `test_screw_die_plate_bar` | D gated (D0–D3), E added (E0–E2): 34 → 53 checks; 55 after merging `main`, whose A4b (#285) came in beside them |
| `test_extruder_screw` | the "thinner melt" check now requires the hotter melt it names; + "at a matched melt, rpm alone does not move the die plate", + "2x flow → 2^n": 13 → 15 |
| `test_mfi_proxy` | proportions in Q^n; + "2x flow at the power-law die's 2^n pressure → same MFI"; + "Q exponent == `ExtruderScrew.POWER_LAW_N`" (see M3): 20 → 22 |
| `fit_kopdruk_vs_output.py` | second half: melt vs output, plant rpm per output, sawtooth check |

### 10.4 Measured after

`test_screw_die_plate_bar`, **PASS (53 ok, 0 fail)**, 0 SCRIPT ERROR lines:

| line | output (band low / p50 / high) | rpm driven (the plant's, onto `rpm_nominal`) | die plate | kopdruk band | at the nominal rpm (info) |
|---|---|---|---|---|---|
| 3A | 595 / 908 / 1082 kg/h | 64.8 / 95.0 / 118.8 | **114.6 / 128.2 / 132.4 bar** | 103–173 | 110.6 / 128.2 / 136.3 |
| 3B | 534 / 799 / 1263 kg/h | 82.5 / 110.0 / 165.0 | **129.5 / 143.7 / 164.3 bar** | 106–166 | 124.8 / 143.7 / 168.7 |

- D2: at one melt the die plate's high/low ratio is (Q ratio)^0.35 (3A 1.2328,
  3B 1.3516; a linear die reads 1.8185 / 2.3652).
- D3: at one melt the MFI does not follow output (3A 1.3094, 3B 0.9303 at both
  band edges).
- E: ExtruderModel 3B, run to RUNNING at 73.5 / 110.0 / 173.9 rpm, carries
  0.668 / 1.000 / 1.581 × nominal and reads a die plate of 121.6 / 140.0 /
  164.3 bar = 140 × Q^0.35. MP>MF stays linear: 16.7 / 25.0 / 39.5 bar.
- The nominal points of sections B and C did not move (3A 128.2 bar, 3B 143.7
  bar). 3A's nominal MFI went 1.42 → 1.31, because 3A's nominal output (908)
  is not the 799 kg/h anchor. It still grades ACCEPT.

### 10.5 Mutation proofs

Each mutation was applied alone to the fixed tree and the suites were run.
The files were then restored from saved copies, and md5 was checked identical
after every one. Every run printed its verdict with 0 `^SCRIPT ERROR` lines.

| # | mutation | `test_screw_die_plate_bar` | unit suite | what went red |
|---|---|---|---|---|
| M1 | the old screw law, η(screw rpm)/η_nom · Q | 48 ok, **5 fail** | `test_extruder_screw` 13 ok, **2 fail** | D1 3B top 170.0 bar; D2 ×2 (ratios 1.8185 / 2.3652); D3 ×2 (the new proxy on the old die: MFI 1.72 → 1.17 on 3A); matched melt 119.7 vs 270.2 bar; 2x flow → x2.0000 |
| M2 | linear exponent, temperature-only K | 46 ok, **7 fail** | `test_extruder_screw` 14 ok, **1 fail** | D1 ×3 (3A low 87.0, 3B low 99.7, 3B high 221.3 bar); D2 ×2; D3 ×2; 2x flow |
| M3 | MfiProxy not changed with the die (`DIE_FLOW_INDEX` 1.0) | 51 ok, **2 fail** | `test_mfi_proxy` 21 ok, **1 fail** | D3 ×2 (MFI 1.08 → 1.59 on 3A, 0.72 → 1.25 on 3B across the band); the new "Q exponent == the die's n" check |
| M4 | ExtruderModel's die plate linear in Q | 51 ok, **2 fail** | — | E2 ×2 (93.6 / 221.3 bar instead of 121.6 / 164.3) |
| M5 | ExtruderModel's index drifts to 0.5 | 50 ok, **3 fail** | — | E0; E2 ×2 |
| M6 | test-side: section D at the fixed nominal rpm | 52 ok, **1 fail** | — | D1 3B top 168.7 bar. D1 is not vacuous: along the plant's rpm it is the law that keeps 3B inside the band |

M3's first run against `test_mfi_proxy` stayed **21 ok, 0 fail**. Its proportion
checks read the exponent from the proxy itself, so they follow any exponent.
The check pinning it to `ExtruderScrew.POWER_LAW_N` was added for that reason,
and M3 then turned it red (row above).

### 10.6 Verification run

On the fixed tree (`6b28207` + this change), 2026-09-25 02:39–03:01, one suite
at a time. Every line below is the suite's own verdict, with 0 `^SCRIPT ERROR`
lines in every log.

| step | result |
|---|---|
| parse sweep | `Result: 454 ok, 0 fail`, `RESULT: PASS`. No SCRIPT ERROR line names a changed file |
| `test_screw_die_plate_bar` | PASS (53 ok, 0 fail) |
| `test_extruder_screw` | 15 ok, 0 fail |
| `test_mfi_proxy` | 22 ok, 0 fail |
| `test_die_pressure_bar` | PASS (20 ok, 0 fail); exit 139 in teardown, after the verdict. It also reads 20 ok on `6b28207` with this change reverted: §9's 23 is from before #278's merge rewrote the suite |
| `test_extruder_melt_pressures` | PASS (44 ok, 0 fail) |
| `test_extruder_brain_wired` | PASS (24 ok, 0 fail) |
| `test_qa_loop` | 14 ok, 0 fail, 0 skip. Its sample grades REGRADE by design: the suite feeds a NaN MFI (`mfi_unavailable`, `polymer_impure`) |
| `test_qa_spec` | 24 ok, 0 fail, 0 skip |
| `test_qa_terminal` | Failures: 0 |
| `test_tag_snapshot` | 28 ok, 0 fail, 1 skip. The skip is data-gated, as in §9 |
| `lint_unused_params` | 449 files, 0 unused parameters |

`user://world_layout.json` hashed `e046af7d…` (the operator's kept file) before
and after, and every MainWorld suite first checked that hash.

**After merging `origin/main` (`64921ff`: #284's melt-following dMP and #285's
A4b).** The conflict in `ExtruderModel` was resolved to the two-argument
`_set_melt_pressures(throughput_norm, melt_viscosity_factor)`, which uses #284's
new property. Its one-argument call would not have parsed against this change.
Results: parse sweep `454 ok, 0 fail`; `test_screw_die_plate_bar` PASS (55 ok);
`test_extruder_screw` 15 ok; `test_mfi_proxy` 22 ok; `test_die_pressure_bar`
PASS (21 ok); `test_extruder_melt_pressures` PASS (53 ok, main's dMP suite);
`test_extruder_brain_wired` PASS (24 ok); `test_qa_loop` 14 ok; `test_qa_terminal`
0 failures; `lint_unused_params` 0; `test_qa_spec` 24 ok; `test_tag_snapshot`
28 ok, 1 data-gated skip. Every log had 0 `^SCRIPT ERROR` lines. The last two
first waited out another session's `test_jam_baseline`, and
`world_layout.json` hashed `e046af7d…` before and after.

**An incident during this session, not caused by it.** At 02:34:33 the file was
rewritten to `bd62352d…`, with the jam-baseline fixture gate in
`structure_items` **twice**. At that moment two OTHER sessions were running
`test_jam_baseline` at once on the shared `app_userdata` (worktrees
`clever-hypatia-945f15` and `cedo-sim-sound-processing-0667d4`, from 02:27:38
and 02:28:52). The first verification batch was stopped before its MainWorld
suites, so it could not snapshot and restore that version. After both jam runs
ended, the file was back to `e046af7d…` at 02:38:01. **`world_layout.json.bak`
still holds the two-gate version** (11108 bytes, 02:36:08): it is AtomicFile's
fallback if the primary is ever unreadable. It was left alone
(`CLAUDE.md`: do not edit that file without asking him).

### 10.7 Still open

- **3B's top edge at the nominal rpm reads 168.7 bar**, 2.7 above the band
  (info line, not gated). LineFlow caps `rpm_pct` at 1.0, which is the
  profile's `rpm_nominal`, so a 3B fed 1263 kg/h in a world turns 110 rpm and
  reads that. The plant turns 120 rpm there, and scaled onto the profile that
  is 165 rpm.
- **The profile pairs two independent p50s.** `rpm_nominal` is the rpm
  curve's own p50 (3A 95, 3B 110). Paired, the plant turns 88 / 80 rpm at the
  output p50 (908 / 799 kg/h). D scales the plant's rpm by its ratio for that
  reason. The profile is unchanged.
- **ExtruderModel's stop ramp compounds.** `_scale_melt_pressures(rpm_frac)`
  multiplies the previous tick's pressures by rpm_frac every tick. Measured:
  1.2 s into STOPPING the screw is at 76 % rpm and the die plate at 19 % (26.9
  of 140 bar). The same holds for MP>MF. It was there before this change and
  is being fixed in its own session (worktree `elegant-liskov-dd1577`, on
  `main`). **When the two branches meet**, STARTING/STOPPING must call
  `_set_melt_pressures(throughput_norm, melt_factor)`. Both arguments are
  required, so a leftover one-argument `_set_melt_pressures(q * m)` is a parse
  error (measured) rather than a silent `pow(q·m, n)`.
- **The MFI's temperature sign** (a hotter melt reads a higher MFI, unlike a lab
  MFI at 190 °C), and whether the MFI should key on the material at all: the
  operator's "beta".
