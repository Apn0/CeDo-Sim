# OSM/PDOK/AHN5/3DBAG Terrain Baker

A standalone Python tool that fetches four open Dutch geographic datasources for
a lat/lon bounding box and bakes them into a unified asset set that the CeDo
Simulator (`MainWorld.gd`) can load at runtime.

The baker produces:
- `assets/terrain/terrain.glb` — AHN5 ground heightmesh + BGT polygons
  (roads/sidewalks/water/grass) baked on top with material slots + OSM road
  ribbons (asphalt).
- `assets/terrain/buildings.glb` — 3D BAG LoD 1.2 extrusions for every building
  in the bbox **except** the CeDo factory itself (operator already has
  `assets/models/CeDo_factory_solid.obj`).
- `assets/terrain/osm_furniture.json` — point features (trees, signs, bollards,
  benches, lamps, power poles) and OSM road polylines with width hints and
  highway-class tags.

The Godot runtime loader is `src/scenes/world/OSMTerrainLoader.gd`, which
spawns the meshes and JSON furniture into MainWorld at startup.

---

## Install

The baker uses standard-library Python 3 for everything **except** four
network/geo libs:

```
pip install requests pyproj rasterio trimesh cjio numpy
```

| Package    | Why                                                          |
|------------|--------------------------------------------------------------|
| `requests` | HTTP POST (Overpass) + GET (PDOK WFS, AHN5 ATOM, 3DBAG API)  |
| `pyproj`   | EPSG:28992 ↔ EPSG:4326 reprojection for PDOK data            |
| `rasterio` | Range-read AHN5 GeoTIFFs from PDOK without full downloads    |
| `trimesh`  | Build the `.glb` outputs from per-feature triangle soups     |
| `cjio`     | CityJSON IO for 3D BAG LoD 1.2 tiles (optional — only used if installed) |
| `numpy`    | Heightmap grid sampling                                      |

Each library is optional in the sense that the baker prints a clear
"`pip install <pkg>`" hint and skips that step if the import fails, so you can
develop incrementally. For a production bake you need all six.

---

## Run

From the project root:

```
python tools/osm_terrain_baker/bake.py <south> <west> <north> <east>
```

Example for the ~1 km square around CeDo Krijtstraat, Sittard-Geleen:

```
python tools/osm_terrain_baker/bake.py 50.9650 5.8120 50.9740 5.8270
```

If you omit the four bbox args, the baker uses the CeDo default
(`DEFAULT_BBOX = (50.9650, 5.8120, 50.9740, 5.8270)`).

Optional flags:

| Flag              | Effect                                                |
|-------------------|-------------------------------------------------------|
| `--skip-overpass` | Skip the OSM Overpass fetch                           |
| `--skip-bgt`      | Skip the PDOK BGT WFS fetch                           |
| `--skip-ahn`      | Skip the AHN5 elevation fetch (terrain stays flat)    |
| `--skip-3dbag`    | Skip the 3DBAG download (no buildings.glb output)     |
| `--grid-n N`      | Heightmesh sample grid resolution (default 257)       |

---

## Endpoints (exact)

| Source        | Endpoint                                                              |
|---------------|-----------------------------------------------------------------------|
| Overpass      | `https://overpass-api.de/api/interpreter` (POST, `application/x-www-form-urlencoded`) |
| PDOK BGT WFS  | `https://service.pdok.nl/lv/bgt/wfs/v1_0`                             |
| PDOK AHN5     | `https://service.pdok.nl/rws/ahn/atom/dtm_05m.xml`                    |
| 3D BAG        | `https://3dbag.nl/api/tile?bbox=...` → `/api/v1/tile/<id>/lod12.city.json` |

### Overpass QL (verbatim — the operator's spec)

The baker substitutes `{bbox}` with `south,west,north,east` (Overpass
convention):

```
[out:json][timeout:60];
(
  way["highway"]({bbox});
  node["highway"="traffic_signals"]({bbox});
  node["highway"="street_lamp"]({bbox});
  node["highway"="stop"]({bbox});
  node["traffic_sign"]({bbox});
  node["barrier"="bollard"]({bbox});
  way["barrier"="fence"]({bbox});
  way["barrier"="wall"]({bbox});
  node["amenity"="bench"]({bbox});
  node["amenity"="waste_basket"]({bbox});
  node["natural"="tree"]({bbox});
  way["natural"="tree_row"]({bbox});
  node["man_made"="utility_pole"]({bbox});
);
out body;
>;
out skel qt;
```

### PDOK BGT WFS layers requested

| typeName                      | Purpose in scene                |
|-------------------------------|---------------------------------|
| `bgt:wegdeel`                 | Road surfaces (asphalt)         |
| `bgt:ondersteunendwegdeel`    | Sidewalks, shoulders            |
| `bgt:waterdeel`               | Canals, ponds                   |
| `bgt:begroeidterreindeel`     | Grass strips, vegetated areas   |

Per-layer GetFeature parameters (sent as `?key=value`):

```
service=WFS
version=2.0.0
request=GetFeature
typeNames=<layer>
outputFormat=application/json
srsName=EPSG:28992
bbox=<rd_min_x>,<rd_min_y>,<rd_max_x>,<rd_max_y>,EPSG:28992
count=5000
```

### AHN5 DTM 0.5 m/px

The ATOM index lists per-sheet feeds; each sheet feed lists GeoTIFFs. The
baker uses `rasterio` HTTP range reads so the heightmap grid only pulls the
windows it samples (not the full ~100 MB GeoTIFFs).

### 3D BAG LoD 1.2

Bbox-based tile index, then one CityJSON download per overlapping tile, parsed
with `cjio` (or a stdlib JSON fallback). Building footprints whose centroid
falls within `FACTORY_EXCLUSION_RADIUS_M = 80 m` of the bbox centre are
**skipped** — that's the CeDo factory the operator already has as
`assets/models/CeDo_factory_solid.obj`.

---

## Coordinate convention

All output geometry is in a local right-handed metre frame whose origin sits at
the bbox centre. Axes match the project's canonical convention
(`forward = -Z`, `right = +X`, `up = +Y`):

```
x = (lon - origin_lon) * 111320 * cos(origin_lat)   # east = +X
z = -(lat - origin_lat) * 111320                     # north = -Z
```

PDOK polygons are transformed EPSG:28992 → WGS84 (via `pyproj`) → local metres
so they share the same frame as the OSM/Overpass output.

---

## Expected output

After a successful bake the `assets/terrain/` directory looks like:

```
assets/terrain/
├── terrain.glb         (~5–20 MB, depending on grid-n)
├── buildings.glb       (~1–5 MB)
└── osm_furniture.json  (~50–500 KB)
```

`OSMTerrainLoader.gd` loads these at world startup if present; if any file is
missing the loader logs a single warning and falls back to MainWorld's
hardcoded ground/roads/neighbour-building emitters.

---

## Operator approvals required before re-baking

Per the **"No build without docs"** rule, before re-running the baker against
a NEW bbox or different data layers the operator must confirm:

1. The bbox lat/lon (current default centred on Krijtstraat).
2. The Overpass QL above — any extra OSM keys to fetch.
3. Any additional PDOK BGT layers beyond the four above.
4. The factory-exclusion radius (currently 80 m).

The defaults match the CeDo plant as deployed; no extra approval needed for
the same-bbox re-runs.
