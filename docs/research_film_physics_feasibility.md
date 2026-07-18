# Film-physics tooling — feasibility read (2026-07-15)

Research for the [film-physics R&D track](../../.claude/...) — cyclone clog → film ejection → aerodynamic dispersal (leaf-blower / HP nozzle) → settle into piles → buoyancy in water. Target engine: **Godot 4.6.3-stable, GDScript**. Verdicts are GO / NO-GO with sources.

## TL;DR — recommended stack (all built into Godot 4.6, zero native deps)
| Need | Use | NOT |
|---|---|---|
| Rigidbody physics (hero flakes, machines) | **Jolt** — already the 4.6 default, no plugin | Rapier backend swap |
| Airborne dispersal (leaf-blower / nozzle) | **GPUParticles3D + Attractor3D + SDF collision** (visual cloud, 100k+) | thousands of real rigidbodies |
| Gameplay-meaningful "hero" film pieces | a *small* pool of real Jolt RigidBody3D | GPU particles (can't be picked up/counted) |
| Settled piles (accumulation) | **MultiMeshInstance3D + growing heightfield** | godot_voxel; N rigidbodies |
| In-water buoyancy + drag | **custom GDScript Archimedes** (extend existing `FilmFlakeField`) | "Waterbox" (doesn't exist); Rapier fluid |

The winning shape is **hybrid**: GPU particles for the *visual* mass of blown film, a handful of Jolt rigidbodies for pieces the player actually interacts with, MultiMesh for piles, custom buoyancy in water. No new native/compiled dependencies.

---

## 1. Godot Rapier Physics — ⚠️ NO-GO as a backend swap (revisit only for true fluid)
- **Real + active:** `appsinacup/godot-rapier-physics`, ~949★, 97 releases, **v0.8.39 released 2026-07-07**. API tags for 4.4/4.5/**4.6**/4.7 → 4.6-compatible.
- **Fluids:** yes — Salva integration, `Fluid2D`/`Fluid3D` nodes (SPH). SIMD + parallelism (parallel build **not on web**).
- **The catch:** it's a **whole-project physics-backend REPLACEMENT** (Advanced Settings → Physics Engine → Rapier3D) — you'd drop Jolt (the 4.6 default) for it. It's **pre-1.0 (0.8.x)**; **2D is "pretty stable" but 3D is "still missing things" / under development.** Caveats: double builds need manual compile; asymmetric collisions unsupported.
- **Verdict:** betting the entire 3D project on a pre-1.0 3D backend to get one feature (SPH fluid) is not worth it. And SPH fluid for "film in water" is overkill vs cheap custom buoyancy. **Skip unless a future feature genuinely needs real fluid dynamics.**

## 2. "Waterbox" buoyancy addon — ❌ does not exist
- No asset named "Waterbox" in the Godot Asset Library. Likely a misremembered name.
- **Real options:** `FloatableBody` (Asset #2345 — buoyancy in pure GDScript, Godot 4); custom GDScript **Archimedes** buoyancy (submerged-volume × fluid-density → upward force + linear drag) — cheap, full control, scales to many bodies; Rapier Salva fluid (heavy, see §1). `Waterways` = river-mesh generation, **not** buoyancy physics.
- **Verdict:** use **custom GDScript buoyancy/drag**, which is what the existing `FilmFlakeField` sink/float already approximates. No addon needed.

## 3. Voxel / volumetric accumulation — ⚠️ godot_voxel is overkill; use MultiMesh
- `Zylann/godot_voxel` runs on 4.6 (GDExtension for official builds ≥4.4.1, or a custom module build), but it's a **terrain engine** (infinite chunked worlds, LOD/Transvoxel) — heavyweight and the wrong shape for "piles of film." The GDExtension edition is newer/less-tested.
- **Better 4.6-native path:** **MultiMeshInstance3D** (thousands of settled-flake instances in **one draw call**, no per-instance physics) for the look, plus a simple **growing heightfield/mesh** for the pile volume that the leaf-blower deforms. This is "treat the accumulator as a volume, not N bodies" — exactly the operator's intent — without a compiled module.
- **Verdict:** **NO-GO on godot_voxel**; **GO on MultiMesh + heightfield.**

## Bonus — the two alternatives that actually matter
- **Jolt Physics = the DEFAULT 3D engine in Godot 4.6** (replaced GodotPhysics3D; built-in, no plugin). Benchmarks vs GodotPhysics: ~1.4× @1k bodies, ~2.6× @2k, ~4.7× @5k, raycast ~3×. **No fluids / cloth / destruction; SoftBody experimental.** → This is the rigidbody backend to use, for free.
- **GPUParticles3D:** renders 100k+ particles on the GPU; **GPUParticlesAttractor3D** (Box/Sphere) = ready-made wind/blower forces; collision via SDF/box/sphere (approximate). **Limitation:** GPU particles live on the GPU — they **can't be individually picked up, counted, or touch the gameplay physics world.** Perfect for the *visual* blown-film cloud, useless for pieces the player must interact with (→ use a few Jolt rigidbodies for those).

## Sources
- Rapier: [github.com/appsinacup/godot-rapier-physics](https://github.com/appsinacup/godot-rapier-physics), [godot.rapier.rs](https://godot.rapier.rs/)
- Jolt in 4.6: [StraySpark migration guide](https://www.strayspark.studio/blog/godot-46-jolt-physics-migration-guide), [Godot docs — Using Jolt Physics](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html), [GameFromScratch](https://gamefromscratch.com/godot-4-4-gets-native-jolt-physics-support/)
- Buoyancy: [FloatableBody (Asset #2345)](https://godotengine.org/asset-library/asset/2345)
- Particles: [Godot docs — 3D particle collisions](https://docs.godotengine.org/en/stable/tutorials/3d/particles/collision.html), [GPUParticlesAttractor3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticlesattractor3d.html)
- Voxel: [github.com/Zylann/godot_voxel](https://github.com/Zylann/godot_voxel)
