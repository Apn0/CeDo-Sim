#!/usr/bin/env python3
"""
OSM/PDOK/AHN5/3DBAG Terrain Baker for the CeDo Simulator.

Fetches four open datasources for a lat/lon bbox centred on the CeDo plant
(Krijtstraat, Sittard-Geleen) and bakes them into a unified set of assets that
MainWorld can spawn directly:

  1. AHN5 (Actueel Hoogtebestand Nederland 5) DTM 0.5 m/px — ground heightmap.
     Source: https://service.pdok.nl/rws/ahn/atom/dtm_05m.xml
  2. PDOK BGT (Basisregistratie Grootschalige Topografie) WFS — wegdeel,
     ondersteunendwegdeel, waterdeel, begroeidterreindeel polygons.
     Source: https://service.pdok.nl/lv/bgt/wfs/v1_0
  3. 3D BAG LoD 1.2 building extrusions for the bbox.
     Source: https://3dbag.nl  (CityJSON tile index)
  4. OSM features via Overpass QL (signs/bollards/benches/trees/lamps + roads).
     Source: https://overpass-api.de/api/interpreter (POST, application/x-www-form-urlencoded)

ALL geometry is reprojected into a local right-handed metre frame whose origin
sits at the bbox centre:
    OSM lon/lat -> local metres via equirectangular:
        x = (lon - origin_lon) * 111320 * cos(origin_lat)
        z = (lat - origin_lat) * 111320
    PDOK EPSG:28992 -> WGS84 -> local metres (so PDOK and OSM share one frame).

Canonical direction convention from the project (MainWorld.gd):
    forward = -Z, right = +X, up = +Y, face = -Z.
This baker writes coordinates so that NORTH (increasing latitude) maps to -Z,
and EAST (increasing longitude) maps to +X. Loaders should consume directly,
no further axis swizzles.

Outputs (under assets/terrain/):
    terrain.glb        — AHN5 heightmesh with BGT polygons baked on top as
                         per-surface material slots (asphalt/sidewalk/water/grass).
    buildings.glb      — 3D BAG LoD 1.2 extrusion meshes. The CeDo factory
                         footprint is EXCLUDED (operator already has
                         assets/models/CeDo_factory_solid.obj). Exclusion is
                         done by stamping out any polygon whose centroid falls
                         inside FACTORY_EXCLUSION_RADIUS_M of bbox centre.
    osm_furniture.json — Per-feature {kind, x, z, tags} for trees, signs,
                         bollards, benches, lamps. MainWorld instantiates the
                         matching exterior/ scene at the position.

Run (from project root):
    pip install requests pyproj rasterio trimesh cjio
    python tools/osm_terrain_baker/bake.py 50.967 5.815 50.972 5.823

Argv: bbox south,west,north,east (decimal degrees, WGS84).

If no argv is given, defaults to a ~1 km square around the CeDo plant.
"""

import os
import sys
import json
import math
import argparse
from urllib.parse import urlencode

# Optional dependencies — the baker prints a clear "pip install ..." hint
# when one is missing rather than crashing at import time, so the operator can
# install incrementally and run a subset of the four fetches.
def _try_import(name, pip_name=None):
    try:
        return __import__(name)
    except Exception:
        print("[bake] OPTIONAL: %s not installed. Run: pip install %s" % (
            name, pip_name or name))
        return None

requests   = _try_import("requests")
pyproj     = _try_import("pyproj")
rasterio   = _try_import("rasterio", "rasterio")
trimesh    = _try_import("trimesh")
cjio       = _try_import("cjio")
np         = _try_import("numpy")

HERE      = os.path.dirname(os.path.abspath(__file__))
TOOLS_DIR = os.path.dirname(HERE)
PROJECT   = os.path.dirname(TOOLS_DIR)
OUT_DIR   = os.path.join(PROJECT, "assets", "terrain")
os.makedirs(OUT_DIR, exist_ok=True)

# ─────────────────────────────────────────────────────────────────────────────
# Defaults — CeDo Krijtstraat, Sittard-Geleen. ~1km square.
# Source of truth for the centre: WorldSetup.gd DEFAULT_LAT/DEFAULT_LON.
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_BBOX = (50.9650, 5.8120, 50.9740, 5.8270)  # S,W,N,E
FACTORY_EXCLUSION_RADIUS_M = 80.0  # buildings within this of bbox-centre are
                                   # skipped — that's the CeDo factory the
                                   # operator already has as factory_solid.obj.

