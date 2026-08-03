# godot-waterbox

WaterBox is an open-source addon for Godot 4.x that adds buoyancy and drag simulation for `RigidBody3D` objects inside a water volume.

This repository is the addon distribution repository. It contains the plugin, runtime scripts, built-in materials, and reusable prefabs required to install WaterBox in another Godot project.

## Requirements

- Godot 4.x
- a 3D project using `RigidBody3D` physics

Compatibility note:

- Tested on Godot `4.0.1`
- Expected to work with other Godot 4.x versions, but those versions have not been verified yet.

## Quick Start

1. Copy `addons/waterbox` into your Godot project.
2. In Godot, open `Project > Project Settings > Plugins`.
3. Enable `WaterBox`.
4. Add a `Node3D` to your scene and attach `res://addons/waterbox/scripts/water_box.gd`.
5. Add a child `Area3D` with a `CollisionShape3D` to define the water volume.

## Addon Installation (Your Project)

1. Copy the `addons/waterbox` directory into your Godot project.
2. In the editor, go to `Project > Project Settings > Plugins` and enable `WaterBox`.
3. Add a `Node3D` to your scene and attach this script:
	- `res://addons/waterbox/scripts/water_box.gd`

## WaterBox Configuration

Minimal node setup:

1. `WaterBox (Node3D)` with the `water_box.gd` script.
2. A child `Area3D` node.
3. Add a `CollisionShape3D` inside `Area3D` to define the water volume.

The `WaterBox` script automatically:
- detects `RigidBody3D` objects inside the `Area3D` volume
- applies buoyancy force
- applies damping through `water_drag`

Available exported parameters:
- `require_buoyancy_component`: requires `BuoyancyComponent` on floating objects
- `water_density`: fluid density (affects buoyancy force)
- `water_drag`: damping for linear and angular velocity

## BuoyancyComponent (More Accurate Floating)

Add `BuoyancyComponent` as a child of `RigidBody3D`:

1. Attach `res://addons/waterbox/scripts/buoyancy_component.gd`.
2. Add `Marker3D` children (buoyancy points), for example at object corners.
3. Set `use_buoyancy_points = true`.

If you do not add this component, `WaterBox` can still work in fallback mode (single buoyancy force), as long as `require_buoyancy_component` is disabled.

## Included Addon Content

- `addons/waterbox/scripts/water_box.gd`
- `addons/waterbox/scripts/buoyancy_component.gd`
- `addons/waterbox/prefabs/floating_cube.tscn`
- `addons/waterbox/prefabs/floating_capsule.tscn`
- `addons/waterbox/assets/materials/water.tres`
- `addons/waterbox/assets/materials/metal.tres`

## Repository Structure

```text
.
|-- addons/
|   `-- waterbox/        # addon
|-- docs/                # additional documentation
|-- CHANGELOG.md
|-- LICENSE
`-- README.md
```

## Recommended Repository Layout

- Keep the addon in `addons/waterbox` (Godot standard).
- Keep reusable addon assets inside `addons/waterbox/assets`.
- Keep addon documentation under `docs/addon`.

## Documentation

Available docs in `docs/`:
- `docs/addon/installation.md` (done)
- `docs/addon/api_reference.md` (done)

## Changelog

- Project change history:
	- `CHANGELOG.md`

## License

This project is distributed under the terms described in `LICENSE`.
