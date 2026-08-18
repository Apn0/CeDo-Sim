# Operator rulings — 2026-08-17

Statements made by the operator while driving the sim. These SUPERSEDE earlier notes where they
conflict. Recorded because project rule 1 requires an operator statement in `docs/plant/` before
code may contradict an earlier ruling — a code comment is not an acceptable substitute.

---

## 1. Bale-clamp steering is CORRECT as it now stands — `steer_sign = 1.0`

> "I have checked it in the simulator, and the steering is actually the correct way around. So if I
> press A, I will turn to left."

**This closes a contested item.** `docs/plant/operator_issues_2026-07-16.md:50` recorded the older
hint *"STEERING (operator hint): bale-clamp left/right switched (steer_sign=-1)"*, and an audit on
2026-08-16 flagged the working tree's flip to `1.0` as an unauthorised reversal. It was not a
regression — it was a correction.

**Why both statements are true.** The sign is a **double negative**. `BaleClamp.gd:147` sets
`operator_forward_sign = -1.0`, and `BaseVehicle.gd:1691` applies `_steering *= operator_forward_sign`
*before* `BaseVehicle.gd:1745` applies `* steer_sign`. Net steering is therefore `-1 × steer_sign`:

| `steer_sign` | net | verdict |
|---|---|---|
| `-1.0` (the 2026-07-16 value) | **+1** | wrong today |
| `1.0` (current) | **−1** | **correct — operator-verified 2026-08-17** |

The 2026-07-16 ruling was given when `operator_forward_sign` did not yet flip steering. When that
flip was added, the operator's single intended inversion silently became two. Nobody re-checked the
pair.

**Do not revert `steer_sign` to `-1.0`.** Any future agent reading only the 2026-07-16 line will
propose exactly that; this section exists to stop it.

**Follow-up (housekeeping):** `BaleClamp.gd:250` still carries a comment saying the switch is
*"handled by steer_sign=-1 in _ready"*. That is now stale and contradicts line 162.

---

## 2. OPEN BUG — bale-clamp throttle is inverted

> "When I press W, I go backwards. When I press the S key, I go forwards."

Steering is correct, throttle is not. Note this is **not** simply "flip `operator_forward_sign`":
that variable also gates steering (which the operator has just confirmed is correct and must not
regress), the reverse beeper, the head/reverse light aim, and the speed readout
(`BaseVehicle.gd:2113, 2132, 2174, 2309, 2400`).

On paper the chain already looks correct — the CabCamera at `BaleClamp.tscn:751-752` carries a 180°
yaw so it looks toward **+Z** where the mast is (`MastPivot` at z = +1.30), the counterweight is on
**−Z** (z = −1.55), and `operator_forward_sign = -1` should make W drive clamp-first. So the real
inversion is somewhere the comment at `BaseVehicle.gd:136-148` does not describe. Under
investigation; likely a second, uncounted sign flip downstream — the same shape of defect as the
steering double negative above.

---

## 3. Bale-clamp appearance — operator counts six defects

> "I can count at least four things that are very wrong. Actually, five. And when I go to the
> outside view, there is a number six. They all have to do with the middle clamp itself."

From the seat: a large reddish-brown slab blocks the forward view, the steering wheel is far too
small and low, three olive-green spheres float in the cab, and no mast rails or clamp plates are
visible ahead. From outside: the mast appears **bare** — no clamp attachment on it at all.

Consistent with the 2026-08-16 audit finding that `LiftCarriage` is an empty `Node3D` with no mesh
and nothing connects the plates to the mast posts.

**Rule 1 note:** there is still **no photo or spec of the operator's own bale clamp** anywhere in
`docs/plant/` or `assets/reference_photos/`. Clamp geometry may not be rebuilt from imagination.
A photo of the real machine is the blocker.

---

## 4. Delete the parallel test worlds

> "You can delete the line layout dragger completely… I'm actually thinking to also remove the
> extruder test gauntlet because it's fucked anyways, and it's a duplicate of what should be in the
> factory… same for the NPC testing… the world setup can also be deleted… I'm kinda done with all
> the hopping around between things where nothing works, and then it works in one, and then it
> doesn't work in the other."

**Ruled: remove them.** The bench worlds are to be deleted, not merely hidden from the menu.

This is consistent with what the repo already knew about them: `CLAUDE.md` records *"GauntletWorld
is a visual bench only. It omits LineFlow/crew/SCADA. Trustworthy for 'does it spawn/render', never
for behaviour"*, and project rule 3 exists because `npc-05` passed 31/31 on a bench while moving
0.00 kg. The benches have produced false confidence twice.

**Consequence accepted by the operator:** where a bench was the only proof for something, the proof
must be re-established in a real `MainWorld` boot instead. That is the point of the ruling — one
world, one truth.
