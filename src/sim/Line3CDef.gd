extends RefCounted
class_name Line3CDef

## Authoritative definition of LINE 3C, transcribed from the plant HMI overview
## (cedo SCADA, "Techical overview", 1687 kg/h). This is the single source of
## truth for the exact machine ORDER + their real codes/Dutch names, so the line
## is built the way it actually runs — and material can only enter at the head
## (L3C.1 Doseer Silo) and leave at the tail (Meltpump), never straight into the
## extruder (the #144 requirement).
##
## Waste baskets / scraper bins are intentionally OMITTED here (per the operator)
## — they hang off the separators and dryers and are placed separately.
##
## Each stage:
##   code  — the plant tag shown on the HMI (e.g. "L3C.4L")
##   name  — the Dutch machine name on the HMI
##   id    — the PlaceableCatalog model id used to build it
##   amps  — the live current shown on the HMI screenshot (for the label/where
##           a future per-machine load model can seed itself); 0 if not shown
##
## Numbering gaps (no L3C.2 / .7 / .8 / .17) are faithful to the HMI — those tags
## are sensors/valves/sumps not drawn as machines on the overview.
##
## ── EXTRUDER BACK-END (#175) ──────────────────────────────────────────────────
## The plant HMI OVERVIEW screen stops at the Meltpump; the pelletizing back-end
## (die head → hot-face cut → dewater → centrifuge → weigh → storage) lives on a
## separate page whose exact tags I don't have, so those stages carry RECONSTRUCTED
## short codes (Cband/Degas/Kop/Heet/Ontw/Centr/Weeg/Voorraad) built from the operator's
## own description of the real line, not invented HMI numbers:
##   • Extruder Silo → COMPACTORBAND (feed belt) → PCU (the EREMA cutter/COMPACTOR,
##     the upright pre-conditioning unit) → EXTRUDER (the screw — the labelled 3C HMI
##     shows it as its own instrumented unit: 138 rpm / 53% torque / 187 kW, fed by
##     the PCU at 112 °C / 169 kW). PCU and extruder are SEPARATE units on the HMI.
##   • melt path is an EREMA INTAREMA TVEplus (single-Laserfilter): FILTRATION
##     happens BEFORE DEGASSING — the patented TVEplus loop. The screw sends the
##     melt OUT through the LASERFILTER (big rotary DISC, 259 bar / 81% loaded — the
##     HMI concentric circle, NOT the PCU) and back in, THEN the vacuum DEGASSING
##     zone pulls moisture/volatiles off the cleaned melt, THEN the MELTPUMP (gear
##     pump, 25 bar) feeds the die head (~86 bar). On a single-Laserfilter TVEplus
##     there is NO separate die-head screen changer — the Laserfilter replaces it
##     (so the tail "Diekop" node is just the pelletizer die head, not a filter).
##     [Sourced from EREMA INTAREMA TVEplus docs — see #175 research report.]
##   • HEETAFSLAG (hot-face die cut): the granulate first forms here ("banks at the
##     heetafslag end"); the pellets are quenched by surface water only.
##   • that surface water is pulled straight back off by the ONTWATERZEEF (dewater
##     screen) + CENTRIFUGE spin-dryer → granulate leaves at ~0.1–0.5% moisture.
##   • WEEGSCHAAL (25 kg batch weigh) → VOORRAAD SILO (finished-granulate store =
##     the line's product sink). Amps are 0 (not on the overview screenshot).

const LINE_SPEED_KG_H : float = 1687.0

