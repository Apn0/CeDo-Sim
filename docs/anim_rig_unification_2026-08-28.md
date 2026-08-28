# Humanoid rig unification — 2026-08-28

Operator bug report (4 screenshots): walk/run/jump = stiff statue, crouch did
nothing, prone folded the torso while the LEGS stayed standing. Later the same
session: "a second player spawned inside of me".

## Root causes (all fixed, all guarded by `src/tests/test_humanoid_rig_conformance.gd`)

1. **Limb meshes were never on the skeleton.** `Humanoid._collect_meshes_recursive`
   skipped the `HipPivot_L/R` / `ShoulderPivot_L/R` subtrees "for the sine-based
   NPC gait" — but that gait was an empty stub (`NPC._apply_gait` = `pass`, zero
   callers of `_cache_gait_pivots`). The AnimationTree rotated limb bones that
   owned no meshes. The skip is deleted; every mesh now reparents under its
   `BA_<bone>` BoneAttachment3D. The empty pivots stay for name-compat.
   **Trap:** the NPC.gd deprecation docstring claimed the migration had already
   happened. It hadn't. Trust `test_humanoid_rig_conformance`, not comments.

2. **FP layer split keyed on the pivots.** `MainWorld._set_body_render_layer_split`
   classified "leg" by a `HipPivot*` ancestor (first person shows only the legs).
   It now also accepts the six leg-bone attachment names (`BA_LUpperLeg` …
   `BA_RFoot`); the old name is still honoured.

3. **Prone was face-UP.** `-90°` Hips pitch tipped the chain onto its back, arms
   poking skyward (rig-internal forward is `+Z`, so face-down needs `+90°`).
   Caught by `src/tests/shot_humanoid_stances.gd` renders, guarded by the
   quaternion-sign check in the conformance test.

4. **No airborne pose existed.** New `jump_pose` + "jump" SM state;
   `PlayerController` travels there after 0.12 s continuously off-floor
   (`_AIR_ANIM_DELAY_S` debounces the post-vault re-seat and step-up flicker)
   and reverts instantly on landing.

5. **Double player body.** `Humanoid.rebuild_appearance` didn't know the player
   rig's name `"PlayerBody"` — every shift-bell wardrobe rebuild
   (`PlayerSpawner._player_apply_footwear`) found no old rig, freed nothing, and
   added a stray. Also reordered to detach-before-add so Godot never
   auto-renames the incoming like-named rig (`@HumanoidBody@N` broke NPC
   per-frame lookups after wardrobe swaps).

## Tools

- `src/tests/shot_humanoid_stances.tscn` — renders every SM state to
  `docs/plant/renders/shot_stance_<state>.png` (phase-aware for walk/run: waits
  for a swing peak so a zero-crossing frame can't fake a statue). Run WINDOWED.
- `src/tests/test_humanoid_rig_conformance.tscn` — 19 checks, headless;
  mutation-verified (restoring the pivot-skip goes red on 6 checks).