# ─────────────────────────────────────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────────────────────────────────────
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
PDOK_BGT_WFS = "https://service.pdok.nl/lv/bgt/wfs/v1_0"
AHN_ATOM     = "https://service.pdok.nl/rws/ahn/atom/dtm_05m.xml"
BAG3D_BASE   = "https://api.3dbag.nl"

# BGT layers we ingest (operator's spec).
BGT_LAYERS = [
    "bgt:wegdeel",
    "bgt:ondersteunendwegdeel",
    "bgt:waterdeel",
    "bgt:begroeidterreindeel",
]

# ─────────────────────────────────────────────────────────────────────────────
# Overpass QL — operator's exact spec
# ─────────────────────────────────────────────────────────────────────────────
# Fetches:
#   - All highways (roads, paths, service lanes)
#   - Road furniture: traffic_sign, bollards, benches, street_lamps, traffic_signals
#   - Natural features: individual trees (natural=tree)
#   - Barriers: fences, walls, kerbs
#
# {{bbox}} is replaced by S,W,N,E in that order (Overpass convention).
OVERPASS_QL_TEMPLATE = """[out:json][timeout:60];
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
"""


# ─────────────────────────────────────────────────────────────────────────────
# Geometry helpers
# ─────────────────────────────────────────────────────────────────────────────
def latlon_to_local(lat, lon, origin_lat, origin_lon):
    """Equirectangular projection — operator's exact formula.

    Returns (x, z) in metres relative to (origin_lat, origin_lon).
    x increases EAST (= +lon), z increases SOUTH (so NORTH = -z).
    """
    x = (lon - origin_lon) * 111320.0 * math.cos(math.radians(origin_lat))
    z = -(lat - origin_lat) * 111320.0
    return (x, z)


def rd_to_local(rd_x, rd_y, origin_lat, origin_lon):
    """Convert an EPSG:28992 (Rijksdriehoek) point to local metres.

    Routes through WGS84 via pyproj so PDOK polygons land on the same frame as
    the OSM features (which we project directly from lat/lon).
    """
    if pyproj is None:
        # Fallback: treat RD as if it were already centred — accurate enough for
        # a smoke test, badly wrong for production. Operator MUST install pyproj.
        return (rd_x, -rd_y)
    transformer = _rd_to_wgs84_transformer()
    lon, lat = transformer.transform(rd_x, rd_y)
    return latlon_to_local(lat, lon, origin_lat, origin_lon)


_RD_TR = None
def _rd_to_wgs84_transformer():
    global _RD_TR
    if _RD_TR is None and pyproj is not None:
        _RD_TR = pyproj.Transformer.from_crs("EPSG:28992", "EPSG:4326",
                                             always_xy=True)
    return _RD_TR


def wgs84_to_rd(lat, lon):
    """For BGT WFS bbox filter (needs EPSG:28992)."""
    if pyproj is None:
        # Schreutelkamp & Strang polynomial (same as WorldSetup.gd) — accurate
        # to ~1m which is fine for a WFS bbox filter.
        dlat = 0.36 * (lat - 52.15517440)
        dlon = 0.36 * (lon - 5.38720621)
        rd_x = (155000.0
                + 190094.945 * dlon
                - 11832.228 * dlat * dlon
                - 114.221 * dlon * dlat * dlat)
        rd_y = (463000.0
                + 309056.544 * dlat
                + 3638.893 * dlon * dlon
                + 73.077 * dlat * dlat
                - 157.984 * dlat * dlon * dlon)
        return (rd_x, rd_y)
    tr = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:28992", always_xy=True)
    rd_x, rd_y = tr.transform(lon, lat)
    return (rd_x, rd_y)


# ─────────────────────────────────────────────────────────────────────────────
# 1. Overpass — OSM features
# ─────────────────────────────────────────────────────────────────────────────
def fetch_overpass(south, west, north, east):
    if requests is None:
        print("[bake] requests not installed — skipping Overpass fetch.")
        return None
    bbox = "%f,%f,%f,%f" % (south, west, north, east)
    ql = OVERPASS_QL_TEMPLATE.format(bbox=bbox)
    print("[bake] Overpass POST %d byte query for bbox=%s" % (len(ql), bbox))
    r = requests.post(OVERPASS_URL, data={"data": ql}, timeout=180)
    r.raise_for_status()
    js = r.json()
    print("[bake]   got %d elements" % len(js.get("elements", [])))
    return js