## Ordered stage list — head (intake) first, pelletized-granulate store last.
const STAGES : Array = [
	{"code": "L3C.1",   "name": "Doseer Silo",            "id": "doseersilo",      "amps": 0.0},
	{"code": "L3C.3",   "name": "Bezinkafscheider",       "id": "sink_float",      "amps": 0.0},
	{"code": "L3C.4L",  "name": "Frictiescheider L",      "id": "friction_sep",    "amps": 29.92},
	{"code": "L3C.4R",  "name": "Frictiescheider R",      "id": "friction_sep",    "amps": 29.92},
	{"code": "L3C.5L",  "name": "Transportschroef L",     "id": "transport_screw", "amps": 0.0},
	{"code": "L3C.5R",  "name": "Transportschroef R",     "id": "transport_screw", "amps": 0.0},
	{"code": "L3C.6",   "name": "Maalmolen",              "id": "mill",            "amps": 186.79},
	{"code": "L3C.9L",  "name": "Frictiescheider L",      "id": "friction_sep",    "amps": 28.03},
	{"code": "L3C.9R",  "name": "Frictiescheider R",      "id": "friction_sep",    "amps": 30.88},
	{"code": "L3C.10L", "name": "Transportschroef L",     "id": "transport_screw", "amps": 4.30},
	{"code": "L3C.10R", "name": "Transportschroef R",     "id": "transport_screw", "amps": 4.38},
	{"code": "L3C.11",  "name": "Flotatietank",           "id": "flotation_tank_wide",  "amps": 0.0},
	{"code": "L3C.12",  "name": "Transportschroef",       "id": "transport_screw", "amps": 2.52},
	{"code": "L3C.13",  "name": "Frictiescheider L-R",    "id": "friction_sep",    "amps": 24.68},
	{"code": "L3C.14L", "name": "Mechanische droger L",   "id": "mech_dryer",      "amps": 70.80},
	{"code": "L3C.14R", "name": "Mechanische droger R",   "id": "mech_dryer",      "amps": 63.51},
	{"code": "L3C.15",  "name": "Transportventilator",    "id": "blower",          "amps": 0.0},
	{"code": "L3C.16",  "name": "Plasmaq",                "id": "plasmaq",         "amps": 0.0},
	{"code": "L3C.18",  "name": "Extruder Silo",          "id": "silo",            "amps": 0.0},
	{"code": "L3C.19",  "name": "Rondmeng ventilator",    "id": "blower",          "amps": 12.76},
	# ── extruder back-end (reconstructed; see header) ─────────────────────────
	{"code": "Cband",   "name": "Compactorband",          "id": "compactorband",   "amps": 0.0},
	{"code": "PCU",     "name": "Compactor (PCU)",        "id": "compactor",       "amps": 0.0},
	{"code": "Extr",    "name": "Extruder",               "id": "extruder_screw",  "amps": 0.0},
	{"code": "Laser",   "name": "Laserfilter",            "id": "laser_filter",    "amps": 0.0},
	{"code": "Degas",   "name": "Ontgassing (vacuum)",    "id": "vacuum_degas",    "amps": 0.0},
	{"code": "Melt",    "name": "Meltpump",               "id": "melt_pump",       "amps": 0.0},
	{"code": "Kop",     "name": "Diekop (smeltkop)",      "id": "kopfilter",       "amps": 0.0},
	{"code": "Heet",    "name": "Heetafslag",             "id": "heetafslag",      "amps": 0.0},
	{"code": "Ontw",    "name": "Ontwaterzeef",           "id": "ontwaterzeef",    "amps": 0.0},
	{"code": "Centr",   "name": "Centrifuge",             "id": "centrifuge",      "amps": 0.0},
	{"code": "Weeg",    "name": "Weegschaal",             "id": "weegschaal",      "amps": 0.0},
	{"code": "Voorraad","name": "Voorraad Silo",          "id": "voorraad_silo",   "amps": 0.0},
]

## EXPLICIT flow topology (#1) — directed [from, to] edges. This is what makes the
## SPLITS real: Bezink feeds BOTH 4L and 4R (a left + right wash train running in
## parallel), and the two trains MERGE back at the Maalmolen / Flotatietank / dryers.
## LineFlow builds these edges for the Line 3C stages (splitting mass evenly down each
## branch and summing it at each merge); build-mode-placed objects + other lines still
## fall back to nearest-neighbour geometry linking. Single-stage runs are just A→B.
const LINKS : Array = [
	["L3C.1", "L3C.3"],
	["L3C.3", "L3C.4L"],  ["L3C.3", "L3C.4R"],          # SPLIT → L/R friction trains
	["L3C.4L", "L3C.5L"], ["L3C.4R", "L3C.5R"],
	["L3C.5L", "L3C.6"],  ["L3C.5R", "L3C.6"],          # MERGE at the Maalmolen
	["L3C.6", "L3C.9L"],  ["L3C.6", "L3C.9R"],          # SPLIT again
	["L3C.9L", "L3C.10L"],["L3C.9R", "L3C.10R"],
	["L3C.10L", "L3C.11"],["L3C.10R", "L3C.11"],        # MERGE at the Flotatietank
	["L3C.11", "L3C.12"],
	["L3C.12", "L3C.13"],
	["L3C.13", "L3C.14L"],["L3C.13", "L3C.14R"],        # SPLIT → L/R dryers
	["L3C.14L", "L3C.15"],["L3C.14R", "L3C.15"],        # MERGE
	["L3C.15", "L3C.16"],
	["L3C.16", "L3C.18"],
	["L3C.18", "L3C.19"],
	["L3C.19", "Cband"],  ["Cband", "PCU"],   ["PCU", "Extr"],   ["Extr", "Laser"],
	["Laser", "Degas"],   ["Degas", "Melt"],  ["Melt", "Kop"],   ["Kop", "Heet"],
	["Heet", "Ontw"],     ["Ontw", "Centr"],  ["Centr", "Weeg"], ["Weeg", "Voorraad"],
]

## Downstream stage codes that `code` feeds (1 for a normal run, 2 at a split point).
static func out_links(code: String) -> Array:
	var outs : Array = []
	for l in LINKS:
		if String(l[0]) == code:
			outs.append(String(l[1]))
	return outs

## The intake stage code — the ONLY place raw feedstock may enter the line.
static func intake_code() -> String:
	return STAGES[0]["code"]

## The terminal stage code (granulate out).
static func tail_code() -> String:
	return STAGES[STAGES.size() - 1]["code"]

## True if `code` is the line intake (L3C.1 Doseer Silo).
static func is_intake(code: String) -> bool:
	return code == intake_code()

## Index of a stage code in the chain, or -1.
static func order_of(code: String) -> int:
	for i in STAGES.size():
		if STAGES[i]["code"] == code:
			return i
	return -1
