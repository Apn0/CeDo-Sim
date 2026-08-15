extends RefCounted
class_name HmiScopes

## Scope table for the 12 distinct HMI panels documented by the operator.
##
## This is the single source of truth for which LineFlow nodes each physical
## HMI can see and control. Both the placement catalog (PlaceableCatalog.gd)
## and the runtime overlay (HmiOverlay.gd) read from here — there is exactly
## ONE list of scopes in the codebase. Do NOT duplicate this table elsewhere.
##
## ───────────────────────────────────────────────────────────────────────────
## SPEC (operator's whiteboard list, taken verbatim — do NOT invent extra HMIs):
##   1.  Shredder line 1                       — `hmi_shredder_l1`
##   2.  Shredder 1 line 3A / 3B               — `hmi_shredder1_l3ab`
##   3.  Shredder 2 line 3A / 3B               — `hmi_shredder2_l3ab`
##   4.  Shredder line 3C / 6                  — `hmi_shredder_l3c6`
##   5.  Sorting line 3A / 3B                  — `hmi_sorting_l3ab`
##   6.  Transportation belts 3A / 3B          — `hmi_transport_l3ab`
##   7.  Transportation belts 3C / 6           — `hmi_transport_l3c6`
##   8.  Washing line 1 / 3A / 3B / 3C / 6     — `hmi_washing_all`
##   9.  Extruder 1 / 3A / 3B / 3C / 6         — `hmi_extruder_all`
##   10. Water 3C / 6                          — `hmi_water_l3c6`
##   11. Water extruder 1 / 3A / 3B            — `hmi_water_extr_l1_3ab`
##   12. Indaver water                         — `hmi_indaver_water`
##
## ───────────────────────────────────────────────────────────────────────────
## SCOPE SHAPE — each entry is a Dictionary:
##   {
##     "label":     String      # human-readable title shown in the HMI header
##     "mesh":      String      # "hmi_panel" (stand) or "hmi_wall" — drives the mesh dispatcher
##     "color":     Color       # housing colour (lets operators tell panels apart visually)
##     "lines":     Array[String]   # line tags (1 / 3a / 3b / 3c / 6 / indaver) this HMI owns
##     "tokens":    Array[String]   # machine id-substring tokens the HMI can control
##     "web_screen": String     # OPTIONAL — filename of a Claude-Design
##                              # .dc.html export (docs/plant/hmi_screens_2026-07-26/)
##                              # to open as this panel's start screen in the
##                              # HmiWebOverlay (WebView) instead of the GDScript
##                              # touchscreen. Falls back to the touchscreen when
##                              # the WebView addon is unavailable (headless).
##   }
##
## A LineFlow node MATCHES the scope when:
##   ANY token in `tokens` is a substring of the node id
##   AND (no `lines` filter, OR a line tag appears in the node id, OR the node has
##        an explicit "line" attribute matching one of `lines`).
##
## The line/token approach keeps the scope SHALLOW — it does not require
## LineFlow to learn a `line` field on every node (today the macros encode line
## membership in the id suffix, e.g. `extruder_3a`, `shredder_1`). When that
## changes, `matches()` below is the ONE function to update.
##
## ───────────────────────────────────────────────────────────────────────────
## RETIRED (2026-08-15, operator order "remove unused/old HMI displays"):
##   The two pre-#165 cosmetic placeable ids `hmi_panel` / `hmi_wall` used to
##   map to a "generic" scope that saw EVERY machine. No such panel exists in
##   the plant, so the id, the scope and the fallback are all gone
##   (`PlaceableCatalog.RETIRED_IDS`). There is now exactly one rule:
##
##       an hmi_id that is not a key of SCOPES is a BUG, not a fallback.
##
##   `get_scope()` therefore returns an EMPTY dictionary on a miss and Hmi.gd
##   leaves such a panel inert (warning, no interaction) instead of quietly
##   handing the player control over the whole plant.

