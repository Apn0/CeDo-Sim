# Project sweep — 2026-08-23

_A full sweep of `main` as merged (`e48479b`, PR #83). Ran on Linux against a
real `Godot_v4.6.3-stable_linux.x86_64`, so every number below was produced, not
reasoned about. Headline: **HEAD did not compile**, and the harness said it was
fine._

---

## 0. The state HEAD was actually in

`src/build/PlaceableCatalog.gd:11071` referenced `grp_hot` — a local belonging to
`show_die_face_state()`, a *different function* 20 lines further down. GDScript
resolves that at parse time, so the file did not parse. Measured cascade, from a
real boot log:

```
SCRIPT ERROR: Parse Error: Identifier "grp_hot" not declared in the current scope.
          at: GDScript::reload (res://src/build/PlaceableCatalog.gd:11071)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: GDScript::reload (res://src/sim/LineFlow.gd:0)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: GDScript::reload (res://src/build/BuildMode.gd:0)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: GDScript::reload (res://src/tests/test_line3c_seq_alignment.gd:0)
```

LineFlow, BuildMode and 27 of the 93 test scripts were down. And a headless suite
whose script fails to compile does not report FAIL — it boots **with no script
attached** and idles forever with nothing to call `get_tree().quit()`. Measured:
`test_line3c_seq_alignment.tscn`, a pure-data suite that finishes in seconds,
ran to a 2-minute timeout with no verdict. This is the *same* failure this repo
already chased in the `1b29087` "hang" (CLAUDE.md documents it) — third time in
this file's history that a merge has done this.

`src/scenes/world/BaleYardManager.gd` was mangled in the same way, and its own
header already documents merge `4ce7627` doing it a *first* time.

### Where it came from

Not a typo someone made. A merge **reverted a fix**:

| commit | `grp_hot.add_child` present | `_spawn_yard` |
|---|---|---|
| `ed9198b` (wip branch tip) | 0 — fixed | 0, inline |
| `084c7e2` | 0 — fixed | 0, inline |
| `7b72ecf` (merge) | **1 — reverted** | 1, mangled |
| `e48479b` (PR #83, = main) | **1 — reverted** | 1, mangled |

`ed9198b` carried the correct line — `smoke_mm.set_instance_transform(i, ...)` —
and the merge resolution took the older side. Every *other* commit on that branch
survived the merge intact (verified: `shot_common.gd`'s blank-frame guard, the
`run.sh` npc05 gate, `tools/audit/*.py`, the DETAIL_STANDARD doc, the `.gd.uid`
sidecars). Only the two files that actually conflicted were damaged.

### Why nothing caught it

Both harness compile checks had a blind spot, and the defect walked between them:

* **the parse gate** is `--headless --path . --quit`, which boots the main scene.
  The main scene is `MainMenu.tscn`, which loads none of `src/build`, `src/sim`
  or `src/scenes/world`. Measured on the broken tree: **exit 0, zero errors.**
* **the test-script sweep** only walks `src/tests/*.gd`. It *did* go red — 27
  files — but every one reported the same *inherited* error and none of them
  named the file that broke. That reads as test rot, not as "the catalog is
  down".

---

## 1. What was changed

### 1.1 `PlaceableCatalog._build_heetafslag_strand_switcher` — restored (CRITICAL)

Restored `ed9198b`'s form: the smoke wisp goes into `smoke_mm`, the MultiMesh
built ten lines above it for exactly this purpose (`instance_count ==
strand_count`, `mesh == qm`). The reverted per-strand `MeshInstance3D` version
was wrong twice over — it did not parse, and it left `smoke_mm`'s transforms
unset, so all 20 of its instances stay at IDENTITY and the quads pile up on the
switcher origin. It also cost 20 nodes per extruder.

### 1.2 `BaleYardManager` — repaired (CRITICAL)

The merge left the file with BOTH the old inline version and main's extracted
`_spawn_yard()`, interleaved:

* `_spawn_bale_yards_from_layout()` opened its yard loop and then **stopped** at
  the `use_pc` fallback — it never called `_spawn_yard`, never tallied, never
  printed. No yard could ever spawn.
* `_spawn_yard()` carried a duplicated 29-line block re-pasted one indent deeper
  *inside* its own `for i in bales_this_yard:` loop (so `mmi_close`/`mmi_sticker`
  were `add_child`ed once per bale), a second declaration of `safe_yaw` /
  `bale_basis` / `size_y_half` — the parse error — and a tail of caller residue
  (`total_bales`, `total_yards`, the summary print) where its `return` belonged.

Repaired to what the merge should have produced: main's `_spawn_yard` extraction
plus the branch's PC-path (`#221-PC Phase 3`), duplicate excised, tail returning
`bales_this_yard`, and a caller loop rebuilt. The caller enumerates the index
rather than recovering it with `bale_yards.find(y)` — `find` matches by VALUE, so
two identically-drawn yards would both resolve to the first one's index and
`_spawn_yard` would read the wrong `bale_yards_pc` entry.

### 1.3 Hand-built walls now survive a save — FULL_LOGIC_AUDIT #7, **confirmed live**

`BuildMode._place_current()` did not stamp `placeable_id` on a wall.
`_save_layout()` gates on exactly that meta (`BuildMode.gd` ~2996), so the wall
was never serialised: draw a partition, save, reload, the plant is open-plan
again. `build_wall()` cannot set it (a static helper that never receives the id)
and `_finalize_placed()` only writes `height_offset`. The RELOAD path always
stamped it itself (~3369), which is why loading a wall worked and saving one
never did — and why a files-present review passes this.

One line, at the caller, matching the load path.

### 1.4 `Walkie` → `VoiceService` — FULL_LOGIC_AUDIT #12 is **REFUTED**

The audit calls this "All real TTS crew voice is dead every launch" on the
grounds that VoiceService is autoload #13 and Walkie #6, so
`get_node_or_null("/root/VoiceService")` in `Walkie._ready()` is null. The
prescribed `call_deferred` fix was implemented — and then measured, by probing
from inside that function on a real boot:

```
[PROBE] Walkie._ready: /root/VoiceService present = true
```

Godot adds every autoload to `/root` **before** readying them, so declaration
order does not starve the lookup. The connect works and always did. The change
was reverted to inline; what was kept is the extracted, idempotent
`_connect_voice_service()` (so a test can call it, and so calling it twice cannot
double every synthesised line) and a comment recording the measurement, so the
next reader of the audit does not "fix" a working line on a stale doc.

**The audit is a 2026-07-08 snapshot with no per-finding status. Re-measure
before acting** — it says so, and this is what that looks like in practice.

---

## 2. What was added

### 2.1 `tools/regression/parse_sweep.gd` — full-tree parse sweep

Replaces the `src/tests/*.gd`-only sweep in `run.sh`. Walks `src/` and `tools/`,
names the file that actually broke, and does it in **one boot** — ~15 s against
the ~6 min the old 312-engine-start loop cost.

Gated on `ERR_PARSE_ERROR` (43) only, for the same reason as its predecessor:

| tree | result |
|---|---|
| repaired | 47 × `ERR_COMPILATION_FAILED` (36), 0 × 43 → **PASS** |
| `grp_hot` restored | 47 × 36, **1 × 43 naming `PlaceableCatalog.gd`** → FAIL |
| `BaleYardManager` reverted | 47 × 36, **4 × 43** naming it, `MainWorld.gd`, `MapOverlay.gd`, `test_bale_yard_mass_conservation.gd` → FAIL |

The 47 are stable and are an artefact of `CACHE_MODE_IGNORE` re-resolving
dependencies; they print as a note. Gating on them would paint the step
permanently red, and a permanently red step is one everyone learns to skip.

**Two detectors were tried and REJECTED — by mutation, not by argument.** Both
would have shipped as vacuous greens:

* `ResourceLoader.load(f) == null`. A file with a hard parse error still comes
  back **non-null**. This version reported "316 ok, 0 fail" with the broken
  catalog in place, and only the mutation test caught it.
* compiling the file's **source text** into a fresh `GDScript`. A source-only
  script has no `res://` identity, so its own `class_name`, its preloads and its
  `@tool`/`@icon` annotations cannot resolve: 200+ healthy files reported 43.

### 2.2 `src/tests/test_project_sweep_guards.{gd,tscn}` — 19 checks, in `run.sh`

A (die-face smoke, 7) / B (wall persistence on a real MainWorld boot, 7) /
C (crew TTS hookup, 4) + a save-integrity check. Mutation-proven:

| mutation | effect |
|---|---|
| restore the `grp_hot` loop | the whole `.tscn` **hangs** — no verdict at all |
| re-parent the wisp to `mmi_hot` (the naive repair) | A1d red (20 loose wisps) |
| drop `wall.set_meta("placeable_id", …)` | B2 + B3 red (0 structure_items) |
| gut `_connect_voice_service()`'s body | C2 + C3 red |
| revert `_connect_voice_service` to inline | **stays green** — this is the measurement that refuted audit #12 |

---

## 3. Measurements worth keeping

### 3.1 A headless suite cannot assert MultiMesh CONTENT

Measured on 4.6.3, immediately after a successful `set_instance_transform`:

```
buffer size=0
buffer=[]
get_instance_transform(1)=[X: (1,0,0), Y: (0,1,0), Z: (0,0,1), O: (0.0, 0.0, 0.0)]
```

The dummy renderer keeps no CPU-side copy, so `buffer` reads back empty and
`get_instance_transform()` returns identity for every index — regardless of what
was written. The first version of check A asserted exactly this and failed on
**correct** code; the tempting next step is to weaken the check, which would have
buried the finding. Assert a MultiMesh's SHAPE and its NODE GRAPH headless; never
its contents.

### 3.2 What a fresh clone can and cannot prove

`assets/` is gitignored (2.9 GB, `git ls-files assets` → 0) and
`user://world_layout.json` is in git nowhere. Full harness on a clean clone:
**15 of 22 suites PASS**, and every one of the 7 failures is environmental, not
a code defect:

| suite | failing check | cause |
|---|---|---|
| `test_map_frame` | measured building frame never became available | no `assets/models/CeDo_factory_solid.obj` |
| `test_nav_connectivity` | the shell has a measurable footprint | same |
| `test_outdoor_route` | the shell has a measurable footprint | same |
| `test_gate_carve` | the shell has a measurable footprint | same |
| `test_vehicle_spawn_frame` | layout holds ≥1 vehicle marker | no `world_layout.json` |
| `spawn_clearance` (both) | BaleYardManager reachable | `MainWorld.gd:286` only builds it when the layout is authoritative |
| `test_jam_baseline`, `test_npc05_realworld` | timeout / no indoor bin | already-documented defects, plus no layout |

So a green run in a cloud session is a *narrower* claim than a green run on the
operator's machine, and `regression_world_save` reporting `FAIL : building shell
mesh present` there is expected. The suites that DO prove something on a fresh
clone are the pure-data and catalog-driven ones — and `test_bale_yard_mass_
conservation`, which passed non-vacuously ("yard filled 32 slots", 32 MultiMesh
instances, 32 colliders, mass conserved across 3 haul cycles) and is therefore
the behavioural proof that the §1.2 repair works.

### 3.3 The engine is reachable from a cloud session

`Godot_v4.6.3-stable_linux.x86_64` downloads and runs headless here, and
`run.sh`'s `GODOT=` / `PROJ=` / `UD=` overrides work unmodified. There is no
reason for a cloud session to reason about this project instead of measuring it.
The one GDExtension that will not load is `addons/godot_wry` (needs
`libwebkit2gtk-4.1`), which only affects the HMI WebView.

### 3.4 A duplicate-block scan found nothing else

Given two files mangled the same way, the whole tree was scanned for runs of ≥8
identical non-comment lines repeating within one file. 17 files matched; all
spot-checked matches are legitimate parallel idioms (e.g. `CrewManager
._pick_responder`'s three-tier fallback repeats the same nearest-worker loop by
design). **No further merge damage found.** Recorded so nobody re-runs this
expecting gold — the scan is dominated by false positives and the two real cases
were both found by the compiler instead.

---

## 4. Still open (measured, not fixed)

* `FULL_LOGIC_AUDIT_2026-07-08`'s remaining findings are still unverified one by
  one. Two were checked here: **#7 confirmed and fixed**, **#12 refuted**. That
  is a 50 % accuracy rate on a two-item sample of a doc that is still being cited
  as a work list. Re-measure each before acting.
* The 5 "dead whole files" that audit lists have not been re-grepped.
* `regression_world_save`'s **doors-on-walls** and **macro-corruption** checks
  still skip on a world with no structure items and no operator macros. §1.3 now
  makes `structure_items` reachable from a test, which is the first half of what
  the doors check needs.
