# Operator issue dump — 2026-07-16 (in-game shift, Ploeg A)

Captured verbatim so nothing is dropped. Grouped by type.

STATUS SUMMARY (regression 14/0 green after all fixes):
- FIXED+VERIFIED: 1, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15
- EXPLAINED (no code change): 16 (scan)
- QUEUED (root-caused, exact fix known, not yet applied): 2, 6, 7, 17
- NEEDS OPERATOR TO POINT: 18, 19  ·  META: 20

## A. PHYSICS VIOLATIONS (loudest — "IT SHOULD BE IMPOSSIBLE TO MOVE THROUGH A MESH")
1. **Cannot walk over the flotation-tank catwalk — no collision.** Player passes through the walkway. Catwalks/walkways must have solid collision.
2. **Floating stairs** — stair treads hover with no support, AND they are solid slabs, not the **metal grid/grating** meshes the operator told me to use.
3. **Steam from nothing** — PCU / dryer emits steam plume while `fed: 0 kg` (no material, no water). "Inventing water into existence."
4. **Orange stuff dripping from the extruder while it's OFF / no material.** Material from nothing.
5. **"this is not a mesh underneath the compactor"** — support/floor under the compactor is missing or not a real mesh.

## B. CARTS / CONTAINERS
6. **Lump/extruder carts STILL WRONG.**
7. **No fork pockets in the container feet** — notes describe **POCKETS BELOW the cart, not grooves**. Current holes are invisible/fake. Forklift forks have nowhere to enter.

## C. GEOMETRY / PLACEMENT
8. **Shredder exit belt runs straight THROUGH the friction washer.** Belt routing clips the machine.

## D. CHARACTER MODEL (NPC + player)
9. **High-vis is YELLOW — must be ORANGE only.**
10. **Texture on pants but not on shirt** (inconsistent).
11. **Hands are the wrong way round.**
12. **Feet/toes point the wrong direction** (toes should point forward/opposite).

## E. GAMEPLAY / TUNING
13. **Double the jump height.**
14. **Allow vaulting.**
15. **Dirt/grime accumulates WAY too fast** (see image).
16. **FeederWorker "SCAN" state** — "what do you mean scanned??" (why does the NPC scan bales).
17. **"stationary bale --> impossible"** — a bale sits dead-stationary (feeder vpos stuck at (4,0,-14), speed 0).

## F. NEEDS CLARIFICATION (image-only, I must confirm what they point at)
18. **"what is this?"** — unidentified object.
19. **"what are those light blue things?"** — light-blue elements on a machine.

## G. META
20. **"making simple label takes 100 turns?"** — label quality/speed frustration.

## ROUND 2 (second in-game pass, same day) — STATUS
FIXED+VERIFIED: 21 (real Waterbox water, buoyancy proven), 24 (orange→green panels), 25 (leaf blower to hand), 26 (bale unfrozen on belt), 27 (soft/proximity-fade smoke), 28 (Inventory crash).
QUEUED (root-caused, bigger): 22 (seated pose + SeatMarker per vehicle), 23 (openable cab doors + NPC door-open handshake — forklift/clamp doors are fixed geometry; Merlo/car doors animate but NPCs never trigger them).

## ROUND 7 (steering fix + adversarial bug-hunt, 2026-07-17)
STEERING (operator hint): bale-clamp left/right switched (steer_sign=-1) + steer & auto-centre rate DOUBLED (steer_rate_rad_per_sec=2×). Old `c.steering=-c.steering` flip was a NO-OP (yaw is driven by _current_steer_rad); removed. New per-subclass steer_sign + steer_rate_rad_per_sec on BaseVehicle.

