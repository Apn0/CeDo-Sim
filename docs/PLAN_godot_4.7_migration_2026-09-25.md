# Plan: Godot 4.6.3 → 4.7.2 (2026-09-25)

**Status 2026-09-26: steps 0-7 DONE, measured in
`docs/audit/godot_4.7_migration_trial_2026-09-26.md`. Steps 8-9 (full harness,
play-test, merge) are the operator's.** Step 0 was already done: the operator
had put 4.6.3, 4.7.1 and 4.7.2 in `V:\Godot`, so nothing was downloaded. The
"should" claims below were written before the trial; the audit doc says which
of them held.

## 1. Versions

| | version | date | source |
|---|---|---|---|
| installed, used by `run.sh:21` | 4.6.3-stable | — | `C:/Users/arnod/AppData/Local/Godot/` (VERIFIED, `ls`) |
| **newest stable** | **4.7.2-stable** | 2026-08-18 | godotengine.org/download/archive + GitHub release API (VERIFIED) |
| earlier 4.7 | 4.7-stable / 4.7.1 | 2026-06-18 / 2026-07-14 | same |
| newest pre-release | 4.8-dev6 | 2026-09-15 | same |

Target **4.7.2**. 4.8 is a dev snapshot: not stable, not for a project whose
proof is a 120-step harness.

Download (not done): `Godot_v4.7.2-stable_win64.exe.zip`, 86,013,866 bytes,
from `github.com/godotengine/godot/releases/tag/4.7.2-stable`, checked against
that release's `SHA512-SUMS.txt`.

## 2. What 4.7 adds that CeDo could use

Source: godotengine.org/releases/4.7. These are CLAIMED by Godot's release
notes, not measured here.

| 4.7 feature | what it could do in CeDo |
|---|---|
| **AreaLight3D**, rectangular area lights with soft shadows | TL tube and LED panel strips as real rectangular lights instead of point/omni approximations. Costs GPU; measure fps first |
| **Per-pass environment uniform buffer** | Free rendering performance, no code change |
| **Clearcoat fixed** (energy, sky reflections, reflection probes) | Painted machine bodies and the CeDo-blue motors get correct gloss |
| **3D particles scale + rotate** | Dust, film flakes and water spray |
| **HDR output** (Windows) | Only on an HDR monitor |
| **`Tween.tween_await(signal)`** | Sequences such as the extruder start chain, gate travel and lids, without hand-written state machines |
| **Control `offset_transform_*`** | HMI animations (alarm blink, slide-in panels) that do not fight containers |
| **PopupMenu search bar** | The build menu holds ~200 catalog ids |
| **RichTextLabel font-sized images** (em units) | Icons inside HMI text that scale with the font |
| **Controller ignored when window unfocused** | Stops input leaking while tabbed out |
| Editor: **3D follow mode** (F twice) | Follow a driving forklift or NPC in the editor |
| Editor: **vertex snapping** (B), **trackball rotate**, **Path3D snap to colliders**, **3D ruler with per-axis lengths** | Placing and measuring machines against the shell ("measure, don't assert") |
| Editor: **Remote Inspector folding, enum names in the remote tree** | Debugging a running world: states show as names, not ints |
| Editor: loaded GDExtensions listed in Project Settings | Shows at a glance whether Rapier and WRY loaded |
| 4.7.2 fix: mouse with a high polling rate on Windows | Performance fix for a Windows FPS |

Not relevant to CeDo: Android/XR/visionOS work, VirtualJoystick, gyro input,
2D scene painter, one-way 2D collision direction, and the **Jolt** physics
changes (CeDo runs **Rapier3D**, `project.godot:419`).

For information, 4.8 dev snapshots so far add Trail3D, texture streaming by mip
level (VRAM), screen-space contact shadows for directional lights, multi-bounce
AO and directional lightmap specular. Those would be a later migration.

## 3. What 4.7 breaks, checked against this tree

Source: `docs.godotengine.org/.../upgrading_to_godot_4.7.html`. The hits are
greps over `src/ tools/ addons/`, measured 2026-09-25 at `c1dabb7`.

