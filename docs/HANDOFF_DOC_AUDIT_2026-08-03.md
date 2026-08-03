# Audit of the self-documenting commit (`bcf27d1`) — 2026-08-03

`bcf27d1` added `CLAUDE.md` + `docs/AUDIO_sound_engine_state_2026-08-03.md` to fix
the structural problem that sessions opened inside this repo load no memory.

That diagnosis was right. The **content** was not audited before it was committed,
so this pass verified all 83 checkable claims in it against the code. **34 were
wrong or misleading.** The corrections are already applied to `CLAUDE.md`; this
file is the evidence trail.

Method: 6 parallel verifiers, each required to back every verdict with a command
and its real output. Every finding below was then re-measured by hand before being
written here — one verifier had inverted the Godot conclusion by treating
`CLAUDE.md` as ground truth, which is exactly the failure this repo keeps hitting.

## The five hard errors

| # | Claim | Measured reality |
|---|---|---|
| 1 | "Godot 4.2", engine at `.../Godot/godot.exe` | `project.godot` → `config/features=("4.6")`; `run.sh:17` → `Godot_v4.6.3-stable_win64_console.exe`. That `godot.exe` is md5-identical to `Godot_v4.2-stable_win64.exe` and `--version` → `4.2.stable`. **A fresh session's first command would fail.** |
| 2 | harness proves "doors on walls" | **SKIPPED** — `note  : no structure_items (doors) in world_layout`, data-gated at `regression_world_save.gd:204` |
| 3 | harness proves a "macro-corruption guard" | **SKIPPED** — `note  : no operator macros present`, `regression_world_save.gd:575` |
| 4 | "F8 stops the editor, it does not stop the game" | **Inverted.** F8 is bound to Inspect Mode (`SettingsManager.gd:660`); embedded in the editor it is the **Stop** shortcut — `NpcTaskBench.gd:68` "it killed the session" |
| 5 | "one lump cart serves four extruders" | Code places **six**, two per line (`BuildMode.gd:159/161, 379/381, 471/473`), 3C gets none. Contradicts an operator-locked fact → **flagged as an open question, not resolved** |

### The skip problem is the important one

`Result: 16 ok, 0 fail, 2 skip`. `run.sh` gates on the fail count, so skips pass
silently. The regression world boots with `Loaded 0 placed objects` and
`0 machines, 0 links` — so a green run does not exercise the placed-content paths
at all. This is Rule 3 ("bench greens prove the mock") biting the very harness
Rule 3 points you at.

## Doc index — 7 of 8 rows misdescribed

Worst three, because each actively misdirects:

- `DESIGN_hmi_tag_bridge` was labelled "HMI ↔ tag bridge design". Its actual line 3
  reads **"do NOT build the WebSocket/HTML bridge"** — the label reads as a design
  to build, i.e. the opposite of its verdict.
- `DESIGN_npc05_container_chain` still states `GEBOUWD`, proof =
  `test_npc05_container_chain.gd`, with no correction note — that is the project's
  flagship vacuous green (31/31 PASS while moving 0.00 kg).
- `FULL_LOGIC_AUDIT` was presented as a live list. It has no per-finding status and
  mixes fixed with open items, so a fresh session would re-fix Bug 0 / HIGH #1 / #2.

`docs/DESIGN_SUGGESTIONS_2026-07-08.md` existed but was absent from the index.

## Gaps the file had no answer for

Measured, not speculative:

1. **No current-state section** — 82 lines of rules and history, zero statement of
   what is in flight or blocked.
2. **No code map** — 285 `.gd` files / 105,241 lines and the index named none.
3. **No way to satisfy Rule 3.** Rule 3 demands proof "in a real MainWorld boot";
   `run/main_scene` is `MainMenu.tscn`, there is no launch config and no CLI boot
   hook. The rule was unactionable as written.
4. **`user://world_layout.json`** — the world's ground truth, in git nowhere,
   `WorldLayout.gd` has no `res://` fallback. Undocumented, and a bigger exposure
   than the `assets/` trap that *was* documented.
5. **F10 marker tool undocumented** — the operator's primary feedback channel.
6. **`shot_placeable.tscn` unnamed** — so Rule 9 (render filenames) had no referent.

## The structural gap is machine-wide, not CeDo-specific

`CLAUDE.md` coverage across all 12 repos: **10 have no usable entry point.**
Ranked by exposure (code volume × recent commits × blast radius):

| repo | commits | entry point |
|---|---|---|
| `C:\Users\arnod\telnyx-ghl-bridge` | 6, active | none — 40-byte README. **Live production** (Oranje-Eco dialer/CRM) |
| `V:\_Claude\Master` | 828, committed yesterday | none at all |
| `C:\Users\arnod\AqueductSim` | 1122 | README only, no CLAUDE.md |
| `C:\Users\arnod\Documents\uber-agent` | 141 | `.claude/` holds only `launch.json` |
| `V:\Odido` | 11 | none — its hard-won merge rules live only in cross-project memory |
| `AuschwitzSim`, `wtc_evacuation_sim` | 53 / 18 | nothing of any kind |
| `cedo-audio-placer` | 10 | none — a CeDo satellite, cut off from these rules |
| `farmers`, `nurburgring-app` | — | 11-byte stub CLAUDE.md (an Expo import line) |

Only 2 of 12 repos have a scoped session project dir, and no repo has a memory
store. So the CeDo fix is correct but local: the same blindness applies everywhere
else, and `telnyx-ghl-bridge` is the one where a blind session can do real damage.