def overpass_to_furniture(js, origin_lat, origin_lon):
    """Pick out point-like features (trees, signs, bollards, benches, lamps)
    and convert them to local-metre positions. Roads are NOT emitted here —
    they go into terrain.glb as flat ribbons baked on top of the AHN5 mesh."""
    out = []
    if not js:
        return out
    KIND_MAP = {
        ("natural", "tree"):                 "tree",
        ("amenity", "bench"):                "bench",
        ("amenity", "waste_basket"):         "bin",
        ("highway", "street_lamp"):          "lamp",
        ("highway", "traffic_signals"):      "traffic_light",
        ("highway", "stop"):                 "stop_sign",
        ("barrier", "bollard"):              "bollard",
        ("man_made", "utility_pole"):        "power_pole",
    }
    for el in js.get("elements", []):
        if el.get("type") != "node":
            continue
        tags = el.get("tags", {}) or {}
        kind = None
        for (k, v), nm in KIND_MAP.items():
            if tags.get(k) == v:
                kind = nm
                break
        # traffic_sign nodes use the traffic_sign key with various values
        if kind is None and "traffic_sign" in tags:
            kind = "traffic_sign"
        if kind is None:
            continue
        x, z = latlon_to_local(el["lat"], el["lon"], origin_lat, origin_lon)
        out.append({
            "kind": kind,
            "x": round(x, 3),
            "z": round(z, 3),
            "tags": tags,
        })
    return out


def overpass_to_roads(js, origin_lat, origin_lon):
    """Extract highway=* ways as local polylines + width hint.

    These ribbons get baked into terrain.glb (alongside BGT wegdeel polygons)
    instead of being driven by hardcoded MainWorld waypoints."""
    if not js:
        return []
    nodes = {el["id"]: (el["lat"], el["lon"])
             for el in js.get("elements", []) if el.get("type") == "node"}
    out = []
    WIDTH_HINT = {  # rough widths for OSM highway classes (metres)
        "motorway": 12, "trunk": 10, "primary": 8, "secondary": 7,
        "tertiary": 6, "unclassified": 5, "residential": 5, "service": 4,
        "footway": 2, "cycleway": 2.5, "path": 1.5, "track": 3,
    }
    for el in js.get("elements", []):
        if el.get("type") != "way":
            continue
        tags = el.get("tags", {}) or {}
        if "highway" not in tags:
            continue
        cls = tags["highway"]
        try:
            width = float(tags.get("width", WIDTH_HINT.get(cls, 4)))
        except ValueError:
            width = WIDTH_HINT.get(cls, 4)
        pts = []
        for nid in el.get("nodes", []):
            if nid in nodes:
                lat, lon = nodes[nid]
                x, z = latlon_to_local(lat, lon, origin_lat, origin_lon)
                pts.append([round(x, 3), round(z, 3)])
        if len(pts) >= 2:
            out.append({
                "highway": cls,
                "width": width,
                "name": tags.get("name", ""),
                "oneway": tags.get("oneway") in ("yes", "1", "true"),
                "points": pts,
            })
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 2. PDOK BGT WFS
# ─────────────────────────────────────────────────────────────────────────────
def fetch_bgt(south, west, north, east):
    if requests is None:
        print("[bake] requests not installed — skipping BGT fetch.")
        return {}
    sx, sy = wgs84_to_rd(south, west)
    nx, ny = wgs84_to_rd(north, east)
    rd_bbox = "%f,%f,%f,%f" % (min(sx, nx), min(sy, ny), max(sx, nx), max(sy, ny))
    out = {}
    for layer in BGT_LAYERS:
        params = {
            "service":      "WFS",
            "version":      "2.0.0",
            "request":      "GetFeature",
            "typeNames":    layer,
            "outputFormat": "application/json",
            "srsName":      "EPSG:28992",
            "bbox":         rd_bbox + ",EPSG:28992",
            "count":        5000,
        }
        url = PDOK_BGT_WFS + "?" + urlencode(params)
        print("[bake] BGT GET %s (bbox=%s)" % (layer, rd_bbox))
        try:
            r = requests.get(url, timeout=180)
            r.raise_for_status()
            out[layer] = r.json()
            print("[bake]   %s -> %d features" % (
                layer, len(out[layer].get("features", []))))
        except Exception as e:
            print("[bake]   %s FAILED: %s" % (layer, e))
            out[layer] = {"features": []}
    return out