| 4.7 change | hits here | verdict |
|---|---|---|
| **A method that overrides a typed-return method inherits the return type and needs an explicit `return`** | not greppable | **Unknown count.** The 4.7 parse sweep lists every one. Fix: add the return |
| **Keyboard/mouse events get device 16/32 instead of 0** | 65 key and 5 mouse events stored `"device":0` in `project.godot`; ~20 runtime `InputMap.action_add_event` sites | Should be safe: PR #116526 (4.7) normalises legacy device 0 when events are added to the InputMap. Not measured. 3 **probes** (not suites) inject events with `Input.parse_input_event`. Test them |
| CanvasItem lines lose their AA feather, so they draw thinner | `draw_line/draw_arc(..., true)` ×3 in `MapOverlay.gd` (+1 in a shot tool) | Cosmetic: the map's ring and building outline get thinner. Check the look; widen by ~1 px if needed |
| Packed array element set no longer calls the property setter | 0 typed Packed props with a setter | none found |
| `AnimationNodeBlendSpace*` `sync` bool → `SyncMode` enum | `Humanoid.gd:952` builds a BlendSpace2D and never sets `sync` | low; `test_humanoid_rig_conformance` covers it |
| `sky_reflections/roughness_layers` default 7 → 8 | not set in `project.godot` | Takes the new default: slightly different reflections |
| Font import `hinting` default 1 → 3 | only for NEW imports; existing `.import` files keep their value | none |
| Jolt: WorldBoundaryShape3D sign, SoftBody3D mass/stiffness, Area3D↔SoftBody | 0 uses; engine is Rapier3D | n/a |
| AudioStreamPlayer `area_mask` 1 → 0 | 0 `audio_bus_override` / `reverb_bus` | n/a |
| RichTextLabel `add_image` units, `UPDATE_WIDTH_IN_PERCENT` | 0 | n/a |
| `AudioEffectSpectrumAnalyzer.tap_back_pos` removed | 0 | n/a |
| `LookAtModifier3D.relative` default | 0 | n/a |
| `Object.is_class` takes StringName, `Animation.length` is double | GDScript-compatible | n/a |

## 4. Project-specific risks that Godot's guide cannot know

1. **Assets that exist only in the import cache** (`docs/audit/assets_loss_and_restore_2026-09-21.md`).
   101 of them have no source, `CeDo_factory_solid.obj` (the shell) among them.
   `Merlo.fbx` has its source, but a forced re-import loses all 21 texture links.
   If 4.7 bumps an importer version, the editor re-imports every file whose
   source it can see, and Merlo would re-import too. Cache-only files are
   probably skipped: the editor only lists files whose source exists. Not
   measured. **Gate: fingerprint `.godot/imported/` and `assets/`, run 4.7.2
   `--import`, fingerprint again, and account for every change.**
2. **`app_userdata` is keyed by project name, not folder.** A 4.7 game run in a
   separate folder would still write the operator's real
   `%APPDATA%/Godot/app_userdata/CeDo Simulator/` (`world_layout.json`, saves,
   `settings.cfg`). **Every trial run redirects `APPDATA`.**
3. **There is no way back.** Once a 4.7 editor saves the project,
   `config/features` reads `"4.7"` and `.godot/` holds 4.7 data. 4.6.3 is not
   guaranteed to open it again. So the trial runs on a branch in its own folder,
   with its own copy of `.godot/`.
4. **Both GDExtensions are unverified on 4.7.**
   - Rapier3D 0.8.34 (`compatibility_minimum = 4.6`) is the physics engine for
     the whole game.
   - godot_wry (`compatibility_minimum = 4.1`) runs the web HMI panels.

   GDExtension is built to load in newer 4.x versions, and 4.7 changes only
   the **2D** physics-server extension API. Should load; not measured.
   **Gate:** the boot log shows Rapier3D registered, with no "unknown physics
   server" fallback and no GDExtension errors.

   Do **not** update Rapier or WRY in the same change. One variable at a time.
5. **The one-harness-runner rule** (CLAUDE.md, 2026-09-25). This session may
   run single suites and the parse sweep only. A full harness on 4.7.2 is the
   runner's job, or the operator's by hand.

