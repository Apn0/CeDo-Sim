# Design — the vacuum-pot cleaning mini-game (P3 stage B)

Source: the operator's transcript of 2026-09-23, `docs/plant/operator_rulings_2026-09-23.md`
§14. His framing: "this is operator simulation stuff … I have never held any
E's inside the factory." This document turns that transcript into game
systems; it invents nothing he did not say and marks every parameter that is
his, derived, or a placeholder. Stage A (the visible pot state) shipped the
same day; this stage is NOT built yet.

## 1. What the operator described (in order)

1. The vacuum alarm sounds: a pot is full and the melt has pushed its lid open
   (`ExtruderModel` "vacuum_lid_pushed_open" → VACUUM_ALARM).
2. **Pull the lid off.** It sticks — "the plastic that is already starting to
   stick to it more and more and getting harder and harder, the longer the
   vacuum has been not in vacuum".
3. **Clear the inner planes with a plamuurmes** (putty knife): the TOP plane
   top-left → top-right → bottom-right → bottom-left; the BOTTOM flat plane
   the same; the LEFT side (left-front, left-rear, left-bottom, left-front
   plane); the RIGHT side likewise. The tool is narrower than a plane, so it
   is pushed in several times; a push "might only go halfway" — pull out,
   move aside while not touching the melt, push again; the same spot may
   then go three quarters or all the way, "depending on how stiff the melt
   is".
4. **Success:** each of the four planes ≥ 90 % cleared ("for the testing
   phase"). Then the block "drops down and forwards, towards the player by
   like a centimetre" — the visual that it is free.
5. **Take the block out by hand** (no tool) and place or throw it anywhere:
   the ground, a container, the lump pile under a filling cart, into the
   lump cart if there is room.
6. Which pot: laser-filter trouble clogs the PRIMARY (first) pot, head-filter
   trouble the SECONDARY; sometimes both.
7. **Lid back on.** If the seal is good, start the extruder; the vacuum pump
   reaches vacuum; the alarm clears.
8. **The two-minute rule.** Lid off, pot clean, lid back within ~2 minutes of
   the alarm → the extruder sees vacuum restored, silences the alarm and keeps
   running. Past two minutes → instant shutdown of the screw motor, the vacuum
   pump, the laser-filter knife motor, water pumps, the pelletiser head; the
   vacuum alarm stops (no vacuum needed when off) and a DIFFERENT HMI alarm
   reports the shutdown "due to laser filter error".

## 2. Systems

| system | today | stage B |
|---|---|---|
| Pot state | `ExtruderModel.primary/secondary_pot_fill_kg` (18 kg), VACUUM_ALARM after lid push, FAULT after 120 s (`vacuum_alarm_remaining_s`) | unchanged — the 120 s IS his two minutes |
| Pot visual | stage A: witness port, `Lid` disc lifts/tilts, `Gunk` | the lid becomes a carryable prop once pulled; the melt BLOCK appears inside the open pot |
| Lid pull | — | interaction on the open `Lid`: a hold whose required time grows with `seconds since VACUUM_ALARM` (his "harder and harder"); on completion the lid detaches into the player's hands |
| Plamuurmes | — | a new hand tool (`tool_plamuurmes`) in the catalog, like the shovel / wrench: held, pushed with the interact key while aimed at a plane |
| Planes | — | per pot 4 planes (top, bottom, left, right), each a 2×2 grid of quarter cells (his "quadrants" per plane); a cell's clearance 0..1 |
| A push | — | aim at a cell, push: depth gained = f(melt stiffness, cell clearance so far); stiffness = f(seconds since alarm, pot temperature); a push that stops "halfway" leaves the cell at ≤ 0.5 and requires pull-out + re-aim before the next push (the tool must be clear of the melt to move sideways: enforce by "pull out" being its own key/state) |
| Release | — | all four planes ≥ 0.90 (constant `PLANE_CLEAR_FRAC`, his testing value) → the block prop shifts 1 cm down and toward the player; it becomes grabbable |
| Block | — | a carryable RigidBody prop (mass = pot fill kg) — placeable anywhere, throwable; accepted by `WasteContainer.add`, `FloorPile.add` (the lump pile), `LumpCart.receive_lump` if room |
| Re-lid | — | interaction with the lid prop aimed at the empty pot; seal check = block gone AND lid seated; sets `vacuum_restored` input for the model |
| Two-minute race | model has it | the model's VACUUM_ALARM → RUNNING transition on `vacuum_restored` within the window; FAULT otherwise (existing) — verify the "different HMI alarm" text on the extruder HMI |

## 3. Parameters

| parameter | value | provenance |
|---|---|---|
| plane clear threshold | 0.90 | operator, "for the testing phase" |
| alarm window | 120 s | model (matches his "about two minutes") |
| block shift on release | 1 cm down and forward | operator |
| planes per pot | 4 (top, bottom, left, right) | operator |
| cells per plane | 4 | operator's "quadrants" wording — placeholder until played |
| push depth per attempt | 0.5 / 0.75 / 1.0 steps | operator's example — placeholder curve |
| lid pull time | 2 s + 1 s per minute since alarm | placeholder; his "harder and harder" gives the sign, not the number |
| which pot clogs | laser filter → primary, head filter → secondary | operator |

## 4. Test strategy (before any of it counts as done)

- A headless suite drives the model into VACUUM_ALARM with the primary pot
  full, pulls the lid through the interaction API (no input events), pushes
  every cell of every plane until ≥ 0.90, asserts the block's 1 cm shift and
  that it is grabbable, removes it, re-lids, and asserts the model returns to
  RUNNING within the window; a second run lets the window lapse and asserts
  FAULT with the laser-filter HMI alarm text.
- Conservation: the block's mass = the pot's fill kg; placing it in a lump
  cart or pile moves exactly that mass.
- Nothing about the feel (stiffness curve, cell count) can be proven headless:
  those are the operator's to play, then set.

## 5. Not in scope here

The laser filter's own knives/nozzles (already modelled), the head-filter
change, the pelletiser. The two "open top tanks" and the cyclone-to-blower
gap belong to the wet-side flake work (task 1c).