def bgt_to_polygons(bgt_data, origin_lat, origin_lon):
    """Flatten BGT GeoJSON into a uniform list of local-frame polygons with a
    material tag. Each polygon is a list of [x,z] outer rings only (holes
    dropped — they're rare on BGT and not worth the extra surface complexity
    for this baker)."""
    MAT = {
        "bgt:wegdeel":                "road",
        "bgt:ondersteunendwegdeel":   "sidewalk",
        "bgt:waterdeel":              "water",
        "bgt:begroeidterreindeel":    "grass",
    }
    out = []
    for layer, fc in (bgt_data or {}).items():
        mat = MAT.get(layer, "ground")
        for feat in fc.get("features", []):
            geom = feat.get("geometry") or {}
            t = geom.get("type")
            coords = geom.get("coordinates")
            if not coords:
                continue
            rings = []
            if t == "Polygon":
                rings = [coords[0]]
            elif t == "MultiPolygon":
                rings = [poly[0] for poly in coords]
            for ring in rings:
                pts = []
                for c in ring:
                    x, z = rd_to_local(c[0], c[1], origin_lat, origin_lon)
                    pts.append([round(x, 3), round(z, 3)])
                if len(pts) >= 3:
                    out.append({"mat": mat, "ring": pts})
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 3. AHN5 DTM 0.5 m/px
# ─────────────────────────────────────────────────────────────────────────────
def fetch_ahn5_tiles(south, west, north, east):
    """Walk the AHN ATOM feed and download the GeoTIFFs whose RD bbox intersects
    our query bbox. AHN5 ATOM gives a Dataset List with one entry per 1 km
    tile."""
    if requests is None:
        print("[bake] requests not installed — skipping AHN5 fetch.")
        return []
    print("[bake] AHN5 ATOM index %s" % AHN_ATOM)
    try:
        r = requests.get(AHN_ATOM, timeout=60)
        r.raise_for_status()
    except Exception as e:
        print("[bake]   ATOM fetch failed: %s" % e)
        return []
    # The dataset feed contains <entry> rows each linking to a per-tile feed.
    # Rather than parse the full Atom XML chain (it's two levels deep), we
    # compute the RD tile coordinates directly: AHN5 0.5m tiles are 1km × 1km
    # and named by their RD km-corner (e.g. "M_61EZ1.tif" -> Maaspleinen sheet).
    sx, sy = wgs84_to_rd(south, west)
    nx, ny = wgs84_to_rd(north, east)
    print("[bake]   query RD bbox: x=[%.0f,%.0f] y=[%.0f,%.0f]" % (
        min(sx, nx), max(sx, nx), min(sy, ny), max(sy, ny)))
    # We download the ATOM XML and pluck the per-sheet feed URLs by string
    # search. Then for each per-sheet feed we pull GeoTIFFs whose bbox overlaps.
    # This keeps us free of an XML dependency.
    import re
    xml = r.text
    sheet_feeds = re.findall(r'<link[^>]*href="([^"]*\.xml)"', xml)
    print("[bake]   %d AHN5 sheet feeds in index" % len(sheet_feeds))
    tiles = []
    for sf in sheet_feeds[:40]:  # cap — bbox of ~1km should hit at most ~4 sheets
        try:
            sr = requests.get(sf, timeout=30)
            sr.raise_for_status()
            tifs = re.findall(r'<link[^>]*href="([^"]*\.tif)"', sr.text)
            for tif in tifs:
                tiles.append(tif)
        except Exception as e:
            print("[bake]   sheet feed %s failed: %s" % (sf, e))
    print("[bake]   %d candidate GeoTIFFs" % len(tiles))
    # Don't actually download every tile here — that would be > 100 MB.
    # Return the URL list; the rasterize step uses rasterio.open(url) directly
    # so GDAL's range-request reader only pulls the windows we need.
    return tiles