## ── MOUNT TABLE (placement) ─────────────────────────────────────────────────
## This file called itself "the single source of truth" while carrying no
## placement data at all: it mapped panels to the machines they CONTROL, never
## to where they STAND. That is why five rounds of "fix the HMI placement"
## changed nothing — every one of them touched screen content, because there was
## no placement code to change. Hmi.gd._ready() never set a transform; a panel
## sat wherever it was dropped.
##
## Each entry is:
##   {
##     "set":    bool     # false = NOT specified by the operator yet. Never guess.
##     "anchor": String   # placeable_id substring of the machine it mounts to
##     "face":   String   # "+x" / "-x" / "+z" / "-z" — which side of that machine
##     "offset": Vector3  # metres from the anchor's face centre (y = mount height)
##   }
##
## `set: false` is deliberate and load-bearing: an unset mount means the panel
## keeps whatever position it was placed at, and Hmi.gd logs it once. Inventing
## coordinates here is exactly the failure this table exists to end. Fill them
## from operator F10 markers via tools/hmi_mounts_from_markers.py.
const MOUNT_UNSET := {"set": false, "anchor": "", "face": "+x", "offset": Vector3.ZERO}

## hmi_id -> mount. Only ids present here are placed automatically.
const MOUNTS := {
	"hmi_shredder_l1":       MOUNT_UNSET,
	"hmi_shredder1_l3ab":    MOUNT_UNSET,
	"hmi_shredder2_l3ab":    MOUNT_UNSET,
	"hmi_shredder_l3c6":     MOUNT_UNSET,
	"hmi_sorting_l3ab":      MOUNT_UNSET,
	"hmi_transport_l3ab":    MOUNT_UNSET,
	"hmi_transport_l3c6":    MOUNT_UNSET,
	"hmi_washing_all":       MOUNT_UNSET,
	"hmi_extruder_all":      MOUNT_UNSET,
	"hmi_water_l3c6":        MOUNT_UNSET,
	"hmi_water_extr_l1_3ab": MOUNT_UNSET,
	"hmi_indaver_water":     MOUNT_UNSET,
}

## The mount for an hmi_id, or MOUNT_UNSET when the operator hasn't specified it.
static func get_mount(hmi_id: String) -> Dictionary:
	return MOUNTS.get(hmi_id, MOUNT_UNSET)

## How many of the 12 panels actually have operator-specified placement.
## Surfaced so "HMI placement is done" can never again be claimed without a count.
static func mounts_specified() -> int:
	var n := 0
	for k in MOUNTS:
		if bool((MOUNTS[k] as Dictionary).get("set", false)):
			n += 1
	return n


