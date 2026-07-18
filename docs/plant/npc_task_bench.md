# NPC Task Bench (#225)

Flat 3-line test world for the crew stack — **main menu → "NPC task bench"**.
Scene: `src/scenes/world/NpcTaskBench.tscn` / `.gd`.
Proof: `godot --headless --path . res://src/tests/test_npc_task_bench.tscn`

## What's in it (operator spec 2026-07-12)

- **3 lines** along +Z at X = -12 / 0 / +12, each:
  `opzetband (feeder belt) → shredder_1 → friction_washer → flotation_tank → extruder → laser_filter (live sim)`
- **TWO lump carts per extruder** — one under EACH vertical discharge nozzle
  (aisle +X in front of the disc face, wall -X behind it), on the bordes
  (platform + ramp), a yellow spot under each.
- **Housekeeping bait** the NpcAutonomyBoard scans for: 2 waste containers,
  leaf blower + jerrycan, 80 kg film pile ON THE FLOOR under line B's feeder
  belt, forklift (tagged group `forklift` for the lump-haul task).
- **8 NPCs**: 3 extruder ops (Pascal/Kevin/Emrah), 3 feeders
  (Abdellilah/Mohammed/Yassine), 1 all-rounder (Vincent), 1 shift leader
  (Romain — receives NO automatic tasks; the role-gate control).
- **Real systems** (not the visual-only gauntlet): CrewManager (production-first
  gate, role/section posting), NpcAutonomyBoard autoload (5 s scan →
  auto-assignment), ShiftClock, LineFlow (best-effort discovery), CrewPanel on
  **C / Numpad-.**, BuildMode (Tab) with its own wiped-on-boot layout file.

## Lump discharge — TWIN vertical nozzles (operator 2026-07-14 + photos)

The afvoervijzel discharges through a VERTICAL nozzle on BOTH sides of the disc
— **aisle** (+X, in front of the disc face / HMI side) and **wall** (-X, behind
it) — each dropping straight down into its own lump cart on the bordes. (The
earlier single sideways-arm model was operator-corrected.)

- **Model** (`_m_laser_filter`): per side = corrugated riser beside the disc →
  short top arm → prominent vertical down-spout → funnel mouth at filter-local
  **(±1.30, ~1.13)**, above the cart rim.
- **Sim** (`LaserFilter.gd`): `eject_local_offset` (+X aisle) + `eject_wall_local`
  (-X); two bound carts `lump_cart` / `lump_cart_wall`, each by its own catch
  window (±0.55 / ±0.85 m, re-checked 2 s). Discharge routes to the ACTIVE
  nozzles (those with a parked cart), split evenly: a single-cart MainWorld line
  → all to the aisle (**no regression**); the bench's two carts → half each. kg
  stays on the `receive_lump` path. Two ropes (one per nozzle) grow + break into
  their cart; settled chunks are absorbed, misses stay as floor litter (cap 16).
- **Bordes** (`lump_platform` placeable): low steel-grating deck + ramp (~0.12 m)
  the filter + both carts stand on; the forklift rolls up the ramp to fork a
  cart out.
- **Fork-pickability** (#201, this pass): the cart underframe visual is now 3
  rails with TWO genuine OPEN fork channels matching the collision cavities 1:1
  — not a solid slab with painted-on recesses ("you can't put forks into a solid
  block"). MainWorld line macros are unchanged (the aisle cart still catches the
  +X nozzle; the -X nozzle stays idle until a wall cart is parked).

## What the headless test proves (all green 2026-07-12)

S1 exact group populations (3 filters, 6 carts) · S2 **BOTH** nozzles (aisle +X,
wall -X) of every filter: mouth above cart rim + exactly one cart under each +
neither mouth over an extruder footprint · S3 both carts bind → chunks exist
mid-flight (control) → land at a nozzle drop column → **zero on any extruder** →
absorbed by the bound carts · S4 shift_leader gets nothing (role gate) while all_rounder gets the
EmptyLumpCartTask for a full cooled cart · S5 **auto-assignment**: idle NPCs
claimed tasks from the board within 8 s with no manual call · S6 force_task
(CrewPanel backend) succeeds + fails cleanly without a jerrycan · S7
CrewManager holds all 8 workers, manual role assignment pins the post,
station_list() feeds the panel.

## Known limits (v1 — flagged, not hidden)

- Navmesh parses only the floor: NPCs can path through machine footprints.
- EmptyLumpCartTask **execution** (forklift haul legs) depends on #201/#202
  (pending) — assignment is proven, full haul-and-dump is not.
- LineFlow auto-discovery on the simplified bench chain is unverified — the
  CrewManager jam/production gate idles if `_nodes` came up empty.
- Animation/visual quality of NPCs doing the tasks needs an in-game eyeball.