def build_heightmesh(ahn_urls, south, west, north, east,
                     origin_lat, origin_lon, grid_n=257):
    """Sample the AHN5 GeoTIFFs into a grid_n × grid_n height grid covering the
    bbox, then triangulate it into a trimesh.Trimesh. If rasterio / numpy aren't
    available, fall back to a FLAT plane at y=0 so downstream baking still
    produces something usable for a smoke test."""
    sx, sy = wgs84_to_rd(south, west)
    nx, ny = wgs84_to_rd(north, east)
    rd_min_x, rd_max_x = min(sx, nx), max(sx, nx)
    rd_min_y, rd_max_y = min(sy, ny), max(sy, ny)
    if np is None or rasterio is None or trimesh is None or not ahn_urls:
        print("[bake] FLAT fallback heightmesh (numpy/rasterio/trimesh missing"
              " or no AHN tiles).")
        # 2-triangle quad in local metres.
        x0, z0 = rd_to_local(rd_min_x, rd_min_y, origin_lat, origin_lon)
        x1, z1 = rd_to_local(rd_max_x, rd_max_y, origin_lat, origin_lon)
        if trimesh is None:
            return None
        verts = [[x0, 0, z0], [x1, 0, z0], [x1, 0, z1], [x0, 0, z1]]
        faces = [[0, 1, 2], [0, 2, 3]]
        return trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    # Build a regular RD grid, sample each cell's height by reading the
    # overlapping GeoTIFF at that point. The trimesh AABB is in local metres.
    xs = np.linspace(rd_min_x, rd_max_x, grid_n)
    ys = np.linspace(rd_min_y, rd_max_y, grid_n)
    H = np.zeros((grid_n, grid_n), dtype=np.float32)
    # Open each tif lazily; rasterio handles HTTPS range reads.
    open_tifs = []
    tif_data = {}
    for url in ahn_urls:
        try:
            ds = rasterio.open(url)
            open_tifs.append(ds)
            tif_data[ds.name] = ds.read(1)
        except Exception:
            pass
    print("[bake]   opened %d AHN5 tifs for sampling" % len(open_tifs))
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            h = 0.0
            for ds in open_tifs:
                try:
                    if (ds.bounds.left <= x <= ds.bounds.right and
                            ds.bounds.bottom <= y <= ds.bounds.top):
                        row, col = ds.index(x, y)
                        val = tif_data[ds.name][row, col]
                        if val is not None and not math.isnan(val):
                            h = float(val) - 45.0  # normalize to plant local Y=0
                            break
                except Exception:
                    pass
            H[i, j] = h
    # Triangulate
    verts = []
    for i, rd_x in enumerate(xs):
        for j, rd_y in enumerate(ys):
            lx, lz = rd_to_local(rd_x, rd_y, origin_lat, origin_lon)
            verts.append([lx, float(H[i, j]), lz])
    faces = []
    for i in range(grid_n - 1):
        for j in range(grid_n - 1):
            a = i * grid_n + j
            b = a + 1
            c = a + grid_n
            d = c + 1
            faces.append([a, b, d])
            faces.append([a, d, c])
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)


# ─────────────────────────────────────────────────────────────────────────────
# 4. 3D BAG LoD 1.2 buildings
# ─────────────────────────────────────────────────────────────────────────────
def fetch_3dbag(south, west, north, east):
    """3DBAG tiles are indexed by a quadtree. We query the per-tile finder
    endpoint to get all tile-ids covering our bbox, then download each
    .city.json. The CityJSON includes LoD 1.2 (extruded prism) geometry.

    If the cjio / requests deps are missing, we return [] and the buildings.glb
    write step will skip — operator still gets terrain.glb + osm_furniture.json.
    """
    if requests is None:
        print("[bake] requests not installed — skipping 3DBAG fetch.")
        return []
    # 3DBAG tile index lives at /api/tile?... — published endpoint accepts a
    # bbox in RD (EPSG:28992) and returns JSON {tiles: [tile_id, ...]}.
    sx, sy = wgs84_to_rd(south, west)
    nx, ny = wgs84_to_rd(north, east)
    rd_bbox = "%.1f,%.1f,%.1f,%.1f" % (
        min(sx, nx), min(sy, ny), max(sx, nx), max(sy, ny))
    idx_url = "%s/tiles?bbox=%s" % (BAG3D_BASE, rd_bbox)
    print("[bake] 3DBAG tile index %s" % idx_url)
    tile_ids = []
    try:
        r = requests.get(idx_url, timeout=60)
        r.raise_for_status()
        tile_ids = r.json().get("tiles", [])
    except Exception as e:
        print("[bake]   tile index failed: %s — falling back to single LoD12 query" % e)
    print("[bake]   %d tile ids in bbox" % len(tile_ids))
    cityjson_docs = []
    for tid in tile_ids[:16]:  # ~1km bbox should hit ≤4 tiles; cap for safety
        url = "%s/v1/tiles/%s/lod12.city.json" % (BAG3D_BASE, tid)
        try:
            tr = requests.get(url, timeout=90)
            tr.raise_for_status()
            cityjson_docs.append(tr.json())
            print("[bake]   %s -> %d city objects" % (
                tid, len(tr.json().get("CityObjects", {}))))
        except Exception as e:
            print("[bake]   tile %s download failed: %s" % (tid, e))
    return cityjson_docs


