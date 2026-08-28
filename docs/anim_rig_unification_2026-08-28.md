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

## Round 2 — what the adversarial review caught (12 confirmed, 2 refuted)

6. **The crouch was 4% deep.** Measured, not eyeballed: 1.70 m against a 1.78 m
   stand — the operator's "crouching does nothing" was literally true. The rig's
   bones are thigh 0.20 m / shin 0.38 m, so the fold is geometry-limited: thigh
   +100°, knee −150° puts the ankle 0.209 m under the hip instead of 0.58 m, and
   the hips must drop by exactly that difference to keep the feet planted. Feet
   counter-rotate +50° so they stay flat instead of tiptoeing. **Now 1.41 m.**
7. **Ground poses sank through the floor.** Prone (−0.97) and the old crouch
   (−0.97) both dropped below the standing sole plane (−0.90). Both now measure
   exactly −0.90. `src/tests/probe_stance_extents.tscn` prints the numbers.
8. **A blanket `scale = ONE` would have erased every NPC's build.**
   `Humanoid.build` puts the #126 height/width/depth sliders on the *rig root*
   scale, so six roster NPCs legitimately run non-1.0 scales (Vincent 1.12 tall,
   Pascal 0.90/1.15 …). The legacy-squash clear now matches only the Y-only
   shape (x == z == 1, y < 1) it is meant to undo.
9. **NPC jump pose was unreachable.** `_jump_locked` was cleared on the *impulse
   tick*: `is_on_floor()` still reports the previous tick's `move_and_slide`, so
   the landing branch fired before the body left the ground. New `_jump_airborne`
   gate gates it. This also silently disabled the mid-air re-impulse guard.
10. **Stale `_last_anim_state` after a rig swap.** The double-body fix made
    player rig replacement *real*, which exposed this: the fresh tree starts in
    "locomotion", the cached state still said "crouch", so the travel guard
    skipped and a crouching operator stood up. Reset on re-resolve, both
    PlayerController and NPC.
11. **The new test wasn't in the harness** (`tools/regression/run.sh`) — added,
    so all of the above are guarded on every run.

Mutation-verified: restoring the pivot-skip reds 6 checks; reverting the FP
splitter to HipPivot-only reds the leg-layer check; restoring the shallow crouch
reds both crouch checks.

**Residual, documented not fixed:** the crouch capsule (player 1.0 m, NPC 1.20 m)
is shorter than the posed body (1.41 m), so a crouching head pokes above its
capsule. Changing those heights changes what the operator can crouch under —
a gameplay-clearance decision, not an animation one.

## Tools

- `src/tests/shot_humanoid_stances.tscn` — renders every SM state to
  `docs/plant/renders/shot_stance_<state>.png` (phase-aware for walk/run: waits
  for a swing peak so a zero-crossing frame can't fake a statue). Run WINDOWED.
- `src/tests/test_humanoid_rig_conformance.tscn` — 25 checks, headless, wired
  into `tools/regression/run.sh`. Four layers: S1 rig structure, S2 animated
  poses (incl. measured crouch depth + floor-plane contact, signed-axis jump
  tuck), S3 rebuild one-body, S4 the REAL `MainWorld._set_body_render_layer_split`
  run over a real rig.
- `src/tests/probe_stance_extents.tscn` — prints measured low/high/height per
  stance. Run it before trusting any pose change; the renders hid a 4% crouch
  that this caught in one line.
