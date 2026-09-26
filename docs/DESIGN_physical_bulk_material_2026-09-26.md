# Physical bulk material: research and design (2026-09-26)

RESEARCH AND DESIGN ONLY. Nothing in `src/` or `tools/` changes. Branch
`docs/physical-bulk-material-2026-09-26`, on `main` `a727485`.

Evidence tags used throughout:

- **VERIFIED**: read in this repo's code or plant docs, or measured in this
  session (the measurement is named).
- **CLAIMED**: the operator's words or recollection. Not a document.
- **SOURCED**: read on the web page cited in §13.
- **INFERRED**: my reasoning. Treat as a hypothesis until measured.

---

## 1. In short

- **The good way, as the field does it** (SOURCED, §4). No real-time system
  simulates a pile grain by grain. The professional earth-moving simulators
  (AGX Terrain, Vortex) keep resting material as a cheap store (a heightfield
  or voxels) and turn it into moving bodies only where something moves it: a
  blade, a fall, a slope. At rest the bodies merge back. Mass is conserved at
  every conversion. Gold Rush is the store half of that (a heightfield a tool
  deforms), and it does not conserve mass, on purpose.
- **Recommended for CeDo** (§8 R, §9): the same hybrid, one zone per
  physical machine. Blobs of ~1 L where film moves (belt ends, falls, the
  screws' layer), a heightfield store where it rests, and screws as helicoid
  bodies that TURN. The zone sits between its LineFlow node's `in` and `out`;
  the rate law skips that node; the zone's kg count in `in_transit_mass()`, so
  `ledger_residual()` closes unchanged; nothing is ever deleted (§9.4).
- **Measured in a throwaway spike** (§6): in Jolt, a turning screw moves
  material out of a pile, a stopped one moves nothing, and reversed it moves
  material back. No rate was stated anywhere; the kg/h came out of contacts.
  **But the numbers are not calibrated**: three screws 637 kg/h, one screw
  alone 32 kg/h, an effective φζ of ~0.04 against the screw formula, and
  10 / 20 / 40 rpm gave 54 / 637 / 1555 kg/h, not proportional. The plant's
  screw sizes and gearbox (Q2) are what can validate it.
- **A screw as a moving surface does not work.** A static helix given a
  surface velocity (`constant_angular_velocity`, the "warped plane moving one
  way" taken literally) moved 0 kg in both engines, asleep or awake.
- **The game runs Rapier3D 0.8.34, not Jolt** (§3.4), a single-threaded
  build without SIMD. As shipped it throws blobs out of the bin from a turning
  screw: 143, 260 and 204 blobs lost in three runs, one flung 157 m up. Jolt
  lost 0-11 in the same kind of runs. Which engine the blobs run in is Q7
  (Rapier ≥ 0.35 is multithreaded and still deterministic, and unmeasured
  here).
- **No GPU for anything that carries kg.** Under `--headless`, where every
  regression suite runs, there is no RenderingDevice (measured). GDScript is
  too slow to be the solver (21 ms per step per 1,000 particles). The GPU
  draws the flakes; the CPU carries the kg.
- **Cost** (§7): a running doseersilo keeps ~2,000 blobs awake in its screw
  layer alone, and 3,000 active blobs cost 19-36 ms per step in Jolt on this
  PC (by how busy the other cores were): one to two frames for one silo. The
  whole plant cannot run physically at once at 1 L;
  physical-where-the-player-is (LOD) is Q5.
- **Machine by machine** (§10): about 70 of the 200 macro machines are
  granular (silos with screws, belts, chutes, screws). Those move to the
  physical model in four phases, the 3C doseersilo and its feed belt first.
  Air, water (the frictiewasser, R2), shredders, dryers and the melt train
  keep the rate law or get models of their own.
- **Ten operator questions** (§12), AskUserQuestion-ready. Batch 1 blocks
  phase 1: what feeds the doseersilo (the docs do not say), the screws'
  sizes and gearbox, the silo's depth (the HMI scale reads 0-300 cm, the model
  has 1.0 m walls), and whether film bridges in it.

---

## 2. What the operator asked for (CLAIMED)

Arno, 2026-09-26, answering AskUserQuestion in the rpm_pct session
(`docs/audit/hmi_rpm_rate_2026-09-26.md` §2, rulings R1-R3; the rulings file
for the day, `docs/plant/operator_rulings_2026-09-26.md`, comes with PR #334
and is not on `main` yet). Paraphrased, as that doc and the brief for this
task record them:

- **R1.** LineFlow's rate law (design kg/s × spin × rotor fraction × rpm_pct ×
  component multiplier) is a BASE and stays untouched, including the measured
  double count of the rpm setting. The END GAME is a physical material
  simulation, and the effort goes there.
- **R3.** No averages for parallel augers ("that does not hold up to me"). The
  film is carried as volume blobs of about a litre. A belt is a moving surface
  and carries what lies on it. At the belt's end nothing holds the blobs up, so
  they fall and keep some horizontal momentum. They stop on the silo's steel
  and pile up. An auger is a warped plane moving one way; it pushes blobs out
  of the pile. With one screw off and another on, the pile feeds the running
  one, and material falling in from above is pushed up. Throughput EMERGES.
  First target: the 3C doseersilo (3 augers) and the conveyor feeding it. He
  pointed at "Gold Rush" / "Gold Mining Simulator" (a shovel deforms the
  ground) for the feel, and asked for "the good way to do it".
- **R2** (already built, `306878b`). The 3A frictiewasser's two stirrers are in
  SERIES, and the wash-water inflow moves the film through it (the level rises
  and overflows into the chute), not the stirrers.