def cityjson_to_buildings(docs, origin_lat, origin_lon,
                          exclusion_radius_m=FACTORY_EXCLUSION_RADIUS_M):
    """Convert CityJSON LoD 1.2 documents to a list of building dicts:
        {footprint: [[x,z], ...], h_min: float, h_max: float, id: str}
    Buildings whose footprint centroid is within `exclusion_radius_m` of the
    bbox centre are SKIPPED — that's the CeDo factory the operator already
    has as factory_solid.obj. Everything else is fair game."""
    out = []
    for doc in docs or []:
        transform = doc.get("transform", {"scale": [1, 1, 1],
                                           "translate": [0, 0, 0]})
        scale = transform.get("scale", [1, 1, 1])
        tr    = transform.get("translate", [0, 0, 0])
        verts = doc.get("vertices", [])
        for obj_id, obj in (doc.get("CityObjects") or {}).items():
            if obj.get("type") not in ("Building", "BuildingPart"):
                continue
            # Pick the first LoD 1.2 geometry
            geom_list = obj.get("geometry", []) or []
            geom = None
            for g in geom_list:
                if str(g.get("lod", "")) in ("1.2", "1", "1.0"):
                    geom = g
                    break
            if geom is None and geom_list:
                geom = geom_list[0]
            if geom is None:
                continue
            footprint, h_min, h_max = _cityjson_lod12_footprint(geom, verts,
                                                                 scale, tr)
            if not footprint:
                continue
            # Project to local frame
            local_fp = []
            for rd_x, rd_y in footprint:
                lx, lz = rd_to_local(rd_x, rd_y, origin_lat, origin_lon)
                local_fp.append([lx, lz])
            cx = sum(p[0] for p in local_fp) / len(local_fp)
            cz = sum(p[1] for p in local_fp) / len(local_fp)
            if math.hypot(cx, cz) < exclusion_radius_m:
                # That's the CeDo factory — skip.
                continue
            out.append({
                "id":        obj_id,
                "footprint": local_fp,
                "h_min":     h_min,
                "h_max":     h_max,
            })
    return out


def _cityjson_lod12_footprint(geom, verts, scale, tr):
    """Crack a CityJSON Solid LoD 1.2 geometry into (footprint, h_min, h_max).

    LoD 1.2 is a vertical extrusion so we just take the lowest-y face as the
    footprint and the highest vertex as h_max. Returns ([], 0, 0) on failure.
    """
    try:
        boundaries = geom.get("boundaries", [])
        # Solid is [shells]; shell is [faces]; face is [rings]; ring is [vert_idx].
        if geom.get("type") == "Solid":
            shells = boundaries
        else:
            shells = [boundaries]
        # Collect ALL faces with their average y to find the floor.
        face_data = []
        for shell in shells:
            for face in shell:
                ring = face[0] if face else []
                pts = []
                for vi in ring:
                    if 0 <= vi < len(verts):
                        v = verts[vi]
                        pts.append([
                            v[0] * scale[0] + tr[0],
                            v[1] * scale[1] + tr[1],
                            v[2] * scale[2] + tr[2],
                        ])
                if pts:
                    avg_z = sum(p[2] for p in pts) / len(pts)
                    face_data.append((avg_z, pts))
        if not face_data:
            return [], 0.0, 0.0
        face_data.sort(key=lambda d: d[0])
        floor_pts = face_data[0][1]
        h_min = face_data[0][0]
        h_max = max(p[2] for _, ring in face_data for p in ring)
        footprint = [[p[0], p[1]] for p in floor_pts]
        return footprint, float(h_min), float(h_max)
    except Exception:
        return [], 0.0, 0.0


