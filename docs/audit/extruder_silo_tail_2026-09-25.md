# Extruder-silo tails on 3A and 3B: wired wrong, pinned, guarded (2026-09-25)

Follow-up to `extruder_screw_die_plate_2026-09-24.md` §8. That section measured
the bug but did not fix it. Its probe fed 950 kg/h into the `extruder_silo` on
3A and 3B, and after 300 s the extruder read 0 kg/h on both lines.

## 1. What LineFlow wired (measured, before)

`src/tests/dump_line_graph.tscn -- <line_id>` is new: a generic dump for any
macro line. It marks each edge **explicit** (the source carries BuildMode's
`lf_explicit_outs`) or **geometry** (the nearest-input-port fallback), and it
prints the fallback's candidate list in the order the linker walks it.

| line | silo in | silo out | band out | extruder in |
|---|---|---|---|---|
| 1 | `cyclone` (explicit) | `compactorband` | `extruder_1` (explicit) | `compactorband` |
| 3A | `blower`, **`compactorband`** | `compactorband` | **`extruder_silo`** | **none** |
| 3B | **none** | `compactorband` | **`blower`** (the booster) | **none** |

On 3B the booster blower fed **its own tussenventilator cyclone**, which fed it
back.

## 2. Why the fallback chose those edges

1. **The extruder is out of range.** The distance from the band's discharge
   (`wout`) to the extruder's inlet (`win`), in 3-D, is 15.22 m on 3A and
   14.24 m on 3B and line 1. `MAX_LINK_DIST` is 14.0 and exclusive
   (`d >= 14` is skipped), so the band never saw the extruder as a candidate.
   It took the nearest inlet it could see, which lies behind it: the silo
   (8.51 m) on 3A, and the booster blower (7.55 m) on 3B. Line 1 has the same
   gap, which is why its tail was pinned on 2026-09-24.
2. **The fallback's cycle guard is called with its arguments swapped.** The
   linker calls `_link_best_target(...)` → `_creates_cycle(best, src_idx)`.
   `_creates_cycle(from, to)` is documented and implemented as "would edge
   from → to close a cycle": it runs a DFS from `to` and looks for `from`. The
   call therefore asks whether the source already reaches the target. In the
   geometry pass a source has no out-edges yet, so the answer is always no,
   and the guard never refuses a back-edge. On 3B the booster blower's nearest
   inlet is its own cyclone's (2.43 m, against the silo's 4.66 m). That edge
   closed a 2-cycle and left the silo with no in-edge.

3A's blower → silo edge was correct, but only because the silo's inlet is
0.32 m nearer than the band's (4.66 m against 4.98 m).

## 3. The fix: pinned in the SEQs, per the plant docs

The chain follows `docs/plant/lijn_3a_flow.md` edges 28-31 (on 3A the silo's
feeder is M11b's blower, ruling 2.1-B) and `lijn_3b_flow.md` edges 19-22 (the
tussenventilator blows "all the way into the extruder silo", ruling 3.1-B).
`"explicit_from_prev": true` is set on `extruder_silo`, `compactorband` and
the extruder, in both `LINE_3A_SEQ` and `LINE_3B_SEQ`. No entry was inserted
or removed, so no `macro_index` shifts. `user://macros/` holds no line
overrides, only `*.probe-bak-20260917` copies.

After the fix, the silo chain on every line is `feeder → silo → band →
extruder`, and the silo chain holds no cycle.

Physical side effects: `_make_connector` draws a conduit per edge.
- **3A: none.** The removed band → silo edge and the added band → extruder
  edge both run uphill, and a gravity gutter is only drawn for a drop over
  0.4 m.
- **3B: two connectors removed, one added.** Removed: a 7.5 m collider gutter
  from the band back to the blower, and the blower → cyclone duct. Added: the
  4.7 m blower → silo duct.

## 4. Guard: `test_extruder_silo_chain` (41 checks, wired into `run.sh`)

Lines 1, 3A and 3B stand in one world, 400 m apart, with one LineFlow.

- **G**: the exact neighbours by name, and an explicit 2-cycle search. A
  sibling 2-cycle passes in/out-degree checks: on 3A the band had in-degree 1
  and out-degree 1.
- **F**: 950 kg/h is fed into the silo's feeder for 120 s, then the pipes
  drain for 60 s. The kg must reach the silo, the band and the named
  extruder. No chain node may process more than 1.05 × the kg fed; a cycle
  circulates mass.

Measured on the fixed tree: 31.7 kg fed per line and 31.7 kg into each
extruder. First kg at the extruder: 19.6 s (3A), 23.8 s (1), 27.4 s (3B).
The run took 51.8 s of wall time for 1800 ticks, with 0 SCRIPT ERROR lines.
`world_layout.json` hashed identical before and after (`e046af7d…`).

### Mutation proofs

Each mutation was applied alone to the fixed `BuildMode.gd`. The file was
restored after each run and checked md5-identical, and no run printed a
SCRIPT ERROR line.

| # | mutation | result | red |
|---|---|---|---|
| M0 | whole fix reverted (`BuildMode.gd.bak`) | 26 ok, **15 fail** | 3A G2/G4/G5/G6 + F3/F4 (the silo processed 457.8 kg from 31.7 fed); 3B G1/G2/G4/G5/G6 + F1-F4 (blower 864 kg) |
| M1 | 3A `extruder_3a` pin | 35 ok, **6 fail** | G2 G4 G5 G6 (`extruder_silo <-> compactorband`), F3 0.0 kg, F4 |
| M2 | 3B `extruder_silo` pin | 34 ok, **7 fail** | G1 G2 G6 (`cyclone <-> blower`), F1-F4 |
| M3 | 3B `extruder_3b` pin | 37 ok, **4 fail** | G4 G5 F3 F4. The band closes a **3-cycle** (band → blower → silo → band) that G6 cannot see. F4 catches it: the blower processed 376.7 kg |
| M4 | 3A `extruder_silo` pin | 41 ok, 0 fail | not load-bearing today (0.32 m margin, see §2) |
| M5 | 3A `compactorband` pin | 41 ok, 0 fail | not load-bearing: the band is the silo's nearest inlet (2.64 m) |
| M6 | 3B `compactorband` pin | 41 ok, 0 fail | not load-bearing: nearest at 2.09 m |