BUG-HUNT confirmed defects (4-lens adversarial):
FIXED this turn:
- [MAJOR] Reverse beeper + reverse beam DEAD on every vehicle — `get_speed_mps()` returns absf() but was compared to a negative threshold, so `reversing` was always false. Now uses signed `_current_speed_mps`.
- [MAJOR] Stairs got a generic full-size AABB collider → flight IMPASSABLE + per-tread colliders dead. Added `stairs` to skip_collision.
- [MAJOR] Extruder die-face strand drip re-appeared: StaticMerge re-bakes the group-hidden strands visible, undoing my orange-drip gate. Added `no_merge` meta to the switcher.
- [MAJOR] Shovel STILL deleted mass when the bin was FULL (bin.add caps, remainder lost). Now refuses the scoop if the bin is_full.

STILL OPEN → ALL CLEARED 2026-07-17 (round 7b). Regression 14/0; 2 new headless proofs PASS:
- [MAJOR] ✅ machine_leg/machine_foot no longer merged away — StaticMerge._is_dynamic now skips
  those groups so extend_machine_legs finds & floors them. PROOF (test_silo_legs_clearance.gd):
  4 machine_leg meshes survive the merge (was 0 → silo floated).
- [MAJOR] ✅ extruder_silo walk-under clearance opened — new _extruder_silo_compound_collision
  (4 slim legs + raised body box) replaces the solid 0..6.5 m AABB. PROOF: 5 collision boxes,
  0 fill the low bay (was 1 solid box). Wired via elif id=="extruder_silo" in build_node.
- [MINOR] ✅ Merlo P40 cab wheel now reads _current_steer_rad*6 (was dead VehicleBody3D.steering).
- [MINOR] ✅ Steered wheel meshes follow the ramp every frame — _rotate_steered_wheel_meshes moved
  out of _drive() into _physics_process (after _update_steer_ramp), so parked/NPC vehicles steer
  their wheels visually too. Removed the two now-redundant in-_drive calls.
- [MINOR/physics] ✅ BezinkTank inflow gated on the line running (any belt moving, 0.5 s cache) —
  no more filling from nothing on a cold plant. Drain/level-control logic untouched.
- [LOW] ✅ Inventory.set_active() + _apply_visibility() hardened to untyped read + self-heal
  (same freed-instance class as the slot_label crash).
- [LOW] ✅ BaleBurst.open() splits mass across LIVE chunks only (divides by non-empty bin count).
  PROOF (test_bale_burst_conserve.gd): clustered sheets → 2 live pieces sum to 600 kg (bale was
  600; old code lost 400).

## ROUND 6 (operator specs: cab levers + cart sketch)
37. **Forklift/bale-clamp cab: 4 hydraulic levers** (operator: 1=lift, 2=tilt, 3=fork-spread/clamp, 4=rotator). Was only 2 (Lift, Tilt). Added LeverShift+LeverRotate to Forklift.tscn and LeverClamp+LeverRotate to BaleClamp.tscn (chrome stalk + knob, spaced right of the wheel). Regression 14/0.
38. **Lump cart rear view (operator sketch)** — rebuilt the cart's fork provision as TWO PROMINENT visible pocket housings near the wheels with dark rectangular mouths (front+back), matching the drawing. Visual only; collision stays the stable narrow layout (wide collision drifts the live cart — needs freeze-on-spawn redesign, flagged). Rendered + confirmed.
39. **Hot-surface warning sticker on the cart back** — operator confirms it's ALREADY done (my not listing it = it wasn't outstanding). No action.

