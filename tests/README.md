# Headless tests

Seven suites:

| File | Mode | Covers | Runs on |
|---|---|---|---|
| `BaleComplianceTest.gd` | `--script` SceneTree | Bale `RigidBody3D` conversion, freeze-on-place, mass, collision shrink (10% give on X/Z), `PhysicsMaterial`, wire/clamp metadata, `delivered`-meta feed gate | Any Godot 4.x |
| `BaleSheetsTest.gd` | `--script` SceneTree | Sheet decomposition (count + thickness sum ≈ bale length), 3 wires × 4 segments, `wires_cut` meta lifecycle, per-origin clamp force metadata | Any Godot 4.x |
| `WireFixAndCameraTest.gd` | `--script` SceneTree | Wire visuals (thickness, corner overlap, knot), CameraRig mode cycle, F4-tap-vs-hold disambiguation, scroll-zoom clamping | Any Godot 4.x |
| `OperatorLifecycleTest.gd` | `--script` SceneTree | Vehicle exit teleport + F4 random-view regression: unattended vehicle rigs spawn INACTIVE, activate/deactivate manage the first-person camera, mode cycle updates camera position synchronously | Any Godot 4.x |
| `VehicleDriveTest.gd` | `--script` SceneTree | Drive-feel regression: no in-place rotation, steering scales with speed, reverse flips steer direction | Any Godot 4.x |
| `SettingsParseTest.gd` | `--script` SceneTree | `SettingsManager` parses; every action in the project's `[input]` map has a friendly label AND belongs to a group | Any Godot 4.x |
| `VehicleBaleTest.tscn` + `.gd` | Full scene | Vehicle scenes load, hydraulic node paths resolve, `_try_grab` / `_release` lifecycle | Godot 4.6 (needs to parse the project's 4.6 `.tscn` files) |

## Run all

```bat
tests\run_tests.bat
```

## Notes

The vehicle scene test needs Godot 4.6 — the project's `.tscn` files use 4.6's resource format. On a Godot 4.2 install the six script-mode tests pass (262 assertions total); the scene test boots Godot but the 4.6 vehicle scenes don't parse. The script-mode tests are what's verified in CI.