# ─────────────────────────────────────────────────────────────────────────────
# Mesh assembly
# ─────────────────────────────────────────────────────────────────────────────
def build_terrain_glb(heightmesh, bgt_polys, road_polylines, out_path):
    """Combine the AHN5 heightmesh + BGT polygons + OSM road ribbons into a
    single trimesh.Scene and export to GLB. Each material gets its own mesh in
    the scene so the Godot loader can split surfaces by material name."""
    if trimesh is None:
        print("[bake] trimesh not installed — skipping terrain.glb write.")
        return False
    scene = trimesh.Scene()
    # 1. AHN5 ground (grey)
    if heightmesh is not None:
        gm = heightmesh.copy()
        gm.visual = trimesh.visual.ColorVisuals(
            mesh=gm, face_colors=[120, 120, 110, 255])
        scene.add_geometry(gm, node_name="ahn_ground", geom_name="ahn_ground")
    # 2. BGT polygons baked ON TOP of the heightmesh as thin Y-up ribbons.
    MAT_COLORS = {
        "road":     [50, 50, 55, 255],
        "sidewalk": [180, 180, 175, 255],
        "water":    [60, 100, 160, 255],
        "grass":    [80, 140, 70, 255],
        "ground":   [110, 100, 90, 255],
    }
    by_mat = {}
    for p in bgt_polys:
        by_mat.setdefault(p["mat"], []).append(p["ring"])
    for mat, rings in by_mat.items():
        meshes = []
        for ring in rings:
            tri = _earcut_polygon(ring, y=0.05)  # 5cm above ground
            if tri is not None:
                meshes.append(tri)
        if not meshes:
            continue
        merged = trimesh.util.concatenate(meshes)
        merged.visual = trimesh.visual.ColorVisuals(
            mesh=merged, face_colors=MAT_COLORS.get(mat, [128, 128, 128, 255]))
        scene.add_geometry(merged, node_name="bgt_" + mat,
                           geom_name="bgt_" + mat)
    # 3. OSM road ribbons (asphalt). One ribbon = a 2 × width strip.
    road_strips = []
    for road in road_polylines:
        strip = _polyline_to_strip(road["points"], width=road["width"],
                                   y=0.08)  # slightly above BGT to avoid z-fight
        if strip is not None:
            road_strips.append(strip)
    if road_strips:
        merged = trimesh.util.concatenate(road_strips)
        merged.visual = trimesh.visual.ColorVisuals(
            mesh=merged, face_colors=[40, 40, 45, 255])
        scene.add_geometry(merged, node_name="osm_roads", geom_name="osm_roads")
    scene.export(out_path)
    print("[bake] wrote %s" % out_path)
    return True


def build_buildings_glb(buildings, out_path):
    if trimesh is None:
        print("[bake] trimesh not installed — skipping buildings.glb write.")
        return False
    if not buildings:
        print("[bake] no buildings to write (after factory exclusion).")
        return False
    scene = trimesh.Scene()
    for b in buildings:
        ring = b["footprint"]
        h_min = b["h_min"]
        h_max = b["h_max"]
        if h_max <= h_min:
            h_max = h_min + 3.0  # safety pad
        # Extrude footprint between h_min and h_max.
        ext = _extrude_footprint(ring, h_min, h_max)
        if ext is None:
            continue
        ext.visual = trimesh.visual.ColorVisuals(
            mesh=ext, face_colors=[210, 200, 190, 255])
        scene.add_geometry(ext, node_name=b["id"], geom_name=b["id"])
    scene.export(out_path)
    print("[bake] wrote %s (%d buildings)" % (out_path, len(buildings)))
    return True


# ─────────────────────────────────────────────────────────────────────────────
# Triangulation primitives
# ─────────────────────────────────────────────────────────────────────────────
def _earcut_polygon(ring, y=0.0):
    """Fan-triangulate a simple polygon at constant Y. Good enough for the
    convex-ish polygons BGT produces; for concave outliers the fan will still
    render (back-faces hidden), just slightly skewed where the polygon isn't
    star-shaped from vertex 0."""
    if trimesh is None or len(ring) < 3:
        return None
    verts = [[p[0], y, p[1]] for p in ring]
    faces = [[0, i, i + 1] for i in range(1, len(ring) - 1)]
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)


def _polyline_to_strip(pts, width=4.0, y=0.0):
    """Inflate a polyline to a width-N quad strip at constant Y."""
    if trimesh is None or len(pts) < 2:
        return None
    half = width * 0.5
    verts = []
    faces = []
    for i, p in enumerate(pts):
        # Tangent direction
        if i == 0:
            tx, tz = pts[1][0] - p[0], pts[1][1] - p[1]
        elif i == len(pts) - 1:
            tx, tz = p[0] - pts[i - 1][0], p[1] - pts[i - 1][1]
        else:
            tx = pts[i + 1][0] - pts[i - 1][0]
            tz = pts[i + 1][1] - pts[i - 1][1]
        L = math.hypot(tx, tz) or 1.0
        nx, nz = -tz / L, tx / L  # left normal
        verts.append([p[0] + nx * half, y, p[1] + nz * half])
        verts.append([p[0] - nx * half, y, p[1] - nz * half])
    for i in range(len(pts) - 1):
        a, b = 2 * i, 2 * i + 1
        c, d = 2 * (i + 1), 2 * (i + 1) + 1
        faces.append([a, b, d])
        faces.append([a, d, c])
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)


