#!/usr/bin/env python3
"""Write export_presets.cfg for the Steam build (Windows 64-bit).

Why an explicit file list and not "Export all resources":
101 imported assets under assets/ have been cache-only since the 2026-09-21
wipe (docs/audit/assets_loss_and_restore_2026-09-21.md): the source file is
gone, while `<file>.import` and `.godot/imported/` still hold the import, so the
game runs. The editor's filesystem only lists files that exist on disk, so
"all resources" drops every one of them, among them the factory shell
`CeDo_factory_solid.obj`, `CeDo_building.obj` and the Merlo P40. A path listed
explicitly ("selected resources") is exported through its `.import` file
whether the source exists or not.

The list is every file the engine loads as a resource: scripts, scenes,
resources, JSON, GDExtensions and anything with a `.import` beside it. It
leaves out what the game never loads (tests, tools, docs, the reference
photos, the raw photogrammetry). The web HMI's pages are not resources; the
include filter adds them as plain files.

Run from the project root (or pass it):  python tools/steam/gen_export_preset.py [root]
It rewrites export_presets.cfg, so run it before every Steam export.
"""
import os
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")

# Loaded by the engine without an importer.
NATIVE_EXT = {"gd", "tscn", "tres", "res", "scn", "json", "gdshader",
              "gdshaderinc", "gdextension"}

# Path prefixes (relative, "/"-separated) the game never loads.
EXCLUDE_PREFIXES = (
    "src/tests/",                 # suites, probes, benches
    "tools/",                     # offline tools
    "docs/",                      # plant corpus; the web HMI pages come back via include_filter
    "assets/reference_photos/",   # photos, cited in comments only
    "assets/building_3d_raw/",    # raw photogrammetry; only the BuildingAlign dev scene loads it
    "src/scenes/world/BuildingAlign.",
    "line_connection_audit.",     # an audit CSV that Godot imported as translations
)

# Plain files the WebView reads through res:// (HmiWebOverlay.SCREENS_DIR).
INCLUDE_FILTER = ("docs/plant/hmi_screens_2026-07-26/*.html, "
                  "docs/plant/hmi_screens_2026-07-26/*.js, "
                  "docs/plant/hmi_screens_2026-07-26/mimic/*.json")


def excluded(rel):
    return rel.startswith(EXCLUDE_PREFIXES)


def collect():
    paths = set()
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        rel_dir = "" if rel_dir == "." else rel_dir + "/"
        # Godot skips hidden directories and any directory holding .gdignore.
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".")
                             and not os.path.exists(os.path.join(dirpath, d, ".gdignore")))
        for f in filenames:
            rel = rel_dir + f
            if excluded(rel):
                continue
            if f.endswith(".import"):
                # The source path, whether or not the source still exists.
                paths.add(rel[:-len(".import")])
            elif f.rsplit(".", 1)[-1].lower() in NATIVE_EXT:
                paths.add(rel)
    return sorted("res://" + p for p in paths)


def main():
    files = collect()
    quoted = ", ".join('"%s"' % p.replace('"', '\\"') for p in files)
    cfg = f'''[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="resources"
export_files=PackedStringArray({quoted})
include_filter="{INCLUDE_FILTER}"
exclude_filter=""
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=true
application/icon=""
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name="CeDo Simulator"
application/file_description="CeDo Simulator"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
'''
    out = os.path.join(ROOT, "export_presets.cfg")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(cfg)
    missing = sum(1 for p in files if not os.path.exists(os.path.join(ROOT, p[len("res://"):])))
    print(f"wrote {out}: {len(files)} files, {missing} of them cache-only (no source on disk)")


if __name__ == "__main__":
    main()