## ROUND 5 (build-the-queue, doc+web sourced)
7b. **Fork pockets VISIBLE** — added dark-lined bores (ceiling+floor+side walls) to the cart fork channels so they read as REAL openings, not invisible holes. NOTE: realistic WIDE spacing (±0.28 m, real 200×100 mm) destabilised the live physics cart (round-trip drift 0.3 m) — reverted to the stable ±0.10 geometry + visibility. TRUE wide pockets need a cart redesign (freeze-on-spawn like bales, or a taller underframe) — deferred.
17b. **Feeder parks forever on empty lot** — re-enabled `_restock_lot()` (was dead code post-#32) with a MAX_RESTOCKS=4 cap so the feeder keeps working without flooding the plant.
32b. **Laser filter model** — examined vs operator photos (`_laserfilter.png`, `laserfilter_lump_cart_discharge.jpg`): the model is already photo-accurate (rotary disc + swoosh, twin screen discs, melt pipes, twin discharge to lump carts; built 2026-07-14). I did NOT change it this session, so "unchanged" is fair — but it already matches. NEED operator to say what specifically is wrong.
STILL QUEUED: 22 (sit-pose), 23 (doors), realistic wide fork pockets, laser-model specifics.

## ROUND 4 (build-the-queue pass)
34. **Scan gate unrealistic** — a conveyor bounced a 700 kg bale over a paper scan. FIXED: belt now ACCEPTS unscanned bales (physically), flags meta `untraced` + `untraced_count` for the scanlog (traceability, not a physical gate).
35. **PHYSICS VIOLATION: shovel deletes mass into nothing** — scoop removed 25 kg from a pile and, with no bin nearby, silently deleted it. FIXED + PROVEN (test_shovel_conservation.gd): no bin → scoop refused (pile untouched); with bin → mass moves pile→bin exactly; scoop size 25→6 kg (realistic shovelful).
2 (floating stairs → grating). FIXED: `_stair` treads now see-through grating + hidden collider + sloped stringers to the floor; standalone `_m_stairs` grating treads got per-tread collision (were walk-through).
36. **Mohammed assigned to leaf blower does NOTHING** (stands still) — FIXED: the "post: tool_leafblower" option routed to a dead stand-at-post state, never the blow-leaves task. Root: hand tools defaulted to a flow-machine role and leaked into the post dropdown. Fix = tools → role "none" (out of the station list) + posting to a leaf blower now forwards to NpcAutonomyBoard.force_task(blow_leaves). forced-task test PASS.

## ROUND 3 (third in-game pass)
29. **Starter tools not in hotbar on spawn** — FIXED: `Inventory.give_starter_tools()` called from PlayerSpawner (scissors/scanner/shovel, idempotent). Regression boots clean.
30. **Feeders scan+cut bales WITHOUT tools, 3 at once** — FIXED: root cause = section-feeder spawn path (CrewManager) never gave them tools (only the legacy path did) + scan/cut was a bare timer meta-flip. Now each section feeder gets its own scanner+cutter, and SCAN/CUT pull the tool to a front hand anchor. (3-at-once = one feeder per feed section, which is fine now they have tools.)
31. **Player CAN'T cut the iron wires even holding the wire cutter** — FIXED: yard bales are SIMPLE LOD (no Wires node until a vehicle grab); WireCutter now promotes via detail_bale() on foot before cutting.
32. **Laser filter model unchanged** (still wrong from earlier) — QUEUED (needs docs).
33. **PHYSICS VIOLATION: laser filter pressure rising while everything reads ZERO** — FIXED + PROVEN: LaserFilter no-flow gate (ΔP/load→0 when feed=0) + ExtruderMachine stops forwarding the 50 kg/h IDLE spin + clears amplifier signals when not producing. test_laser_pressure.gd: unfed ΔP=0, fed ΔP=787 psi.

21. **Flotation water is FAUX** — "contained by nothing in center, outside the reservoir yet floating on the sides." USE THE **Waterbox plugin** (CONFIRMED installed+enabled at addons/waterbox/). — IN PROGRESS
22. **Driver sit pose wrong** — not a normal seated position in the bale-clamp/forklift/merlo cab.
23. **NPC teleported through a non-openable cab door** — door doesn't open; entry is an instant seat-snap.
24. **Orange side panel(s) on the forklift** — makes no sense, not realistic. Remove/recolour.
25. **Held leaf blower FLOATS above the NPC's head** — not in his hands (held-tool attach wrong for NPCs).
26. **STATIONARY BALE ON MOVING CONVEYOR** — bale dead-still on a running belt (likely still frozen when handed to the belt).
27. **Smoke ugly/FAKE, wants volumetric** — flat billboard particles.
28. **CRASH: `Inventory.gd:158 slot_label: invalid previously freed instance`** on extruder-gauntlet start (HUD.gd:1362). — **FIXED** (untyped read + self-heal stale slot; parse-clean).