M4-M6 pin edges that the fallback currently gets right. They stay pinned so
that a K-mode jog cannot flip them.

## 5. Still wrong, measured, not fixed here

The swapped cycle guard leaves more geometry 2-cycles on these same lines.
They are listed by `dump_line_graph`'s `[CYCLES]` section.

- **3A infeed:** `wind_sifter <-> blower` (infeed blower 2). The big shared top
  cyclone over the mengsilo has **no in-edge**, so the graph has no path from
  the mech dryer to the mengsilo. This was read off the dump; it was not
  measured in kg. This is probably what `test_line1_throughput`'s
  2026-09-16 note means by "3A's mass parks in a blower". The silo-chain fix
  above therefore makes the 3A tail work, but not the whole of line 3A.
- **Lines 1 and 3B:** `centrifuge <-> weegschaal`, so `voorraad_silo` has no
  in-edge. 3B's extruder was demoted to role `process` on 2026-07-16 so that
  granulate would reach that silo. On 3A the bigbag branch tags the
  weegschaal, so this cycle does not form there.
- **Every line:** `lump_cart_spot <-> lump_cart` (furniture that becomes a flow
  node), and `compressor_a <-> compressor_b`.

The general fix is to call `_creates_cycle(src_idx, best)`. That changes the
geometry fallback for every line, so it needs its own measurement: dump every
macro line before and after, check each rerouted edge against the plant docs,
and run the full harness. It is filed as a separate task.

## 6. Verification (2026-09-25)

| step | result |
|---|---|
| parse sweep | `Result: 454 ok, 0 fail`, `RESULT: PASS`; no SCRIPT ERROR line names a changed file |
| `test_extruder_silo_chain` | `PASS (41 ok, 0 fail)` |
| `test_line3a_flow_conformance` | `Result: PASS (0 fail)` |
| `test_line3b_flow_conformance` | `Result: PASS (0 fail)` |
| `test_line3a_identity` / `test_line3b_identity` | `RESULT: PASS` / `RESULT: PASS` |
| `test_line1_throughput`, `test_macro_part_placement` | `Result: PASS (0 fail)` each |
| `test_lump_cart_overflow` | `Result: PASS (45 ok, 0 fail)` |

Every suite printed 0 `^SCRIPT ERROR` lines. The rc 139s are the documented
teardown segfault, which comes after the verdict. `world_layout.json` hashed
`e046af7d…` before and after the batch.

**The full harness was NOT run.** At the time, other sessions were running
suites against the same `app_userdata` (`test_jam_baseline` from
`_iso_kind-brattain`, `test_bale_weight_variance` from
`cedo-sim-sound-processing`, and a parse sweep from `clever-hypatia-945f15`).
CLAUDE.md forbids two harnesses sharing it.

## 7. The pins do NOT survive a save → load (measured, not fixed)

> **FIXED the same day:** `docs/audit/macro_edges_reload_2026-09-25.md`.
> `load_layout` re-derives every saved line's explicit edges with the function
> the build uses (`BuildMode.macro_flow_edges`), and `test_macro_edges_reload`
> guards it by name and by kg. The measurement below is the before-picture
> and is left as it was.

`src/tests/probe_explicit_edges_roundtrip.tscn` builds lines 1, 3A and 3B and
calls `BuildMode._save_layout()`. It then boots a fresh BuildMode from that
file (`load_layout()`, the same call MainWorld makes) and rebuilds LineFlow.
It was run under a scratch `APPDATA`, with both file paths redirected to
probe-only names.

| | nodes | edges | nodes with `lf_explicit_outs` |
|---|---|---|---|
| built | 119 | 121 | 47 |
| reloaded | 119 | 113 | **0** |

After the reload every tail is back to geometry wiring:

- **3A:** the silo ↔ band 2-cycle returns and `extruder_3a` has no in-edge.
- **3B:** the silo has no in-edge.
- **Line 1:** `extruder_1` loses its in-edge too; its band feeds a blower.

`_save_layout` persists `macro_id`, `macro_index` and `macro_anchor`, but not
`lf_explicit_outs`. The only caller of `_add_explicit_out` is
`_build_full_line`. So every explicit edge of every macro is lost on reload:
these pins, line 1's 2026-09-24 pins, the 3B L/R split, the 3A recirc, and
line 1's twin streams.

What `test_extruder_silo_chain` proves is therefore narrower than "the game":
it covers a line **in the session it is built**.

Checked read-only on 2026-09-25: none of the operator's own saves on this
machine holds macro-built lines. The only factory files with `macro_id`
entries are test slots (`__npc05real__`, `__extruderwired__`,
`__jambaseline__`, `__outdoorroute__`, `__eventbus_tap__`) plus
`sandbox_layout.json` / `gauntlet_layout.json`. So his world is not affected
today. It will be the first time he builds a line and reloads.

The fix is to re-derive the tags on load from `macro_id` / `macro_index`, by
replaying `_build_full_line`'s branch bookkeeping over the loaded nodes. It
touches every macro, so it is its own change.