The general rules I derive from that, restated so he can reject them (a
plant answer describes one situation, and a rule built from it can be wrong;
§12's options restate the rule each one would make):

- **G1.** Material is conserved as discrete lumps with a mass each; no machine
  has a throughput number of its own anywhere in the physical part.
- **G2.** Every transport mechanism is a SURFACE that moves (belt: flat, screw:
  helicoid) or a SUPPORT that is missing (fall). Nothing else moves film in a
  granular machine.
- **G3.** What a machine delivers depends only on its geometry, its drive
  speeds, the material's friction and weight, and what is lying in front of it.
- **G4.** The rate law remains for every machine not yet physical, and the kg
  ledger balances across the boundary between the two.

G4 is my addition, from R1 ("the base stays") and the project's hard invariant
(`MaterialBatch.gd:3-20`: "VOLUME AND WEIGHT MUST ALWAYS MATCH INPUT/OUTPUT").

---

## 3. What the repo does today (VERIFIED)

### 3.1 LineFlow moves kg by a rate law, and keeps a ledger

- **The law.** `LineFlow._tick_process_machines` (`LineFlow.gd:3507`) moves
  `in.split_mass(min(eff_rate × dt, in))` into the node's `out` each tick,
  with `eff_rate = rate × spin × _mech_fraction × rpm_pct ×
  _component_pct_multiplier`. A stopped machine leaves `in` untouched: that is
  the "leegdraaien" contract (`:3557-3577`).
- **Connectors.** `_tick_route_outputs` (`:3651`) carries `out` down each edge
  as a delay line of `PIPE_STAGES` = 6 slots at `TRANSPORT_MPS` = 1.3 m/s,
  never faster than `MIN_TRANSIT_S` = 0.6 s (`:53-55`).
- **Feed.** `_tick_feed` (`:3446`) draws `FEED_RATE` = 8 kg/s from a bale on a
  head's feed point into its `in`, and adds it to `fed_mass`.
- **Rate.** LineFlow ticks at 10 Hz (`FLOW_TICK_DT` = 0.1, `:3211`).
- **The ledger.** `ledger_residual()` (`:3156`) is `fed + water_added − gran −
  waste − contam_removed − water_removed − poly_rejected − in_transit_mass()`,
  and `in_transit_mass()` is every node's `in` + `out` plus `pipe_mass()`.
  Eleven files under `src/tests/` read it; `test_line3c_identity` holds it to
  `max(0.05 kg, 1 % of the kg fed)` (`:578`).
- **The census gate.** `tools/audit/material_census.py`, one of the four stdlib
  gates `run.sh` exits on, flags any file that touches `MaterialBatch` and
  consumes (`split_*`) without emitting (`add`/`merge`), or builds mass without
  debiting a source, unless it is a named `BOUNDARY`.
- **The unit.** `MaterialBatch` carries mass, volume, polymer composition,
  `water_kg` and `contaminant_kg`; `split_fraction`, `split_mass` and `add`
  conserve all of them (`MaterialBatch.gd:97-155`). Its header already
  describes the design this doc arrives at: "at transformation points … a
  batch is EXPANDED into physicalised particles for the duration it's in that
  zone, then RE-SNAPSHOTTED back into a batch on the way out" (`:9-11`). It was
  never built; nothing in `src/` expands a batch.

### 3.2 Pieces that already exist

- **`BeltSurface`** (`src/sim/BeltSurface.gd`): a belt body's
  `constant_linear_velocity`, refreshed each physics tick and ramped (τ 1.5 s,
  2.5 s on heavy intake belts). Bales, the lump cart and dropped tools already
  ride belts this way. The operator's "a belt is a moving surface" exists for
  rigid bodies today.
- **`FilmFlakeField` belt mode** (`src/sim/FilmFlakeField.gd:26-58`): a heap
  mesh plus GPU-scrolled flakes whose depth is DERIVED from LineFlow's kg per
  metre. On 2026-09-23 the operator asked for exactly this look with the same
  game as the reference: "use similar method that for instance Gold Mining
  simulator uses for the soil, instead of sand the texture is film"
  (`docs/plant/operator_rulings_2026-09-23.md:26`, CLAIMED). So Gold Mining
  Simulator was already the reference for the LOOK; R3 makes it the reference
  for the PHYSICS.
- **`FloorPile`** (`src/sim/FloorPile.gd`): a cone at a 33° angle of repose
  that holds kg and grows a solid collider.
- **The doseersilo's own bed**: `_m_doseersilo` attaches a film field on the
  trough floor at `DOSEERSILO_BED_SPEED_MPS` = 0.05 (`PlaceableCatalog.gd:1250,
  5750-5754`). Visual only.

### 3.3 The 3C doseersilo and what feeds it

**The model** (`PlaceableCatalog._m_doseersilo`, `:5682`, built from rulings
2026-09-23 §17 and §19):

- An open trough with a flat bottom and vertical walls, 2.98 m wide and
  5.57 m long, tilted 22.5° about X. The low end is the inlet, the high end the
  outlet, the lowest point is 1.7 m up. The wall height, 1.0 m
  (`DOSEERSILO_DEPTH_M`), is "a stated placeholder" (`:1221-1227`).
- Three augers on the floor at x = −0.745, 0, +0.745 m: flight radius 0.268 m
  (Ø 0.536 m), shaft radius 0.089 m, driven from the high end, 60 rpm nominal
  (`_spinning_auger`). **The flighting is decoration:** tilted discs every
  ~0.35 m that "fake the helix pitch" (`:2571-2578`). No helicoid exists.
- In LineFlow its profile sets only the ports (`MachineFlow.gd:402-408`), so
  its rate is the 6.0 kg/s default (`:34`), 21.6 t/h. Its three augers are
  components with topology `"parallel"`, combined as an AVERAGE
  (`LineFlow.gd:2146-2214`, `2960-2975`). That is the averaging R3 rejects.
- It is the head of `LINE_3C_SEQ` (`BuildMode.gd:391`), so bales feed straight
  into it. No conveyor feeds it in the sim.

**The HMI** (`docs/plant/hmi_screen_inventory_2026-07-28.md`, "L3C.1 Doseer
Silo", read from the photo `IMG-20240811-WA0006.jpg`, which is local-only):

- three uittrekschroeven (links, midden, rechts) at **8 / 8 / 9 Hz** and
  **5.76 / 6.11 / 5.12 A**, Loopbewaking 15000 ms;
- a level bargraph reading **0-300 cm**;
- level rows Alarm hoog niveau / Stop vullen / Start vullen. So the silo's level
  switches its own feed on and off: whatever fills it is controlled from here.

The SCADA export has `scada/3c/info/1/{em, niveau meting, schroef 1..3}`
(`src/data/plant/line3c_scada_tags.json`).

**Throughput.** The EREMA BluPort photos of 21-12-2024 read 1216, 1321, 1344,
1347 and 1367 kg/h of granulate on line 3C
(`docs/plant/swi/PHOTO-erema-bluport-lijn3C-*`). `Line3CDef.LINE_SPEED_KG_H` is
1687 (SCADA "Techical overview", `Line3CDef.gd:5, 50`). The brief says about
1 t/h (CLAIMED). The doseersilo is the wash line's head, so it carries wet,
dirty feed, more kg than the granulate; no document gives its kg/h. This doc
works with 1.0-1.7 t/h.

**What feeds it: not known.** `docs/plant/fixed_equipment_inventory.md:52`
lists an "HMI — Transportbanden 3C/6" for the 3C/6 intake conveyor cluster in
Hal 8, and `:49` a shredder HMI for 3C/6. `LINE_3C6_SEQ` builds opzetband_3c6
→ shredder_1 → inclined_belt_8m → trilzeef (`BuildMode.gd:359-364`) and does not
link to the doseersilo. Which belt drops into the doseersilo, how fast, how
wide and where: question Q1.

**The material.** Shred before any wash (the bezinkafscheider L3C.3 comes
next). The sim's stated bulk density for fresh shred is 60 kg/m³
(`BeltBuilder.SNIPPER_BULK_KGM3`, `BeltBuilder.gd:52-65`, an assumption).
Vendors give 20-60 kg/m³ for loose film flake, 32 kg/m³ for shredded bags and
52 kg/m³ for plastic fluff (SOURCED [33][34][36][38]).

### 3.4 The game's physics engine is Rapier3D, not Jolt

- `project.godot:419`: `3d/physics_engine="Rapier3D"`, since `1a2e2e2`
  (2026-07-22, "Sync tail: Rapier3D default").
- `addons/godot-rapier3d/plugin.info.cfg`: version 0.8.34, flavour
  `godot-rapier-3d-single-enhanced-determinism`.
- On 4.7.2 the boot log reads `PHYSICS ENGINE 3D: Rapier3D v0.8.34`
  (`docs/audit/godot_4.7_migration_trial_2026-09-26.md:107`).

The 2026-07-15 feasibility doc (`docs/research_film_physics_feasibility.md`)
recommended Jolt and said NO-GO on a Rapier backend swap; the project made
the swap a week later. Every "Jolt" in that doc and in this task's brief is an
engine the game does not run. §6 measures both.

---

## 4. How games and real-time simulators do it (SOURCED)

Numbers in brackets are the sources in §13. "[snip]" marks a claim seen only
in a search snippet because the page would not open; treat it as weaker.

### 4.1 The one pattern everyone uses

No real-time system found simulates a pile grain by grain. Every one that is
documented splits the material in two:

- a **resting store** (a heightfield or a voxel occupancy grid) that costs
  almost nothing while nothing touches it, and
- a **small moving set** (particles or rigid chunks) where a tool, a fall or a
  slope failure is happening,

and converts material between them in both directions. AGX Terrain (Algoryx)
documents this best [1][2]; CM Labs Vortex does the same (particles that come
to rest are put back into the terrain, 1/60 s steps, the particle count can be
capped) [3][4].

Games mostly do not conserve mass:

- **Gold Rush / Gold Mining Simulator** (Code Horizon, Unity [17]): the
  terrain is heights; digging lowers the top value, and digging from below
  deletes what is above, on purpose [16]. Nothing on how the excavator moves
  dirt was found.
- **Hydroneer** ("voxel based terrain" [18] [snip]): a shovel always takes a
  full load, whatever the pile holds, so dirt can be duplicated [19].
- **Spintires / MudRunner**: a heightfield with a mud layer (a 128×128 mud
  height per 16 m block) deformed by "primitives" drawn from each wheel; big
  mud chunks are rigid bodies [15].
- **Farming Simulator** (GIANTS): heaps are a density-map height layer with a
  `maxSurfaceAngle` per fill type (26 for wheat) and a "tip collision" map that
  keeps heaps out of walls [20][21] [snip].
- **Factorio and Satisfactory** belts are not physics: Factorio stores the
  gaps between items [22], Satisfactory places instanced meshes from a shader
  [23].

INFERRED: a plant sim with a kg ledger can copy their store-plus-movers shape
but not their bookkeeping. Gold Rush's "feel" is a heightfield store deformed
by a tool; its loss of mass is a design choice this project cannot make.

### 4.2 Techniques

| technique | how it works | real-time cost (SOURCED) | mass | belt / screw in it |
|---|---|---|---|---|
| **Heightfield + talus relaxation** (Sumner et al. 1999 [10], thermal erosion [11]) | columns on a grid; a body pushes columns down and the displaced volume goes to the nearest free columns; slopes steeper than the angle of repose shed height downhill | Sumner: ~37,000 active columns of >2 M; GPU erosion variants, no ms given [11]; a 2.5D depth-integrated sand model runs at "real-time frame rates" on a GPU [12] | exact if every decrement equals an increment; Sumner's compression and race-ignoring GPU writes are not [10][11] | a belt can advect columns (MudRunner's mud offset [15]); a screw inside a pile has no natural form |
| **Hybrid store + active particles** (Onoue-Nishita 2003 [13], Vortex [3], AGX Terrain [1]) | resting material in a heightfield/voxels, moving material as particles; tool contact or failure converts store → particles, particles at rest merge back | AGX: 0.1 m voxels + ~1,000 particles at a 10 ms step in real time; its DEM reference (200,000 × 50 mm particles, 1 ms step, 250 iterations) ran ~2000× slower on an i7-8700K [1] p.29 | AGX: every mass exchange preserves total mass by construction (p.23); swell changes volume, not mass | the tool acts on the active zone; AGX's "soil deformer" faces push material at the body's velocity projected on each face's normal [1] Fig. 8 |
| **DEM** (each grain a contact body) | Hertz-Mindlin contacts, tiny steps | a 250,000-particle hopper over 40 s: 3 h on 16 cores at Δt = 10 µs [9]; studies use 100 k to millions of particles [9] | exact (fixed particle mass) | the reference method for screws (Owen & Cleary 2009 predicted screw mass flow close to experiment [45] [snip]); offline only |
| **Position-based dynamics** (Macklin et al. 2014, NVIDIA FleX [5]) | particles, position-level friction that gives steep piles; friction depends on the iteration count | sandcastle: 73k particles, 2 substeps, 12 iterations, 10.2 ms/frame on a GTX 680; 1,000 objects × 44 particles: 4 ms [5] | exact (fixed mass) | moving colliders; particle sleeping freezes slow particles [5] |
| **MPM / FLIP** (continuum sand) | particles carry the state, a grid solves the continuum | 6.7 M particles: 38.4 s per frame, and the authors call it far from real time [6]; 1.33 M snow particles at 68.5 fps on four V100s [7]; up to 500 k on a CPU at interactive rates [8] | exact (fixed mass) | moving boundary conditions; GPU pipeline needed |
| **Falling-sand cellular automaton** (Noita [14]) | per-cell rules on a grid, chunked, multithreaded | no numbers found | exact if the rules only move cells | 2D; its 3D analogue is the voxel store |

### 4.3 AGX Terrain, the template (SOURCED [1][2])

- **Store.** Voxels with a solid occupancy 0-1, a compaction and a velocity
  each. The surface heightfield is the top voxel's fill level, so it is
  single-valued (p.17). A "fluidized mass" buffer exists so that total mass is
  conserved.
- **Store → particles.** When a cutting edge enters the soil, a wedge-shaped
  active zone is predicted. The voxel mass inside it is converted into
  particles, new or grown, between a minimum and a maximum diameter, exchanging
  mass only within 3×3×3 voxel bins.
- **Particles → store.** A particle at rest outside an active zone merges once
  its contact velocity, distance and a delay pass thresholds (merge speed
  0.06 m/s by default [2]); its mass is spread over the adjacent voxels
  within the maximum angle of repose (p.15).
- **Relaxation.** A cellular automaton moves mass downhill until no slope is
  steeper than the angle of repose, optionally capped per step, which acts as a
  maximum flow rate (p.19).
- **Tool coupling.** The tool feels the active zone as an aggregate body joined
  to it with a compliant, force-limited lock.
- **Cost.** 0.1 m voxels and ~1,000 particles at a 10 ms step in real time,
  against a DEM reference ~2000× slower (p.29). As few as 25 solver
  iterations (p.24).

### 4.4 The screw: the formula an emergent model must reproduce (SOURCED)

TUM / Logistics Journal 2006, a method built closely on DIN 15262 [28]:

    I_V = (π/4)(D² − d²) · φ · S · n · ζ

D screw diameter, d shaft diameter, φ fill ratio, S pitch, n speed. ζ ≤ 1 is
the **co-rotation factor**: the axial speed is `(S/2π)(ω_screw − ω_material)`,
so material that turns with the screw is not conveyed. ζ is found by
experiment. INFERRED: ζ is exactly what an emergent model has to produce by
itself from friction against flight, trough and neighbouring material.

- The kg/h form uses a loading α of 0.12-0.15 for "non-free-flowing" material
  and an inclination factor C of 0.65 at 20° [29].
- CEMA's standard trough loadings are 15, 30 and 45 % [30].
- A screw FEEDER under a silo is always flood loaded; a constant-pitch screw
  draws from the rear first and causes ratholing, so mass-flow feeders grow
  their flight volume toward the discharge [32].

### 4.5 The belt

`StaticBody3D.constant_linear_velocity` leaves the body where it is but moves
what touches it as if the body moved; the Godot docs name conveyor belts as
the use [43]. At the head pulley a fast belt throws material off at the
tangent at belt speed; a slow one lets it ride around the pulley; the
criterion is v²/(r·g) against cos θ [42]. INFERRED: a friction-driven blob
leaving at belt speed on a ballistic arc is the belt's acceptance test.

### 4.6 What film does in a silo (SOURCED)

- Loose film flake bridges: light flakes arch over a hopper opening and
  starve the screw, with throughput swings of ±30 % [38]. Shredded bags
  bridged, and a screw rat-holed and balled up at its discharge [34].
- **Why three floor screws:** a KWS feeder for plastic fluff uses three
  screws, each with its own drive, and **vertical hopper walls** against
  compression and bridging [33]; live bottoms draw material evenly over the
  whole opening for materials that pack or bridge [32]. The 3C doseersilo is that machine: vertical walls, three
  screws, one VFD each (8/8/9 Hz on the HMI).
- **No angle of repose for film was found.** PET bottle flakes stack at more
  than 80° [41]; FleX notes that simulated friction, and so the repose angle,
  depends on the iteration count [5].
- **A heightfield cannot bridge or rathole**: a column holds one height (AGX
  p.17). If the operator wants to see a bridge form over a screw, the store
  must allow overhangs (voxels) or the blobs must stay rigid bodies there.
  Question Q4.

---

## 5. What runs in Godot 4.7 and in this project

SOURCED unless marked; sources are the [G…] entries in §13.

### 5.1 The rigid-body engines

**Rapier3D 0.8.34, what the game runs.**

- The installed flavour, `single-enhanced-determinism`, is built with neither
  SIMD nor `parallel`. Its Windows build features are
  `"enhanced-determinism,serde-serialize,experimental-threads,register-docs"`
  against `"simd-stable,serde-serialize,parallel,…"` for the other flavour,
  and the locked rapier3d 0.32 refuses SIMD with enhanced determinism at
  compile time [G1]. So the solver is single-threaded and scalar.
- From godot-rapier 0.35.0 (2026-08-08) there is one flavour; its Cargo.toml
  says enhanced determinism now costs no measurable speed and combines with
  SIMD and `parallel` [G1]. Upgrading is a separate change; the
  4.7 migration plan's rule is one variable at a time
  (`docs/PLAN_godot_4.7_migration_2026-09-25.md`).
- **A belt in Rapier is not friction.** In 0.8.34 a contact with a static body
  that has `constant_linear_velocity` makes the next sync call
  `set_linear_velocity` on the dynamic body, overwriting its velocity, and the
  angular velocity the same way [G2]. INFERRED: a blob on a Rapier belt moves
  at exactly belt speed with no slip, and a blob touching two moving surfaces
  takes whichever one synced last. That is why `BeltSurface` works for bales
  but is not a surface model a screw can be built from (measured in §6.2).
- The maintainer's own benchmark on Godot 4.7 (0.35, parallel SIMD, one run,
  hardware unstated): 8,000 boxes dropped into a pit, step p50 13.69 ms for
  Rapier against 21.80 ms for Jolt [G3]. It does not describe the installed
  build.