## 5. The plan

A separate folder is **required**, not merely safer (risks 1-3). This session's
worktree already is one: `V:\_Claude\CeDo_Simulator\cedo-simulator-godot-migration-7de0ab`,
branch `claude/cedo-simulator-godot-migration-7de0ab`, at `c1dabb7` = `origin/main`.
The operator's checkout at `C:\Users\arnod\Documents\CeDo_Simulator` is never
opened with 4.7 until the merge.

| # | step | gate to continue |
|---|---|---|
| 0 | Download the 4.7.2 zip (86 MB) and verify it against SHA512-SUMS. Unzip beside 4.6.3 as `Godot_v4.7.2-stable_win64(_console).exe`. Keep 4.6.3 | sha512 matches; `--version` prints `4.7.2.stable.official` |
| 1 | Copy (**never link**) `assets/` (1.4 GB) and `.godot/` (1.2 GB) from the operator checkout into the worktree. Copy his `app_userdata` to `D:\cedo_archive\userdata\godot47_trial\` | copies md5-identical to the source |
| 2 | **Baseline on 4.6.3** in the worktree, scratch `APPDATA`: parse sweep plus the suites in §6 | the baseline verdicts are recorded |
| 3 | Fingerprint `.godot/imported/` + `assets/`, then run `4.7.2 --headless --import`, then fingerprint again | every changed file is explained; no cache-only file changed; Merlo still has 21 texture links. **Otherwise stop** and rebuild Merlo's PNGs first |
| 4 | Boot on 4.7.2 and read the log: Rapier registered, WRY loaded, `^SCRIPT ERROR` count | 0 extension errors |
| 5 | Parse sweep on 4.7.2. Fix every typed-return override (add the `return`) | `N ok, 0 fail` |
| 6 | Suites of §6 on 4.7.2, one at a time, scratch `APPDATA`, against the step-2 baseline | same verdicts as the baseline, or each difference explained |
| 7 | Commit on the branch: `config/features` "4.7", `run.sh:21` default → 4.7.2, the CLAUDE.md engine section, the code fixes, and the audit doc with every number | clean `git status`, `.uid` files included |
| 8 | **Operator:** a full harness on the branch with `GODOT=` set to 4.7.2, by the runner or by hand, then a play-test (driving, keyboard, map, HMI web panels, sounds) | the red list equals `main`'s (`test_npc05_realworld` only) |
| 9 | Merge. Before the operator opens his checkout in 4.7.2, back up his `.godot/` to `D:\cedo_archive\backups\` | he plays on 4.7.2 |

**Rollback:** keep the 4.6.3 exe, revert the merge commit, and restore the
`.godot/` backup. His `app_userdata` is never touched by steps 0-8.

**Disk:** C: 19 GB free, D: 54 GB, V: 30 GB (measured 2026-09-25). The trial
needs about 3 GB on V: plus the userdata copy on D:. Nothing large lands on C:,
because a full C: already caused short-write reds (memory: `c-drive-full-short-writes`).

## 6. Suites for steps 2 and 6 (one at a time, never `run.sh`)

| area 4.7 touches | suite |
|---|---|
| GDScript compile | `tools/regression/parse_sweep.gd` |
| world boot, shell mesh (cache-only OBJ) | `regression_world_save`, `test_extruder_brain_wired`, `test_legacy_props_unconfigured_boot` |
| Rapier physics | `test_lump_chunk_ccd`, `test_bale_yard_mass_conservation`, `test_spawn_clearance` |
| vehicles + navmesh | `test_jam_baseline` |
| WRY web HMI | `test_hmi_web`, `test_hmi_web_gather_vals` |
| animation (BlendSpace2D) | `test_humanoid_rig_conformance` |
| thinner AA lines | `test_map_overlay_zoom`, `test_map_labels` (plus a look at the map) |
| input device ids | `test_keybind_sheet`, plus the 3 `parse_input_event` probes |
| audio | `test_machine_sounds` |
| file I/O | `test_atomic_file` |