const SCOPES := {
	# ── 1. Shredder Line 1 ────────────────────────────────────────────────
	"hmi_shredder_l1": {
		"label":  "Shredder lijn 1",
		"mesh":   "hmi_panel",
		"color":  Color(0.30, 0.32, 0.36),
		"web_screen": "WEIMA Shredder Vulpeil Trechter.dc.html",
		"lines":  ["1"],
		"tokens": ["shredder"],
	},
	# ── 2. Shredder 1, Lines 3A/3B ────────────────────────────────────────
	"hmi_shredder1_l3ab": {
		"label":  "Shredder 1 lijn 3A/3B",
		"mesh":   "hmi_panel",
		"color":  Color(0.30, 0.32, 0.36),
		"web_screen": "WEIMA Shredder Vulpeil Trechter.dc.html",
		"lines":  ["3a", "3b"],
		"tokens": ["shredder_1", "shredder1"],
	},
	# ── 3. Shredder 2, Lines 3A/3B ────────────────────────────────────────
	# panel_type = "relay" — non-touchscreen 3-position key switch cabinet
	# (#207h). Hmi.gd branches on this field at open time to load
	# ShredderRelayPanel.gd instead of the touchscreen HmiOverlay.
	"hmi_shredder2_l3ab": {
		"label":  "Shredder 2 lijn 3A/3B",
		"mesh":   "hmi_panel",
		"color":  Color(0.30, 0.32, 0.36),
		"lines":  ["3a", "3b"],
		"tokens": ["shredder_2", "shredder2"],
		"panel_type": "relay",
	},
	# ── 4. Shredder Lines 3C/6 ────────────────────────────────────────────
	"hmi_shredder_l3c6": {
		"label":  "Shredder lijn 3C/6",
		"mesh":   "hmi_panel",
		"color":  Color(0.30, 0.32, 0.36),
		"web_screen": "WEIMA Shredder Vulpeil Trechter.dc.html",
		"lines":  ["3c", "6"],
		"tokens": ["shredder"],
	},
	# ── 5. Sorting Lines 3A/3B ────────────────────────────────────────────
	"hmi_sorting_l3ab": {
		"label":  "Sorteerlijn 3A/3B",
		"mesh":   "hmi_panel",
		"color":  Color(0.26, 0.38, 0.30),
		"web_screen": "Sorteerlijn Overzicht.dc.html",
		"lines":  ["3a", "3b"],
		"tokens": [
			"bunker", "sga", "ballistic", "wind_sifter",
			"titech", "tomra", "trilzeef", "metal_belt", "sorteer",
			"bale_feed", "opzetband", "invoer",
		],
	},
	# ── 6. Transportation belts 3A/3B ─────────────────────────────────────
	"hmi_transport_l3ab": {
		"label":  "Transportbanden 3A/3B",
		"mesh":   "hmi_panel",
		"color":  Color(0.36, 0.30, 0.18),
		# No web_screen: the operator's 33 designs contain no conveyor/transport
		# screen. Stays on the GDScript touchscreen rather than borrowing another
		# unit's artwork — a panel showing the wrong machine's screen is worse
		# than an honest generic one.
		"lines":  ["3a", "3b"],
		"tokens": [
			"conveyor", "transport_belt", "transportband",
			"opvoer", "inclined_belt", "belt_", "switch_belt",
			"bale_feed", "opzetband", "invoer",
		],
	},
	# ── 7. Transportation belts 3C/6 ──────────────────────────────────────
	"hmi_transport_l3c6": {
		"label":  "Transportbanden 3C/6",
		"mesh":   "hmi_panel",
		"color":  Color(0.36, 0.30, 0.18),
		# No web_screen — see hmi_transport_l3ab (no conveyor design exists).
		"lines":  ["3c", "6"],
		"tokens": [
			"conveyor", "transport_belt", "transportband",
			"belt_", "compactorband",
			"bale_feed", "opzetband", "invoer",
		],
	},
	# ── 8. Washing lines 1 / 3A / 3B / 3C / 6 (one HMI, all lines) ────────
	"hmi_washing_all": {
		"label":  "Waslijn (alle lijnen)",
		"mesh":   "hmi_panel",
		"color":  Color(0.16, 0.30, 0.40),
		# task#2 prototype: this panel opens the Claude-Design wash-line 3C
		# overview in the WebView overlay (live amps/status via LineFlow).
		"web_screen": "Waslijn 3C Overzicht.dc.html",
		"lines":  ["1", "3a", "3b", "3c", "6"],
		"tokens": [
			"prewash", "voorwas", "friction", "intensive", "wash", "was",
			"flotation", "rotation", "sink_float",
			"kufferath", "rafter", "sieve", "zeef",
			"dewater", "ontwaterzeef", "mech_dryer", "dryer", "droger", "centrifuge",
		],
	},
	# ── 9. Extruder 1 / 3A / 3B / 3C / 6 (one HMI, all lines) ─────────────
	"hmi_extruder_all": {
		"label":  "Extruder (alle lijnen)",
		"mesh":   "hmi_panel",
		"color":  Color(0.30, 0.16, 0.34),
		"web_screen": "EREMA Extruder Scherm 3C.dc.html",
		"lines":  ["1", "3a", "3b", "3c", "6"],
		"tokens": [
			"extruder", "intarema", "erema",
			"mengsilo", "mas_bak", "silo", "compactor",
			"heetafslag", "kopfilter", "vacuum_degas",
			"weegschaal", "voorraad_silo",
			"pelletizer", "die_face",
			"vacuum_unit", "vacuum_cabinet",
		],
	},
	# ── 10. Water 3C / 6 ──────────────────────────────────────────────────
	"hmi_water_l3c6": {
		"label":  "Water lijn 3C/6",
		"mesh":   "hmi_panel",
		"color":  Color(0.14, 0.34, 0.40),
		"web_screen": "Water Circuit Lijn 3C-6.dc.html",
		"lines":  ["3c", "6"],
		"tokens": [
			"water", "pomp", "pump", "tank",
			"eop", "zss", "ringleiding",
		],
	},
	# ── 11. Water extruder 1 / 3A / 3B ────────────────────────────────────
	"hmi_water_extr_l1_3ab": {
		"label":  "Water extruder 1/3A/3B",
		"mesh":   "hmi_panel",
		"color":  Color(0.14, 0.34, 0.40),
		# No web_screen: "Water Circuit Lijn 3C-6" is explicitly the 3C/6 loop,
		# and there is no 1/3A/3B water design. Assigning the 3C artwork here
		# would put the wrong line's circuit on the panel.
		"lines":  ["1", "3a", "3b"],
		"tokens": [
			"water", "pomp", "pump", "tank",
			"eop", "zss", "ringleiding",
		],
	},
	# ── 12. Indaver water (effluent treatment) ────────────────────────────
	"hmi_indaver_water": {
		"label":  "Indaver waterzuivering",
		"mesh":   "hmi_wall",
		"color":  Color(0.22, 0.40, 0.46),
		# No web_screen: no Indaver/effluent design exists in the 33.
		"lines":  ["indaver"],
		"tokens": ["indaver", "effluent", "water"],
	},
}

