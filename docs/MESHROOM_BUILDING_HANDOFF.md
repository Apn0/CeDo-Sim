# Meshroom Building Mesh — Integration Handoff

## What exists

- **Raw mesh**: `assets/building_3d_raw/texturedMesh.obj` (394 MB, 5.3M faces, 9 texture atlases)
- **Backup**: `D:\CeDo_meshroom_raw_backup\` (untouched copy)
- **Test scene**: `src/scenes/world/RawMeshTest.tscn` (loads the raw OBJ with sky+sun)
- **Source images**: `V:\_Claude\CeDo_assets\building_360\production\` (383 × 4K PNGs)
- **Meshroom project**: `V:\_Claude\CeDo_assets\building_360\cedo_building.mg` (re-openable in GUI)

## Mesh coordinate system

- Bounding box center: `(0.03, -0.12, 0.49)` — sits on the main hall roof
- Dimensions: `21.5 × 6.2 × 14.7` Blender units (NOT meters — Meshroom has no real-world scale)
- Real building footprint: ~180m × 140m → scale factor ≈ **8.4×** to get to meters
- Z-up in Blender; Godot is Y-up (OBJ importer handles this)

## Before using in the simulator

1. **Delete floating islands** — sky/horizon fragments around the edges; keep the connected ground+building mass
2. **Scale to real-world** — multiply by ~8.4 or measure a known dimension (parking lot width, silo diameter) and calibrate
3. **Decimate** — 5.3M faces → ~100-200K for real-time; use Blender Decimate modifier (ratio ~0.03) or Quadriflow remesh
4. **Bake textures** — after decimation, bake the original textures onto the simplified mesh (Blender bake, cage projection)
5. **Export as glTF** — Godot's preferred format; embeds textures, imports as a single scene

## Known limitations

- **Flat walls**: Google Earth screenshots don't produce real stereo parallax. Vertical surfaces (walls, silos) are reconstructed as near-flat textured surfaces, not volumetric geometry. The mesh is essentially a textured terrain relief, not a true 3D scan.
- **No interior**: only exterior surfaces visible from orbit altitudes
- **Texture seams**: visible where orbit rings overlap at different tilt angles
- **The white tents** (NE side): reconstructed but blobby; these are temporary structures not in BAG/PDOK

## How to position in the existing world

The ExteriorManager already places the building shell. This mesh would either:
- **Replace** the procedural shell entirely (if quality is good enough after cleanup)
- **Sit underneath** as a ground-truth texture reference while keeping the procedural shell for collision/interaction geometry
- **Provide roof/ground textures** baked from the photogrammetry onto the existing shell UVs

## Meshroom re-run

If more images are needed, the Chrome profile at `scratchpad/chrome_profile` has "Opschriften" label mode persisted. The production script is `scratchpad/production_run.py` — it resumes automatically (skips existing files). Add more POIs to the ellipse or reduce `D` for tighter orbits.