- Salva `Fluid3D` (SPH, two-way coupled with Rapier bodies, positions readable
  as `get_points()`) is a liquid solver with one global particle radius; no
  granular or friction model is in its feature list [G4].

**Jolt, built into Godot.**

- Default only for projects CREATED from 4.6 on; an existing project keeps the
  engine it names [G5].
- Runs its jobs on Godot's `WorkerThreadPool`, on all logical cores by
  default [G6].
- Defaults that matter at blob scale: `max_bodies` 10,240,
  `max_contact_constraints` 20,480, `max_body_pairs` 65,536 [G7]. A pile of
  10,000 blobs needs the first two raised (INFERRED: ~3-6 contacts per resting
  sphere).
- Surface velocity goes through Jolt's per-manifold contact settings, i.e.
  through friction; Jolt's author calls the angular case approximate [G8].
  Islands sleep as a whole.

**Both.** `AnimatableBody3D` estimates its velocity from how it moves, so a
rotated screw pushes with the right contact velocity [G9]. A concave trimesh is
the slowest 3D collision shape, and small fast bodies can clip through it
[G10]. Screws and walls should be convex pieces.

### 5.2 The GPU paths

- **`GPUParticles3D`** cannot pile: particles collide only with
  `GPUParticlesCollision3D` nodes, never with each other, at most 32 colliders
  per system; there is no position readback; and an open bug has particles
  freeze or ignore a moving collider [G11]. Visual only, as the 2026-07-15 doc
  already said.
- **Compute shaders** need a RenderingDevice, which the Godot docs say is not
  available in headless mode [G12]. MEASURED this session (§6.1):
  `create_local_rendering_device()` and `get_rendering_device()` both return
  null under `--headless` on this machine. **So a solver that carries kg on the
  GPU cannot run in any headless suite**, which is where every regression test
  in this repo runs. Reading data back also costs frames
  (`buffer_get_data_async` calls back some frames later) [G12].
- Existing Godot compute examples: an SPH addon claiming 32k+ particles on
  mid-range GPUs, no rigid coupling; boids at 32,000 on a GTX 1060 [G13].

### 5.3 Native libraries through GDExtension

| library | licence | granular? | runs on | note |
|---|---|---|---|---|
| Jolt (direct) | MIT | rigid bodies | CPU, all cores | already inside Godot |
| Rapier ≥ 0.35 | Apache-2.0 / MIT addon | rigid bodies | CPU, parallel SIMD | an addon upgrade, not new code |
| PhysX 5 PBD particles | BSD-3 | yes (PxPBDMaterial) | **CUDA only** | NVIDIA players only |
| NVIDIA FleX | NVIDIA 1-way commercial | yes | CUDA / D3D DLLs | last pushed 2021 |
| Chrono::DEM | BSD-3 | yes (DEM) | CUDA / HIP | offline-grade |
| LIGGGHTS | GPL-2.0+ | yes (DEM) | CPU | copyleft: a problem for a closed Steam game (not legal advice) |
| Taichi | Apache-2.0 | via user kernels (MPM) | Vulkan AOT | its own device beside Godot's |
| wgsparkl | Apache-2.0 | yes (Drucker-Prager MPM) | WebGPU | experimental, 21 stars |

Bindings: godot-cpp is MIT, godot-rust (gdext) MPL-2.0 [G14].

### 5.4 Terrain and rendering

- Terrain3D (MIT) edits heights at runtime (`set_height`, `update_maps()`), and
  its collision may need regenerating; godot_voxel's physics shapes cost about
  3-5× its meshing [G15]. Both are world terrain, not a
  5 m trough; §8 keeps the store in-house.
- MultiMesh: the whole buffer is set in one call; the dummy (headless) renderer
  drops per-instance writes but stores a bulk `buffer` write, which explains
  the repo's earlier "MultiMesh reads back empty" finding (CLAUDE.md) [G16].
  `FilmFlakeField` already writes transforms once and moves flakes in a shader.

---

## 6. Measured in this session