## Stable, deterministic catalog order — matches the operator's whiteboard list.
const ORDERED_IDS := [
	"hmi_shredder_l1",
	"hmi_shredder1_l3ab",
	"hmi_shredder2_l3ab",
	"hmi_shredder_l3c6",
	"hmi_sorting_l3ab",
	"hmi_transport_l3ab",
	"hmi_transport_l3c6",
	"hmi_washing_all",
	"hmi_extruder_all",
	"hmi_water_l3c6",
	"hmi_water_extr_l1_3ab",
	"hmi_indaver_water",
]

## True when `hmi_id` is one of the 12 documented panels.
static func has_scope(hmi_id: String) -> bool:
	return SCOPES.has(hmi_id)

## Look up the scope for a `hmi_id`. Returns an EMPTY dictionary on a miss.
##
## It used to return a see-everything "generic" scope. That fallback existed for
## the retired `hmi_panel` / `hmi_wall` props, and it was the dangerous kind of
## default: an unknown id silently became a master panel over the entire plant.
## Callers must now check `is_empty()` — Hmi.gd does, and leaves the panel inert.
static func get_scope(hmi_id: String) -> Dictionary:
	if SCOPES.has(hmi_id):
		return SCOPES[hmi_id]
	return {}

## True iff the given LineFlow node id (and optional explicit `line` attr) is
## inside the scope.
##   - Empty tokens list  → match everything (generic scope)
##   - Non-empty tokens   → at least one token must be a substring of `node_id`
##   - Empty lines list   → no line gate
##   - Non-empty lines    → either `node_line` matches OR a line tag appears as
##                          a recognisable suffix in `node_id` (e.g. `_3a`,
##                          `_l1`, `_line_3b`). The match is intentionally
##                          permissive because today's macros write line into
##                          the id rather than as a separate attribute.
static func matches(scope: Dictionary, node_id: String, node_line: String = "") -> bool:
	var tokens : Array = scope.get("tokens", [])
	if not tokens.is_empty():
		var hit := false
		for tk in tokens:
			if node_id.find(String(tk)) != -1:
				hit = true
				break
		if not hit:
			return false
	var lines : Array = scope.get("lines", [])
	if lines.is_empty():
		return true
	if node_line != "":
		for ln in lines:
			if String(ln).to_lower() == node_line.to_lower():
				return true
	# Fall back to id-suffix sniffing — `_3a`, `_3b`, `_3c`, `_l1`, `_line_6`, etc.
	var lid := node_id.to_lower()
	for ln in lines:
		var tag := String(ln).to_lower()
		# Direct line-tag substrings used by the existing macros.
		if lid.find("_" + tag) != -1: return true
		if lid.find("_l" + tag) != -1: return true
		if lid.find("line_" + tag) != -1: return true
		if lid.find("lijn_" + tag) != -1: return true
		if tag == "indaver" and lid.find("indaver") != -1: return true
	# Permissive fallback — if NO line tag appears anywhere in the id, treat
	# the machine as line-agnostic (shared/global) and let it through.  Stops
	# unscoped shared infra (e.g. air header) from disappearing entirely.
	var any_line_tag := false
	for tag in ["_1", "_3a", "_3b", "_3c", "_6", "indaver"]:
		if lid.find(tag) != -1:
			any_line_tag = true
			break
	return not any_line_tag

## Resolve a placed-HMI node's hmi_id from its meta, falling back to the
## placeable_id (the catalog stamps both, and they are equal for all 12 panels).
## Returns "" when neither meta is present — the caller treats that as unknown.
static func resolve_hmi_id(meta_owner: Object) -> String:
	if meta_owner == null:
		return ""
	if meta_owner.has_meta("hmi_id"):
		return String(meta_owner.get_meta("hmi_id"))
	if meta_owner.has_meta("placeable_id"):
		return String(meta_owner.get_meta("placeable_id"))
	return ""