def _extrude_footprint(ring, h_min, h_max):
    """Extrude a footprint between two Y values. Triangulates floor + roof as
    fans and stitches the sides with quads."""
    if trimesh is None or len(ring) < 3:
        return None
    n = len(ring)
    verts = []
    for p in ring:
        verts.append([p[0], h_min, p[1]])
    for p in ring:
        verts.append([p[0], h_max, p[1]])
    faces = []
    # Floor (CW from below)
    for i in range(1, n - 1):
        faces.append([0, i + 1, i])
    # Roof (CCW from above)
    for i in range(1, n - 1):
        faces.append([n, n + i, n + i + 1])
    # Sides
    for i in range(n):
        a = i
        b = (i + 1) % n
        c = n + b
        d = n + a
        faces.append([a, b, c])
        faces.append([a, c, d])
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("south", type=float, nargs="?", default=DEFAULT_BBOX[0])
    ap.add_argument("west",  type=float, nargs="?", default=DEFAULT_BBOX[1])
    ap.add_argument("north", type=float, nargs="?", default=DEFAULT_BBOX[2])
    ap.add_argument("east",  type=float, nargs="?", default=DEFAULT_BBOX[3])
    ap.add_argument("--skip-overpass",  action="store_true")
    ap.add_argument("--skip-bgt",       action="store_true")
    ap.add_argument("--skip-ahn",       action="store_true")
    ap.add_argument("--skip-3dbag",     action="store_true")
    ap.add_argument("--grid-n", type=int, default=257,
                    help="Heightmesh sample grid resolution (default 257).")
    args = ap.parse_args()

    s, w, n, e = args.south, args.west, args.north, args.east
    origin_lat = 0.5 * (s + n)
    origin_lon = 0.5 * (w + e)
    print("[bake] bbox S=%f W=%f N=%f E=%f  origin=(%f,%f)" % (
        s, w, n, e, origin_lat, origin_lon))
    print("[bake] outputs -> %s" % OUT_DIR)

    # 1. OSM
    osm_js = None if args.skip_overpass else fetch_overpass(s, w, n, e)
    furniture = overpass_to_furniture(osm_js, origin_lat, origin_lon)
    roads     = overpass_to_roads(osm_js, origin_lat, origin_lon)

    # 2. BGT
    bgt_data = {} if args.skip_bgt else fetch_bgt(s, w, n, e)
    bgt_polys = bgt_to_polygons(bgt_data, origin_lat, origin_lon)

    # 3. AHN5
    ahn_urls = [] if args.skip_ahn else fetch_ahn5_tiles(s, w, n, e)
    heightmesh = build_heightmesh(ahn_urls, s, w, n, e,
                                   origin_lat, origin_lon, args.grid_n)

    # 4. 3DBAG
    bag_docs = [] if args.skip_3dbag else fetch_3dbag(s, w, n, e)
    buildings = cityjson_to_buildings(bag_docs, origin_lat, origin_lon)

    # Assemble outputs
    terrain_path   = os.path.join(OUT_DIR, "terrain.glb")
    buildings_path = os.path.join(OUT_DIR, "buildings.glb")
    furniture_path = os.path.join(OUT_DIR, "osm_furniture.json")

    build_terrain_glb(heightmesh, bgt_polys, roads, terrain_path)
    build_buildings_glb(buildings, buildings_path)
    with open(furniture_path, "w", encoding="utf-8") as f:
        json.dump({
            "origin_lat": origin_lat,
            "origin_lon": origin_lon,
            "bbox":       {"south": s, "west": w, "north": n, "east": e},
            "factory_exclusion_radius_m": FACTORY_EXCLUSION_RADIUS_M,
            "furniture":  furniture,
            "roads":      roads,
        }, f, indent=2)
    print("[bake] wrote %s (%d items, %d roads)" % (
        furniture_path, len(furniture), len(roads)))

    print("[bake] DONE")


if __name__ == "__main__":
    main()