A throwaway benchmark, outside the repo (§14), headless on this machine:
Godot 4.7.2 console, Intel i7-3770 (4 cores / 8 threads), `--fixed-fps 60` so
each frame is exactly one 1/60 s physics step. It is a SPIKE: it answers "does
it move, what does it cost, what breaks", not "what is the plant's kg/h".

### 6.1 Setup

- **The bin** is the doseersilo model's trough: 2.98 × 5.57 m floor, tilted
  22.5° with the outlet at the high end, lowest point 1.7 m. The walls are 3.0 m
  (not the model's 1.0 m placeholder) so a pile fits.
- **Three screws** on the floor at the model's x positions, radius 0.268 m,
  shaft 0.089 m, as in `_m_doseersilo`. The pitch, 0.40 m, is a placeholder.
  Each screw is a shaft cylinder plus a helicoid of 12 convex plates per turn,
  and leaves the bin through a closed 0.56 m square tube in the high end wall
  (rulings 2026-09-24 round 8: a screw outside its enclosure has a closed top).
- **Two screw forms:**
  - `anim`: an `AnimatableBody3D` turned each physics step, the body moves;
  - `surf`: a `StaticBody3D` helix that stays put, with
    `constant_angular_velocity` about its axis. This is the operator's
    "warped plane moving in one direction" taken literally.
- **Blobs** are rigid spheres of 1.000 L (r = 0.0620 m), 0.060 kg (60 kg/m³,
  the sim's snipper density), friction 0.8, bounce 0, rotation locked (a film
  lump does not roll).
- **Steady inventory** (`feed=1`): a blob that leaves a tube is counted and
  thrown back in over the inlet end at 1 m/s, as off a belt. A blob below
  y = −0.5 m is counted LOST and thrown back the same way.
- **Jolt's limits**: runs named `tp_*` / `cost_*` used Jolt's defaults; runs
  named `tp2_*` / `cost2_*` used raised ones (`max_bodies` 40,960,
  `max_body_pairs` 262,144, `max_contact_constraints` 131,072), added after
  the 10,000-blob loss in §6.3.
- **Timing**: the wall time between frames after a settle period. Other
  sessions' Godot processes used between 0.3 and 5 cores meanwhile; each row
  below gives that load. Compare rows, not absolute ms.
- **Check**: `create_local_rendering_device()` and `get_rendering_device()`
  under `--headless` both return null. There is no GPU compute in a headless
  run.

### 6.2 Does throughput emerge?

3,000 blobs, 20 rpm, 5 s settle, 20 s measured (1 min of wall time or more).
kg/h is the blobs out of the three tubes in the 20 s, × 0.060 kg, × 180.

| engine | screw form | screws turning | kg/h out | lost in 20 s | other cores | notes |
|---|---|---|---|---|---|---|
| Jolt | anim | all 3 | **637** | 3 | 1.1 | `tp_jolt_anim_all` |
| Jolt | anim | 1 (left) | **32** | 1 | 1.1 | `tp_jolt_anim_one` |
| Jolt | anim | none | **0** | 0 | 1.4 | whole pile asleep |
| Jolt | anim, reversed (−20 rpm) | all 3 | **0** | 0 | — | mean blob position moved 0.90 m toward the inlet; `dir_jolt_anim_m20` |
| Jolt | surf | all 3 | **0** | 0 | 1.4 | every blob asleep |
| Jolt | surf, blobs never sleep | all 3 | **0** | 0 | 1.8 | `tp2_jolt_surf_nosleep_all` |
| Rapier 0.8.34 | anim | all 3 | 1210 | **260** | 0.3 | a blob flung to y = 148 m; `tp_rapier_anim_all` |
| Rapier 0.8.34 | anim (first run, 10 s measured) | all 3 | 929 | **143** in 10 s | — | `v2_rapier` |
| Rapier 0.8.34 | surf | all 3 / 1 / none | **0 / 0 / 0** | 0 | 1.3-2.1 | every blob asleep |
| Rapier 0.8.34 | surf, blobs never sleep | all 3 | **0** | 0 | 0.9 | `tp2_rapier_surf_nosleep_all` |
| Rapier 0.8.34 | anim, `sync_to_physics` on | all 3 | 1415 | **204** | 1.5 | a blob flung to y = 157 m; `tp2_rapier_animsync_all` |
| Rapier 0.8.34 | anim, `sync_to_physics` on | 1 (left) | 130 | **51** | 1.7 | `tp2_rapier_animsync_one` |
| Jolt | anim, **10 rpm** | all 3 | **54** | 0 | ? | `tp2_jolt_anim_all_rpm10` (the load reading went negative: a process ended mid-run) |
| Jolt | anim, **40 rpm** | all 3 | **1555** | 11 | 1.3 | `tp2_jolt_anim_all_rpm40` |
| Jolt | anim, blobs are 1 L **cubes** | all 3 | **1026** | 0 | 1.0 | 57 ms/step against 24 for spheres; `tp2_jolt_anim_all_box` |

What that shows:

1. **A turning screw moves material and a stopped one does not.** Reversed,
   it moves material back toward the inlet. Nothing in the bench states a
   rate: the kg/h came out of contacts. That is R3's claim, shown in a rigid
   body engine (Jolt).
2. **A surface-velocity screw moves nothing, in both engines, asleep or
   awake.** Jolt applies surface velocity through friction per contact
   manifold [G8], and Rapier overwrites the body's velocity [G2]; neither
   pushes along a helix. So the screw must be a body that turns.
3. **Rapier 0.8.34 cannot hold blobs against a turning screw.** 143, 260 and
   204 blobs left the bin in three runs, with `sync_to_physics` off and on,
   one of them 157 m up. Jolt lost 0-11 in the same kind of runs. As shipped,
   the game's engine fails A2.
4. **The kg/h is far from calibrated.** Three Jolt screws gave 637 kg/h: 212
   kg/h per screw where the formula (§4.4) gives 5,780 kg/h at φζ = 1 for this
   geometry and speed, i.e. **φζ ≈ 0.04**. One screw alone gave 32 kg/h, not a
   third of 637; Rapier's pair was 1415 and 130, the same pattern. Why is not
   known. One untested hypothesis: a lone screw clears a channel above itself
   that the frictional pile does not refill, the rat-holing the feeder
   literature describes for constant-pitch screws [32].
5. **The kg/h is not proportional to the speed.** 10, 20 and 40 rpm gave 54,
   637 and 1555 kg/h: ×2.4 from 20 to 40, but ×12 from 10 to 20. The formula
   (§4.4) is linear in n for a flooded screw, so the spike fails A5 as it
   stands. Counts are small (5, 59 and 144 blobs in 20 s), but not that small.
6. **The blob's shape moves the kg/h too.** The same run with 1 L cubes
   instead of spheres gave 1026 kg/h against 637, lost none, and cost 2.3×
   the frame time (57 against 24 ms).

Points 4-6 are the risk in §11: the numbers emerge, but they depend on
everything and match nothing yet.

### 6.3 What it costs

**A resting pile** (screws present, nothing pushing; 5 s settle, 5 s measured):

| blobs | Jolt ms/step | asleep | Rapier 0.8.34 ms/step | asleep |
|---|---|---|---|---|
| 1,000 | 1.0 | 1,000 | 2.8 | 1,000 |
| 3,000 | 3.0-4.2 | 3,000 | 15-28 | 1,613-3,000 |
| 6,000 | 6.7 | 6,000 | 93 | 109 |
| 10,000 | 142 (default limits: see below) | 977 | 189 | 125 |

- Jolt puts a settled pile to sleep and then it costs ~1 ms per 1,000 blobs.
  Rapier's pile sleeps slowly, and a pile that is awake costs far more.
- **Jolt at 10,000 blobs with its default limits lost blobs through the floor:
  22,350 falls in 9 s** (each thrown back in and counted again). The run
  exceeds the default `max_contact_constraints` of 20,480 [G7], which fits;
  the cause was not isolated. A ledger that deletes lost blobs would have
  lost the whole silo.

- **With raised limits** (`max_bodies` 40,960, `max_contact_constraints`
  131,072) the same 10,000-blob pile lost nothing and fell asleep: 13 ms p50,
  27 ms mean (`cost2_jolt_surf_10000_limits`). So the limits were the cause.
  Any Jolt build of this must set them.

**An active pile** (the screws turning at 20 rpm, 4 s settle, 5 s measured):

| blobs | Jolt ms/step | lost | other cores | Rapier 0.8.34 (`sync_to_physics`) ms/step | lost | other cores |
|---|---|---|---|---|---|---|
| 1,000 | 9.2 | 0 | 2.7 | 16.2 | **28** | 2.9 |
| 3,000 | 36.3 (19-24 in the throughput runs at 1.1 cores) | 0 | 2.4 | 52.0 | **68** | 2.1 |
| 6,000 | 73.6 | 1 | 1.7 | 124.0 | **72** | 2.1 |
| 10,000 | 144.8 (raised limits) | 0 | 1.8 | — | — | — |

Jolt costs ~12-14 ms per 1,000 active blobs on this PC with ~2 cores taken by
other work, and ~7 ms per 1,000 with ~1 core taken; Rapier ~17-20 ms per
1,000 and keeps losing blobs. Held awake with nothing turning, 3,000 blobs
cost 21.5 ms in Jolt and 73 ms in Rapier. **One active doseersilo at 1 L
blobs does not fit a 60 Hz frame on this PC in either engine.**

### 6.4 A solver of our own, in GDScript, and the heightfield store

`cpu_bench.gd what=pbd`: the minimal position-based step (uniform grid,
27-cell neighbour search, 2 contact iterations, box walls), one thread:

| particles | ms per 1/60 s step | contacts |
|---|---|---|
| 1,000 | 20.9 | 400 |
| 3,000 | 84.1 | 4,400 |
| 10,000 | 292.5 | 18,400 |

GDScript is ~20 ms per 1,000 particles with only 2 iterations; FleX needed 12
iterations for good piles [5]. **GDScript cannot be the blob solver.** A native
solver would have to be measured on its own (not done).

`cpu_bench.gd what=hf`: the doseersilo floor at 0.10 m cells (29 × 55 = 1,595
columns), a talus rule at 45°, 1 L deposited per tick at the inlet:

| sweeps per tick | ms per tick (GDScript) | volume added | volume in the grid |
|---|---|---|---|
| 4 | 19.9 (max 36.8) | 0.6000 m³ | 0.6000 m³ (+1.8e-7) |
| 16 | 71.0 (max 124.3) | 0.6000 m³ | 0.6000 m³ (+1.6e-6) |

- Relaxing the WHOLE grid every tick is too slow in GDScript. The store
  should relax only the columns something changed, at LineFlow's 10 Hz, or
  in native code (INFERRED; neither measured).
- The volume closed to 1.8e-7 m³ over 600 ticks at 4 sweeps and 1.6e-6 m³
  at 16: float32 rounding (`PackedFloat32Array`), growing with the number of
  moves. The store's kg must be doubles: a `MaterialBatch`
  per column, as §9.1 has it.

---

## 7. Cost at plant scale

INFERRED arithmetic from the stated inputs; the per-blob costs are §6's.

### 7.1 How many blobs the 3C doseersilo means

A blob is 1 L of bulk film, so it weighs the bulk density in grams. Three
densities (the vendors' 30 and the sim's 60 and 90 kg/m³) against three
throughputs (the brief's 1.0 t/h, the BluPort's 1.37 and SCADA's 1.69):

| bulk density | blob | 1.0 t/h | 1.37 t/h | 1.69 t/h |
|---|---|---|---|---|
| 30 kg/m³ | 30 g | 9.3 blobs/s | 12.7 /s | 15.6 /s |
| 60 kg/m³ | 60 g | 4.6 /s | 6.3 /s | 7.8 /s |
| 90 kg/m³ | 90 g | 3.1 /s | 4.2 /s | 5.2 /s |

- **The feed belt**: the rate over the belt speed. At 1.0 m/s (the operator's
  "other conveyors", rulings 2026-09-23) that is 3-16 blobs per metre, so a
  10 m belt carries 30-160 blobs. Cheap.
- **The fall**: a blob falls ~0.5 s, so 2-8 are in the air at once. Cheap.
- **The pile**: the inventory in litres. 1 m³ is 1,000 blobs, 5 m³ is 5,000;
  the model's trough with its 1.0 m walls holds 16.6 m³ (16,600), with 3 m
  walls 49.8 m³. At 1 t/h and 60 kg/m³, 3 m³ is 11 minutes of feed and a full
  1 m trough an hour.
- **The screws' layer**: the annulus between shaft and flight tip is
  (π/4)(0.536² − 0.178²) × 5.57 m = 1.12 m³ per screw, 3.35 m³ for three. With
  spheres packing at about 0.6 that is **~2,000 blobs that are awake whenever
  the screws turn**, however little is piled above them.

So the doseersilo alone needs ~2,000 active blobs while it runs, plus a
resting pile of 1,000-16,000 more depending on the level, which is a store (a
heightfield) in the hybrid and bodies otherwise.

### 7.2 What each option costs for that silo

From §6 on this PC (other cores busy, so read the ratios):

| option | resting pile of 3,000 | 2,000-3,000 active blobs | verdict for one silo at 60 Hz |
|---|---|---|---|
| rigid blobs, Jolt | 3-4 ms (asleep) | 19-36 ms at 3,000, by the other load (~7-14 ms per 1,000) | 1.2-2.2 frames at 3,000; the hybrid's ~2,000 would be about one frame (INFERRED) |
| rigid blobs, Rapier 0.8.34 | 15-28 ms | 47-52 ms turning, 73 ms held awake; loses blobs | no |
| rigid blobs, Rapier ≥ 0.35 (parallel SIMD) | not measured | not measured | unknown; the maintainer's drop test has it ahead of Jolt [G3] |
| hybrid: heightfield store + Jolt blobs | the store's cost (§6.4) | as the row above, for the screw layer only | the store makes the resting pile nearly free; the screw layer sets the cost |
| own PBD solver in GDScript | — | 84 ms at 3,000 | no |
| own PBD solver, native (C++) | — | not measured | unknown; FleX did 73k particles in 10.2 ms on a 2012 GPU [5], AGX 1,000 particles + voxels at a 10 ms step on a CPU [1] |
| GPU compute solver | — | cheap | cannot carry kg: no device headless (§6.1) |

### 7.3 The whole plant

About 70 of the 200 macro machines are granular (§10.1: 10 silos with
screws, 40 moving surfaces, 16 screws, 4 chutes, 3 vibrating decks). If all ten
silos ran physically at once and each were a doseersilo, that is ~20,000
active blobs, ~140-280 ms per step in Jolt on this PC at the 7-14 ms per
1,000 of §6.3 (INFERRED: linear, measured to 10,000). Belts carried
parametrically cost next to nothing, but piles and screws do not. Hence §9.6: physical where the player is, or bigger blobs, or a
faster solver. That trade is the operator's (Q5, Q8).

---

## 8. The options compared

| # | option | moves film by | kg ledger | runs headless | cost for one silo (§7.2) | verdict |
|---|---|---|---|---|---|---|
| A | rigid blobs in Rapier 0.8.34, as the game ships | kinematic screw bodies | exact, but blobs escape (§6.2) | yes | 47-73 ms at 3,000 | **NO**: loses blobs, single-threaded |
| A′ | rigid blobs in Rapier ≥ 0.35 (parallel SIMD, deterministic) | the same | exact if A2 holds | yes | not measured | **measure first** (Q7): the smallest change for the rest of the game |
| B | rigid blobs in Jolt | kinematic screw bodies | exact; raise the limits (§6.3) | yes | 19-36 ms at 3,000 | **works** in the spike; means moving the whole game to Jolt (Q7) |
| C | an own particle solver (PBD), native code | analytic helicoid, belt and trough | exact | yes | GDScript 84 ms at 3,000; native not measured | a fallback if A′ and B miss the budget (Q7, Q8) |
| D | a GPU compute solver (PBD or MPM) | anything | exact on the GPU, but unreadable headless | **no** | cheap | **NO** for anything that carries kg; fine for looks |
| E | `GPUParticles3D` | colliders only | none (no readback) | — | cheap | **NO**: particles do not touch each other, cannot pile [G11] |
| F | MPM / FLIP continuum sand | a grid solver | exact | GPU only | 6.7 M particles 38 s/frame [6] | **NO**: not real time, not film |
| G | a heightfield alone (the Gold Rush way) | a tool deforms the heights | exact if every move is paired | yes | ~nothing | **as the store only**: it cannot hold a screw inside a pile, a fall or a bridge |
| H | Salva `Fluid3D` (SPH) | liquid pressure | exact | yes | not measured | **NO** for film piles; a candidate for the WATER that moves the frictiewasser (R2), later |
| **R** | **the hybrid: G's store + active blobs from A′, B or C** | moving bodies where film moves, heights where it rests | exact by the §9.4 contract | yes | the screw layer (~2,000 blobs) sets it | **recommended** |

The recommendation R is independent of the solver. The store, the ledger
contract, the ports, the save and the tests (§9) are the same whether the
active blobs run in Rapier 0.35, Jolt or a native solver of our own. Only the
blob solver is Q7.

---

## 9. Recommended design

INFERRED throughout: a design, not a measurement. What each part must prove
is in §9.8.

### 9.1 The shape: a store plus active blobs, per machine (AGX's template)

A physical machine gets a **bulk zone**: a node under its body that owns

- a **store**: columns on a 0.10 m grid over the machine's floor, each with a
  height and a `MaterialBatch`;
- the **active blobs** in the zone, each a body with a `MaterialBatch`;
- its **ports**: emitters where material arrives, absorbers where it leaves.

Material converts both ways:

- **store → blobs** where something moves it: inside the screws' envelope
  plus a margin, where a falling blob lands, and where a slope is steeper than
  the angle of repose. Whole blobs are split off the column's batch
  (`split_mass`) and spawned at the column's top.
- **blobs → store** where a blob has rested (speed under a threshold for a set
  time; AGX uses 0.06 m/s [2]) outside every active region: its batch is added
  to the column below (`add`) and the column grows.
- **relaxation**: a column steeper than the angle of repose passes part of its
  batch downhill (`split_fraction` → `add`), capped per tick as AGX does, which
  sets a maximum slide rate.

For the doseersilo, the screws run the full length of the floor, so the
active region is the whole bottom layer while they turn; the store is the
pile above it. The deeper the silo is filled, the more the store saves.

**Blob mass, not blob size, is what the ledger sees.** A pile of rigid 1 L
spheres packs at some fraction φ_pack below 1, so a blob that is to reproduce
a bulk density ρ must weigh `ρ × V_blob / φ_pack`, with φ_pack measured in the
engine (INFERRED). Otherwise the simulated pile is lighter than the plant's by
that fraction.

**Blob size has a ceiling.** The flight depth of the modelled screw is
0.268 − 0.089 = 0.179 m and a 1 L sphere is 0.124 m across, so about one blob
fits between shaft and flight tip. A larger blob cannot enter the flight at
all. So "about a litre" is also about the largest blob this screw can move
(INFERRED from the model's dimensions, which are themselves not measured on
the plant: Q2).

### 9.2 The belt

The operator's rule is that what lies on a belt moves with it. Two ways:

- **Friction** (Jolt's surface velocity): blobs can slip, which is where a
  belt-speed-mismatch heap would come from.
- **Carried** (what Rapier 0.8.34 does anyway: it overwrites the blob's
  velocity, §5.1): no slip, and cheaper still as a parametric position along
  the belt (Factorio's idea [22]), switching to a free body only at the head
  pulley and where blobs heap.

Either way the blob leaves the head pulley at belt speed on the tangent, then
flies ballistically [42]. The feed belt of the doseersilo carries only 3-16
blobs per metre (§7.1), so the belt is cheap whichever is chosen.

### 9.3 The screw

- **Geometry.** A real helicoid, which the model does not have today (its
  flights are tilted discs). As colliders: convex plates, 12 per turn, as in
  the bench (§6), or an analytic helicoid in a solver of our own (§8, option C).
- **Drive.** Measured in §6.2: a KINEMATIC screw (the body turns) moves
  material; a static helix with a surface velocity (the "warped plane moving
  one way" taken literally) moves nothing in either engine. So the screw turns.
- **Speed.** From the HMI: Hz → motor rpm → gearbox → screw rpm. The gearbox
  ratio is unknown (Q2).
- **What else emerges.** The contact impulses on the flights give a torque,
  and so a current. The HMI's 5.76 / 6.11 / 5.12 A at 8 / 8 / 9 Hz would then
  be a second calibration target beside the kg/h.

### 9.4 The kg ledger across the boundary with LineFlow

This is what keeps R1's base and the physical model in one ledger (G4).

1. **The node stays.** A physical machine keeps its LineFlow node, so PLC
   power, spin, HAND, e-stop, choke, SCADA, sound and save keep working. The
   rate law skips it: a `PHYSICAL` flag set when the zone registers, beside
   `RATE_NOT_BY_RPM` (`LineFlow.gd:2024`).
2. **Inflow.** LineFlow keeps delivering into the node's `in` (from a pipe or
   a bale). The emitter drains it into blobs at the upstream's real discharge
   point: `blob.batch = in.split_mass(m_blob)` while `in` holds a blob's worth;
   the remainder waits in `in`. Between two physical zones there is no pipe:
   the blob and its batch cross from one zone to the next.
3. **Outflow.** An absorber at each discharge (the end of each screw tube)
   adds the blob's batch to the node's `out` and frees the blob. LineFlow's
   routing carries `out` on as today.
4. **Counting.** The zone reports its mass (blobs + columns), and
   `in_transit_mass()` adds it for physical nodes, so `ledger_residual()`
   closes with no new term. Water and contaminant ride inside every batch.
5. **Leaks are material, not errors.**
   - A blob over the rim of an open vessel is a spill: it goes to a
     `FloorPile` and into the ledger's waste the way `_dump_waste` does today.
   - A blob below the floor has tunnelled: it goes back to the nearest column
     and is COUNTED. The acceptance run asserts the count is 0.
   - Nothing is ever deleted (§6.2: 260 blobs left the bench bin in 20 s on
     Rapier; a ledger that deletes them would lose 15.6 kg).
6. **Stops.** A stopped screw takes nothing to the absorber, so the kg stay in
   the zone. The "leegdraaien" contract (`LineFlow.gd:3557-3577`) then holds by
   physics instead of by a rule.
7. **Ticks.** The zone runs in `_physics_process` (60 Hz), LineFlow at 10 Hz,
   both on the main thread, so no batch is touched by both at once. A suite
   cannot step physics by hand the way it drives `lf.tick(0.1)`; it runs real
   frames under `--fixed-fps 60`, and waits on sim time, never on a frame
   count (CLAUDE.md, "A frame-counted wait…").
8. **The census.** The zone consumes (`split_mass`) and emits (`add`), so
   `material_census.py` passes it without a `BOUNDARY` entry.
9. **Save and resume** (rulings 2026-09-25 §R1-§R4). The zone implements
   `save_run_state` / `restore_run_state`, which `PlantResume` already walks:
   the columns (height + batch) and the active blobs (position, velocity,
   batch). Saving resting blobs into the store first would keep a save small
   but move them a little: Q9.
10. **The HMI reads the physics.** The level bargraph (0-300 cm) reads the
    pile height at the sensor's position, not kg over a capacity.

### 9.5 Where it runs

- **Everything that carries kg runs on the CPU**, because the headless suites
  have no GPU device (§5.2, §6.1).
- The GPU draws the look: the blob is the physics carrier, the flakes on it
  are a shader, as the belt beds already do (`FilmFlakeField`).
- The engine for the active blobs is an operator decision (Q7): §6 measured
  what each candidate does with a turning screw.

### 9.6 LOD: physical where the player is (a choice, not a given)

Section 7 shows the plant cannot afford 1 L blobs in every silo at once on this
machine. The standard answer is simulation LOD: a zone near the player runs
physically; a zone far away runs a law measured FROM the physical model (kg/h
against screw rpm and fill, per screw set), and hands over by moving its kg
between the zone and the node's `in`, which conserves. That law would be
emergent-derived, not an average someone chose, but it is still a law for the
unwatched machines. Whether that is acceptable is Q5.

### 9.7 What stays out of this model

The operator's own ruling R2 says the frictiewasser is moved by water, not by
its stirrers. Film in water (tanks, frictiescheiders, the prewash drum) is a
hydraulic problem, air transport (blowers, cyclones) a pneumatic one, and
shredders, mills, dryers and the extruder train have their own models. None of
them is a pile on steel. §10 lists them.

### 9.8 Acceptance: what the physical doseersilo must prove (Rule 2, Rule 3)

| # | check | pass |
|---|---|---|
| A1 | ledger: kg fed = kg in zone + kg out + kg spilled, including water and contaminant, with a DIRTY, WET fixture (the `test_plant_resume` §8 lesson) | ≤ 1e-6 relative |
| A2 | no tunnelling in a 10-minute run at full inventory | 0 returns |
| A3 | a screw off moves nothing; reversed, it moves material back toward the inlet | 0 kg out; mean position falls |
| A4 | with one screw off, the pile feeds the others (R3) | kg/h > 0 and the pile drains toward the running screws |
| A5 | flooded, kg/h is proportional to rpm (the formula in §4.4) | linear fit R² ≥ 0.95 over 3 speeds |
| A6 | the model's ζ (from A5 and the geometry) lies in a band the literature allows | to be agreed (Q2) |
| A7 | at the plant's 8/8/9 Hz, with the gearbox and geometry from Q2, the kg/h lands in the 3C band (1.2-1.7 t/h) | within the band |
| A8 | a blob leaves the belt at belt speed and lands where a ballistic arc says | ≤ 1 blob diameter |
| A9 | save → load gives the same kg per column and per blob | exact |
| A10 | two runs with one seed give the same kg out to 1e-9 (Rapier's enhanced determinism was chosen for this) | identical |
| A11 | cost: the zone's physics fits the frame budget the operator sets (Q8) on this machine | measured |

Each gets a mutation (drop the absorber's `add`, delete tunnelled blobs, make
the screws average again) that turns it red.

---

## 10. Replacing the rate law machine by machine

### 10.1 Every macro machine, by how it moves film

The seven line macros place 200 flow machines (VERIFIED: parsed from the
`*_SEQ` constants in `BuildMode.gd`, entries with `"flow": false` or
`"furniture": true` left out). Grouped by mechanism (INFERRED from each id's
catalog name; the counts are per macro placement):

| mechanism | ids (count) | physical model | when |
|---|---|---|---|
| **pile on steel + screws** | doseersilo (1), vss_silo (2), vuilsnippersilo (2), extruder_silo (3), silo (1), mengsilo (1) | store + active blobs + helicoid screws | **phase 1** (doseersilo), **phase 2** (the rest) |
| **moving surface** | transport_belt (7), inclined_belt_8m (5), transportband_1…11 incl. 8.5 (12), compactorband (4), switch_belt (2), opzetband_* (3), uitvoerband_1, drum_feed_belt, bunker deck (1), titech/tomra acceleration belts (4) | blobs carried or on a friction surface | the doseersilo's feed belt in phase 1; the rest in **phase 3** |
| **fall / chute / slide** | transfer_chute, sga_feed_chute, u_bay (a pile the Merlo scoops: Gold Rush's own case), scheidingsgoot (wet) | ballistic blobs, a store where they land | phase 3 (u_bay is the natural place for a loader bucket) |
| **screw in a trough or tube** | transport_screw (10), dewater_screw (4), intrekschroef (2) | helicoid in a closed or open trough | **phase 4** |
| **vibrating deck / sieve** | trilzeef (1), kufferath_sieve (2) | a vibrating surface (not designed here) | later |
| **air** | blower (14), cyclone (8), wind_sifter, ringleiding_3a, heater_cabinet | not granular: **rate law stays** | — |
| **water** | flotation_tank (3), flotation_tank_wide, sink_float, friction_washer (R2), friction_sep (12), vw_trommel, rafter, kleine_la, pomp_c1 | not granular: a water model, separately (R2 is its first rule) | — |
| **comminution** | shredder_1 (3), shredder_2 (2), mill (2) | rate law; a hopper in front could be a zone | — |
| **drying, melt, pellet** | mech_dryer (7), mas_droger (2), mas_bak (2, an agglomeration trough with a paddle drive), compactor, extruders (4), laser_filter (4), melt_pump, kopfilter, vacuum_degas, heetafslag (4), ontwaterzeef (4), centrifuge (4), weegschaal (4), plasmaq (2), voorraad_silo (4, granulate) | existing models | — |

Two things follow. About a third of the flow machines are granular (piles,
belts, chutes, screws), so "replacing the rate law" means those; the rest keep
it, or wait for a model of their own. And the granular ones are exactly where
the operator can see film, which is where R3 asks for it.

### 10.2 Phases

Each phase ends with its acceptance suite green and mutation-proven, the
ledger unchanged on every line suite (`test_line3c_identity`,
`test_macro_edges_reload`, `test_plant_resume`), and a full harness by the
runner.

- **Phase 0, done here** (throwaway, §6): emergence shows qualitatively;
  the installed Rapier ejects blobs from a turning screw; GDScript is too slow
  to be the solver; there is no GPU device headless.
- **Phase 1: the 3C doseersilo and the end of its feed belt.** Needs Q1, Q2,
  Q3 and Q7 answered first.
  1. The helicoid screws and the trough as colliders, built from the same
     constants as the visual model (no second set of numbers).
  2. The zone, its ledger contract (§9.4) and its save/resume.
  3. A probe that prints kg/h against rpm per screw set, then calibration
     against A7.
  4. `LINE_3C_SEQ` keeps the doseersilo at index 0 (append-only), so nothing
     re-addresses; the node gains the `PHYSICAL` flag.
  5. The HMI: level from the pile, amps from the contact torque if A7 holds.
- **Phase 2: the other silos with screws** (VSS 3A/3B with their M11a dosing
  screw, the vuilsnippersilos, the extruder silos, the mengsilo). The same
  zone, different geometry. The VSS feed stop (`_tick_silo_feed_stops`, a
  laser level) then reads a real pile.
- **Phase 3: belts, transfer points and chutes.** The belt-speed-mismatch heap
  (`_tick_belt_heap`, `CHUTE_PACK_KG` = 15, "PLACEHOLDER") becomes a real heap;
  its trip rulings (rulings 2026-09-24 round 9: the chute packs first, then the
  upstream drive trips) become checks on the emergent heap. The U-bay pile
  gets the Merlo bucket.
- **Phase 4: the open and closed screws between machines.**

The rate law is never removed. A machine leaves it the day its zone is
proven, and every machine not yet physical keeps running on it (R1).

---

## 11. Risks and what is not known

- **Calibration is the whole problem.** Emergent kg/h swung by a factor 20
  between one screw and three in the bench, and the bench's φζ is far below
  what the plant needs (§6.2). Friction, blob shape, flight geometry and the
  tube entry all move it. Without the screw data (Q2) the model can be TUNED
  to 3C's kg/h but not VALIDATED against it.
- **Film is not grains.** Real film entangles, is cohesive and compresses: a
  vendor range of 20-60 kg/m³ loose against 120-300 compacted [36]. Rigid
  blobs do not compress, so the pile weighs the same per m³ at the bottom as at
  the top. In a 3 m deep silo that may matter (Q3); nothing here models it.
- **Blobs leave the machine.** Measured: Rapier 0.8.34 threw up to 260 blobs
  out of the bin in 20 s from a turning screw; Jolt at 10,000 blobs with
  default limits let them fall through the floor (§6). The ledger design
  (§9.4 item 5) never deletes a blob, but the physics must still keep them in
  (A2).
- **The engine question is not small.** The game has run Rapier since
  2026-07-22 and everything that drives, carries or opens has been tuned on
  it. Moving to Jolt (Q7) re-opens all of it; upgrading Rapier is smaller but
  still a change of its own, measured alone.
- **This PC is old.** Intel i7-3770 (4 cores, 8 threads), GTX 1070 (VERIFIED,
  WMI). Players' PCs will differ both ways.
- **Slower suites.** A physical zone cannot be stepped by hand, so its suites
  run real frames: minutes per suite, not seconds. The harness gets longer.
- **Determinism.** Rapier's build was chosen for determinism. Jolt's
  multithreaded determinism was not measured here (A10).
- **Save size** grows with blobs (Q9).
- **My timings are contaminated.** Other sessions' Godot processes used
  0.3-5 cores during the runs; each result line in §6 records how many. The
  ratios between runs are more reliable than the absolute ms.

---

## 12. Questions for the operator (AskUserQuestion-ready)

Every option states the GENERAL rule it would make, not only the case,
because a plant answer describes one situation. Three batches, most blocking
first; each
batch fits one AskUserQuestion call (at most 4 questions, 2-4 options). The
first option is the recommendation where there is one.

### Batch 1: facts phase 1 cannot start without

**Q1. What fills the 3C doseersilo?** (header `3C feed`)

- **Belt, level-switched**: one conveyor drops film into the LOW (inlet) end;
  the silo's own level switches that belt off at "Stop vullen" and on at
  "Start vullen" (the three rows on the L3C.1 screen). Tell me its speed, width
  and where it drops.
- **Belt, always on**: the feed belt runs whenever the line runs; the level
  only alarms ("Alarm hoog niveau"), and the switch stops something further
  upstream.
- **Not one belt**: film arrives some other way (two belts, a chute from the
  shredder, a blower); describe it.

**Q2. Where do the screw sizes and speeds come from?** (header `Screws`)

- **Nameplates (Recommended)**: screw diameter, shaft diameter, pitch and the
  gearbox ratio (motor Hz → screw rpm) come from the machine; the model must
  then hit the 3C kg/h at 8/8/9 Hz by itself, which is a real test (A7).
- **Tune to the kg/h**: keep the modelled sizes; tune only the friction so
  that 8/8/9 Hz gives the 3C kg/h. The kg/h is then fitted, not predicted,
  and every other speed is extrapolation.

**Q3. How deep is the doseersilo?** (header `Depth`)

- **About 3 m, like the HMI scale**: the walls are about as tall as the level
  bargraph's 0-300 cm; film can stand ~3 m above the screws.
- **About 1 m, as modelled**: the 300 cm is the sensor's range, not the
  tank; film stands at most ~1 m above the floor.
- (Other: give the wall height and the Stop/Start vullen levels.)

**Q4. Does film hang up in the doseersilo?** (header `Bridging`)

- **Never seen it**: in the doseersilo film always slumps onto the screws;
  the model need not show a bridge, and material at rest may be kept as a
  height field.
- **Yes, sometimes**: film can hang over a running screw and starve it, or
  leave a hole down to it, until someone clears it; the model must be able to
  show that, which means blobs (or a store with overhangs) everywhere in the
  pile, at a higher cost.

### Batch 2: architecture

**Q5. Where must the physical material run?** (header `Scope`)

- **Near the player (Recommended)**: every granular machine has a physical
  model; a machine near you runs it live; one far away runs a kg/h law
  MEASURED from that same physical model (per screw set and fill), and hands
  its kg over without losing any. The only way to have it everywhere on this
  PC (§7).
- **Everywhere, always**: every granular machine runs physically at all
  times, watched or not; no law anywhere once a machine is physical. Needs
  far fewer bodies or a much faster engine.
- **Only machines I name**: physics only where you say (the 3C doseersilo
  first); every other machine keeps today's rate law until you name it.

**Q6. May film at rest become a height field?** (header `At rest`)

- **Yes (Recommended)**: film lying still, away from the screws and from
  where blobs land, is stored as heights (the Gold Rush way) and turns back
  into blobs the moment anything touches it; the kg are identical. It cannot
  show a bridge (Q4).
- **No, blobs everywhere**: every litre is always a blob, moving or still;
  bridges and rat-holes can happen; about one body per litre in the silo.

**Q7. Which physics engine may the blobs run in?** (header `Engine`)

- **Measure Rapier 0.35 first (Recommended)**: the game keeps the Rapier
  engine it runs today, upgraded from 0.8.34 to 0.35 (multithreaded, still
  deterministic, §5.1) in a change of its own; the blobs run in it if it
  passes §6's turning-screw test. Nothing else in the game changes engine.
- **Switch the game to Jolt**: the whole game moves to Godot's built-in Jolt
  (it moved material with a turning screw in §6 without ejecting it); every
  vehicle, bale, door and gate must be re-tested on it.
- **A blob solver of our own**: blobs get a dedicated native solver that only
  knows the machines' geometry (exact helicoids, no thin plates to tunnel
  through); Rapier stays for everything else; players and vehicles do not
  push blobs.

**Q8. How much of a frame may one physical silo take on this PC?** (header
`Budget`)

- **A few ms, 60 fps holds**: the physics of the material you are near must
  leave the game at 60 fps on the i7-3770; if it cannot, blobs get fewer or
  the zone shrinks.
- **Up to a frame for now**: during development a physical silo may cost up
  to ~16 ms; optimisation comes later.
- **Only on a faster PC**: the physical model is for machines better than
  this one; the i7-3770 runs the law.

### Batch 3: later

**Q9. When you save, may blobs lying still be packed into the pile?**
(header `Save`)

- **Yes, pack them**: a save keeps every kg exactly but not the position of
  each resting blob; moving blobs are saved as they are.
- **No, every blob as it lies**: a save keeps every blob's position and
  speed; saves grow by roughly 4,000 blobs per full silo.

**Q10. What do you see: blobs or film?** (header `Look`)

- **Film on the blobs (Recommended)**: the blob is invisible physics; you
  see film flakes riding on it, like the belt beds today; one look for belts,
  falls and piles.
- **The blobs**: each litre is a visible lump wearing a film texture; clearer
  to read, less like film.

---

## 13. Sources

Web research by two research agents in this session; every claim above is
tagged. The page numbers of [1] are the report's own.

**Techniques, games, plant equipment** ([n])

1. Algoryx, AGX Terrain technical report — https://www.algoryx.se/download/agxTerrain_tech_report.pdf
2. AGX Terrain user manual — https://www.algoryx.se/documentation/complete/agx/tags/latest/doc/UserManual/source/agxTerrain.html
3. Vortex soil/particle paper — https://arxiv.org/html/2505.19330
4. CM Labs, soil in Vortex Studio — https://www.cm-labs.com/en/blog/rendering-even-more-realistic-soil-in-vortex-studio/
5. Macklin et al., Unified Particle Physics for Real-Time Applications — https://mmacklin.com/uppfrta_preprint.pdf
6. Gao et al., GPU MPM — https://pages.cs.wisc.edu/~sifakis/papers/GPU_MPM.pdf
7. Multi-GPU MPM — https://arxiv.org/abs/2111.00699
8. CPU MPM with upsampling — https://arxiv.org/abs/2308.01629
9. DEM cost figures — https://arxiv.org/html/2411.09678
10. Sumner, O'Brien, Hodgins, Animating Sand, Mud and Snow — https://publications.ri.cmu.edu/storage/publications/pub_files/pub4/sumner_robert_1999_1/sumner_robert_1999_1.pdf
11. Terrain thermal erosion on the GPU — https://aparis69.github.io/public_html/posts/terrain_erosion.html
12. Real-time water and sand — https://kuiwuchn.github.io/RTWaterAndSand.pdf
13. Survey citing Onoue-Nishita and Zhu-Yang — https://nccastaff.bournemouth.ac.uk/jmacey/MastersProject/MSc12/Papadimitriou/Master_Thesis_Report.pdf
14. Noita falling sand — https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation
15. Spintires / MudRunner mud — https://www.gamedeveloper.com/programming/mud-and-water-of-spintires-mudrunner
16. Gold Rush developer on terrain heights — https://steamcommunity.com/app/451340/discussions/0/3374780959383910176/
17. Gold Rush on Unity — https://steamcommunity.com/app/451340/discussions/0/1484358860952134178/
18. Hydroneer store page — https://store.steampowered.com/app/1106840/Hydroneer/
19. Hydroneer dirt duplication — https://steamcommunity.com/app/1106840/discussions/0/4120176169345819647/
20. Farming Simulator fill types — https://fswiki.xpmodder.com/wiki/Adding_Fill_Types
21. Farming Simulator tip collision — https://forum.giants-software.com/viewtopic.php?t=102577
22. Factorio belts — https://www.factorio.com/blog/post/fff-176
23. Satisfactory conveyor rendering — https://docs.ficsit.app/satisfactory-modding/latest/Development/Satisfactory/ConveyorRendering.html
28. TUM / Logistics Journal, screw conveyor capacity (DIN 15262 lineage) — https://d-nb.info/101080040X/34
29. Screw conveyor design (kg/h form, loading, inclination) — https://www.powderprocess.net/Equipments%20html/Screw_Conveyor_Design.html
30. KWS screw conveyor capacity — https://www.kwsmfg.com/engineering-guides/screw-conveyor/screw-conveyor-capacity/
32. KWS types of screw feeders — https://www.kwsmfg.com/engineering-guides/screw-conveyor/types-of-screw-feeders/
33. KWS feeder for plastic fluff (three screws, vertical walls) — https://www.kwsmfg.com/resources/problem-solvers/hopper-and-screw-feeder-for-recycling-plastic-fluff/
34. KWS mass-flow feeder for waste plastic — https://www.kwsmfg.com/resources/problem-solvers/mass-flow-screw-feeder-for-metering-waste-plastic/
36. PP/PE pelletizing line (bulk densities) — https://www.polyretecrecycling.com/news/best-pp-pe-pelletizing-line-for-recycled-flake-to-granule-process/
37. LDPE film densification — https://www.recyclemachine.net/ldpe-film-densification-by-screw-press/
38. LDPE recycling process (bridging) — https://www.geniusplas.com/en/article/LDPE-Recycling-Process.html
41. PET flake stacking angle — https://www.filabot.com/blogs/polymer-and-extrusions-blog/how-to-recycle-pet-bottles-into-3d-printer-filament-technical-dive
42. Belt discharge at the head pulley — https://ckit.co.za/secure/conveyor/papers/bionic-research-1/d-bri1-paper03.htm
43. Godot `StaticBody3D` — https://docs.godotengine.org/en/stable/classes/class_staticbody3d.html
45. Owen & Cleary 2009, DEM screw conveyor — https://www.sciencedirect.com/science/article/abs/pii/S0032591009001879

(The numbering keeps the research report's; unused entries are omitted.)

**Godot, engines, libraries** ([G n])

- G1. godot-rapier flavours and features — https://github.com/appsinacup/godot-rapier-physics/blob/v0.8.34/.github/workflows/windows_builds.yml ; …/v0.8.34/Cargo.toml and Cargo.lock ; …/v0.35.4/Cargo.toml ; https://github.com/dimforge/rapier/blob/v0.34.0/src/lib.rs ; https://godotengine.org/asset-library/asset/3085 ; https://github.com/appsinacup/godot-rapier-physics/releases
- G2. Rapier constant velocity sync — https://github.com/appsinacup/godot-rapier-physics/blob/v0.8.34/src/spaces/rapier_space_callbacks.rs ; …/src/bodies/rapier_body.rs ; issue https://github.com/appsinacup/godot-rapier-physics/issues/352
- G3. Engine benchmark by the godot-rapier maintainer — https://github.com/Ughuuu/benchmarks-repo (docs/REPORT-3D.md) ; https://forum.godotengine.org/t/physics-engine-comparison-rapier-vs-godot-vs-box2d-3d-vs-jolt/142786
- G4. Salva / Fluid3D — https://github.com/dimforge/salva ; https://github.com/appsinacup/godot-rapier-physics/blob/main/src/fluids/fluid_3d.rs ; …/issues/509
- G5. Jolt default for new projects — https://github.com/godotengine/godot/blob/master/doc/classes/ProjectSettings.xml ; https://godotengine.org/releases/4.6/ ; https://docs.godotengine.org/en/latest/tutorials/physics/using_jolt_physics.html
- G6. Jolt job system — https://github.com/godotengine/godot/blob/master/modules/jolt_physics/spaces/jolt_job_system.cpp
- G7. Jolt limits — https://github.com/godotengine/godot/blob/master/modules/jolt_physics/jolt_project_settings.cpp
- G8. Jolt surface velocity and performance — https://github.com/godotengine/godot/blob/master/modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp ; https://github.com/godot-jolt/godot-jolt/issues/331 ; https://jrouwe.nl/jolt/JoltPhysicsMulticoreScaling.pdf
- G9. `AnimatableBody3D` — https://github.com/godotengine/godot/blob/master/doc/classes/AnimatableBody3D.xml
- G10. `ConcavePolygonShape3D`, collision shapes — https://github.com/godotengine/godot/blob/master/doc/classes/ConcavePolygonShape3D.xml ; https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html
- G11. GPU particles — https://docs.godotengine.org/en/stable/tutorials/3d/particles/collision.html ; https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/particles_storage.h ; https://github.com/godotengine/godot/issues/83644
- G12. RenderingDevice and headless — https://github.com/godotengine/godot/blob/master/doc/classes/RenderingDevice.xml ; https://github.com/godotengine/godot/pull/98247 ; https://github.com/godotengine/godot/pull/100110
- G13. Compute examples — https://godotengine.org/asset-library/asset/5116 ; https://niceeffort.itch.io/boids-godot4-computeshader
- G14. Libraries and bindings — https://github.com/godotengine/godot-cpp ; https://github.com/godot-rust/gdext ; https://github.com/NVIDIA-Omniverse/PhysX ; https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/ParticleSystem.html ; https://github.com/NVIDIAGameWorks/FleX ; https://github.com/projectchrono/chrono ; https://github.com/CFDEMproject/LIGGGHTS-PUBLIC ; https://github.com/taichi-dev/taichi ; https://github.com/dimforge/wgsparkl
- G15. Terrain editing — https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html ; https://voxel-tools.readthedocs.io/en/latest/performance/
- G16. MultiMesh and the dummy renderer — https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html ; https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/dummy/storage/mesh_storage.cpp

---

## 14. Reproduce

The benchmark is NOT in this repo (the task was a design doc, no code). It
lives with the other non-repo CeDo material, in
`D:\cedo_archive\userdata\session_bulk_material_2026-09-26\`:

| path | what |
|---|---|
| `bench_common\bin_bench.gd` | the bin: trough, walls, closed tubes, three screws (kinematic or surface), n blobs, the discharge count and the timing |
| `bench_common\cpu_bench.gd` | `what=pbd` (GDScript particle solver), `what=hf` (heightfield relaxation), `what=rd` (is there a RenderingDevice) |
| `bench_rapier\`, `bench_jolt\` | two minimal projects; `bench_rapier\addons\godot-rapier3d\` holds the game's own `.gdextension` and Windows DLL (md5 `95998bd1…`, identical to the checkout's) |
| `run_dir.sh`, `run_matrix.sh`, `run_matrix2.sh` | the runs in §6, in order |
| `logs\summary_matrix.txt`, `logs\summary_matrix2.txt`, `logs\*.log` | every result line and each run's full log |

One run, from Git Bash:

    B=/d/cedo_archive/userdata/session_bulk_material_2026-09-26
    export APPDATA="$(cygpath -w $B/appdata)"
    cd $B/bench_jolt
    V:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --fixed-fps 60 \
        --script res://bin_bench.gd -- n=3000 screws=all rpm=20 settle=300 measure=1200 feed=1 kin=anim

`--fixed-fps 60` makes every frame one 1/60 s physics step, so the frame time
measured is the step's cost plus the script's, and the kg/h is in sim time.
The Rapier project needs one `--headless --import` first (it writes
`.godot/extension_list.cfg`; the import segfaults on exit after writing it, the
known headless teardown crash).
