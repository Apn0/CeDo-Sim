extends RefCounted
class_name L3CUnitScreenSpecs

## VERBATIM TRANSCRIPTION of the operator's per-unit HMI screens for wash line
## 3C.  Data only — the layout engine is src/scenes/hud/scopes/L3CUnitScreen.gd.
##
## SOURCE
## ------
## docs/plant/hmi_screens_2026-07-26/*.dc.html, the operator's own export.  Every
## string below was extracted from the HTML mechanically and is cited by its
## line number in the file it came from.  Nothing here is typed from memory and
## nothing is translated.
##
## THE RULE THAT MATTERS MOST
## --------------------------
## DO NOT NORMALISE THESE STRINGS.  The real screens disagree with each other,
## and the disagreements are the plant, not typos to be cleaned up:
##
##     L3C.1   "Safety zone was"       L3C.4  "Safety zone wash"
##     L3C.1   "Safety zone voorwas"   L3C.4  "Safety zone prewash"
##     L3C.3   "Peddelwalzen"          L3C.11 "Peddelwals 1,2,3,4"
##     L3C.1   "Uittrekschroef midden" (lower-case m, beside two capitalised)
##     L3C.14  "Doseersluis Links"     L3C.14 "Doseersluis Rechts"
##
## An operator reads these to find a specific device on a specific screen.
## src/tests/test_l3c_unit_screens.gd fails if a "tidy-up" collapses them.
##
## STRUCTURE IS NOT UNIFORM EITHER
## -------------------------------
## The motor cards do not all carry the same rows.  On L3C.14:
##     Mechanische Droger   Gewenst: Loopbewaking                     Reëel: Stroom
##     Reinigingsschraper   Gewenst: Aanlooptijd, Uitlooptijd         Reëel: Aanlooptijd, Uitlooptijd, Stroom
##     Doseersluis *        Gewenst: Aanlooptijd, Uitlooptijd, Loopbewaking
##                                                                    Reëel: Aanlooptijd, Uitlooptijd, Stroom
## so each card carries its own row lists rather than inheriting a template.
##
## WHICH CARD SHOWS THE MACHINE CURRENT
## -------------------------------------
## `stroom_from_machine` names the ONE card that renders the unit's machine-level
## `amps`.  This is not a fresh judgement: TagMap already maps
## `<unit>/softstarterdroger1/stroom` to MACHINE_FIELD `amps` (TagMap.gd:723), and
## `stroom_tag_motor` records the motor segment so the screen reports the same
## verbatim tag TagMap does.  Every other card renders "--", because the sim has
## no per-motor state at all (TagMap.gd:722).

## The three header chips, verbatim.  Identical on both L3C.14 screens; the CITE
## differs between them (:19 vs :21), which is why the cite lives per screen.
const HEADER_CHIPS : Array = [
	{"label": "Status Lijn 3C"},
	{"label": "Status was"},
	{"label": "Status Silo"},
]

const SCREENS : Dictionary = {
	# ---------------------------------------------------------------------
	# L3C.14 Mechanische Droger LINKS
	# docs/plant/hmi_screens_2026-07-26/Waslijn 3C L3C.14 Mech Droger Links.dc.html
	#
	# Chosen as the first ported unit screen because it is the sharpest proof
	# that machines are addressed individually now: this unit and its Rechts
	# sibling are the same machine TYPE (mech_dryer) and BOTH read 0.00 A until
	# 2026-07-29. They now read their own calibrated currents, 70.80 A and
	# 63.51 A (Line3CDef.gd:77-78, measured by test_line3c_identity).
	# ---------------------------------------------------------------------
	"L3C.14L": {
		"code": "L3C.14L",
		"tag_unit": "14l",
		"title": "L3C.14 Mechanische Droger Links",       # mockup :28
		"amps_fmt": "int",                                 # photo: L3C.14 prints a bare integer
		"stroom_from_machine": "Mechanische Droger",       # TagMap.gd:723
		"stroom_tag_motor": "softstarterdroger1",
		"cite_status": "mockup :29-30",
		"cite_timers": "mockup :32",
		"cite_cards": "mockup :37-39",
		"cite_lamps": "mockup :49",
		"cite_alarm": "mockup :24",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd",
			"Bewaking StartTijd", "Bewaking StopTijd"],    # mockup :32
		"cards": [                                          # mockup :37-39
			{"title": "Mechanische Droger",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"]},
			{"title": "Reinigingsschraper",
				"gewenst": ["Aanlooptijd", "Uitlooptijd"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Doseersluis Links",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
		],
		"cards_bottom": [],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Deur Droger"],  # mockup :49
	},

	# ---------------------------------------------------------------------
	# L3C.14 Mechanische Droger RECHTS
	# docs/plant/hmi_screens_2026-07-26/Waslijn 3C L3C.14 Mech Droger Rechts.dc.html
	#
	# This file is HAND-AUTHORED where its Links sibling is templated: per-card
	# HTML comments, a machine SVG the other screens do not have, and different
	# line numbers throughout. Its LOGICAL content is identical apart from
	# "Doseersluis Rechts". Ported as the second screen precisely because a
	# layout engine that only works on templated input is not a layout engine.
	# ---------------------------------------------------------------------
	"L3C.14R": {
		"code": "L3C.14R",
		"tag_unit": "14r",
		"title": "L3C.14 Mechanische Droger Rechts",      # mockup :33
		"amps_fmt": "int",
		# NOT the family grey. This screen's panel face is a DARK SLATE, used 5
		# times in its file (:32 and the three motor cards), on a 1024x768 canvas
		# rather than the 1280x800 every sibling uses. Recorded in
		# docs/plant/hmi_screen_inventory_2026-07-28.md:235 — "THIS FILE IS
		# STRUCTURALLY DIFFERENT FROM ITS FIVE SIBLINGS and a porter must not
		# assume one template". Rendering it in the sibling grey would be an
		# infidelity nothing else would catch.
		"panel_bg": "#5a6070",
		"stroom_from_machine": "Mechanische Droger",       # TagMap.gd:537 (14r mirrors the approved 14l row)
		"stroom_tag_motor": "softstarterdroger1",
		"cite_status": "mockup :35-36",
		"cite_timers": "mockup :38-42",
		"cite_cards": "mockup :48-85",
		"cite_lamps": "mockup :111-113",
		"cite_alarm": "mockup :28",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd",
			"Bewaking StartTijd", "Bewaking StopTijd"],    # mockup :38-42
		"cards": [                                          # mockup :50, :61, :75
			{"title": "Mechanische Droger",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"]},
			{"title": "Reinigingsschraper",
				"gewenst": ["Aanlooptijd", "Uitlooptijd"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Doseersluis Rechts",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
		],
		"cards_bottom": [],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Deur Droger"],  # mockup :111-113
	},

	# =====================================================================
	# THE REMAINING ELEVEN UNIT SCREENS
	#
	# Transcribed 2026-07-29 by eleven independent passes over the export, one
	# per screen, then cross-audited. Two things the audit established that a
	# single pass would have missed:
	#
	#  * NOTHING WAS NORMALISED. A fuzzy sweep over every visible text node in
	#    all 13 files (plus an alphanumeric-fold pass) found that every
	#    near-identical pair present here is also present in the HTML byte for
	#    byte. The safety-zone vocabulary alone has FOUR real variants:
	#      "Safety zone was"/"voorwas"   (Dutch)      L3C.1
	#      "Safety zone wash"/"prewash"  (English)    L3C.3/4/5/6/10/14
	#      "Safety zone wash" alone, no prewash lamp  L3C.12
	#      "Safety zone Extruder"                     L3C.18/19
	#    and "Uittrekschroef Links/midden/rechts" on L3C.1 is ONE capitalised
	#    beside TWO lower-case, while L3C.3 capitalises both of its two.
	#
	#  * CARD COUNTS VERIFIED TWO WAYS — by the header-band markup signature and
	#    by the width:220px card shells — agreeing with each other and with the
	#    entries below on all eleven screens. Zero dropped, zero invented.
	#    L3C.16 and L3C.18 really do have NO motor cards, and L3C.11 really has
	#    NO safety lamps (its lamp container at :51 is literally empty).
	#
	# THE CARDS ARE NOT UNIFORM, WITHIN OR ACROSS SCREENS. Asymmetries that a
	# template would have flattened, all confirmed against the HTML:
	#    L3C.3  Uittrekschroef L/R — Gewenst is [Frequentie] only, no
	#           Loopbewaking, while the other four cards on that screen have it
	#    L3C.11 Peddelwals 9,10    — Gewenst [Loopbewaking], Reeel [Frequentie, Stroom]
	#    L3C.19 has no Loopbewaking row at all; the string occurs 0 times in the file
	#    L3C.6  card two is "ontgrendel\ndeurmaalmolen" with an EMBEDDED NEWLINE.
	#           The single-space form does not occur in the file. Keep the \n.
	# =====================================================================

	"L3C.1": {
		"code": "L3C.1",
		"tag_unit": "1",
		"title": "L3C.1 Doseer Silo",   # mockup :28
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header trio Status Lijn 3C / Status was / Status Silo), :29 (left-panel Status)",
		"cite_timers": "mockup :32",
		"cite_cards": "mockup :37-39 (top row container :36-40); bottom-row container :43-45 is present but EMPTY",
		"cite_lamps": "mockup :49 (container :48-50)",
		"cite_alarm": "mockup :24",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Uittrekschroef Links",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Uittrekschroef midden",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Uittrekschroef rechts",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone was", "Safety zone voorwas", "Deurschakelaar"],
	},

	"L3C.3": {
		"code": "L3C.3",
		"tag_unit": "3",
		"title": "L3C.3 Bezinkafscheider",   # mockup :28 (also data-screen-label at :14)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header \"Status Lijn 3C\"=Auto, \"Status was\"=Aan, \"Status Silo\"=Aan) and :29-30 (left-panel \"Status\"=Aan plus the Hand/Auto pair)",
		"cite_timers": "mockup :32 (column headings Gewenst / Reëel at :31)",
		"cite_cards": "TOP row container mockup :36-40, cards at :37 (Intrekwals), :38 (Peddelwalzen), :39 (Afvoerwals). BOTTOM row container mockup :43-47, cards at :44 (Uittrekschroef Links), :45 (Uittrekschroef Rechts), :46 (Afvoerschraper).",
		"cite_lamps": "mockup :50-52 (all three inside the single flex column on :51)",
		"cite_alarm": "mockup :24 — number \"149\", text \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Intrekwals",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Peddelwalzen",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Afvoerwals",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
			{"title": "Uittrekschroef Links",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Uittrekschroef Rechts",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Afvoerschraper",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
		],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Safety zone prewash"],
	},

	"L3C.4": {
		"code": "L3C.4L",
		"tag_unit": "4l",
		"title": "L3C.4 Frictiescheider Links",   # mockup :28 (note: data-screen-label at :14 is the shorter "L3C.4 Frictiescheider" — different string)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header trio: \"Status Lijn 3C\"/Auto, \"Status was\"/Aan, \"Status Silo\"/Aan) ; :29 (left-panel \"Status\"/Aan) ; :30 (Hand/Auto pair) ; :37,:38 (green card header bands = running)",
		"cite_timers": "mockup :32 (all five rows are on one physical line; column headings \"Gewenst\" / \"Reëel\" at :31)",
		"cite_cards": "mockup :36-39 (top row container; card 1 = :37, card 2 = :38) ; :42-44 is the \"<!-- Bottom motor cards -->\" container and it is EMPTY — this screen has no second card row",
		"cite_lamps": "mockup :48 (all three lamps on one line, inside the :47-49 \"<!-- Safety indicators -->\" block)",
		"cite_alarm": "mockup :24 — banner reads \"149\" + \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"; the alarm belongs to a DIFFERENT unit, not to L3C.4",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Frictiescheider Links",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"],
				"code": "L3C.4L", "tag_unit": "4l", "tag_motor": "softstarterfrictiewasser"},
			{"title": "Frictiescheider Rechts",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"],
				"code": "L3C.4R", "tag_unit": "4r", "tag_motor": "softstarterfrictiewasser"},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Safety zone prewash"],
	},

	"L3C.5": {
		"code": "L3C.5L",
		"tag_unit": "5l",
		"title": "L3C.5 Transportschroef Links",   # mockup :28
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header trio \"Status Lijn 3C\"=Auto, \"Status was\"=Aan, \"Status Silo\"=Aan) ; :29-30 (left-panel \"Status\"=Aan + Hand/Auto pair)",
		"cite_timers": "mockup :32 (all five rows are on one physical line; column headers \"Gewenst\"/\"Reëel\" at :31)",
		"cite_cards": "mockup :36-39 (top row container :36; card 1 :37, card 2 :38). Bottom-row container :42-44 is present but EMPTY.",
		"cite_lamps": "mockup :47-49 (all three on line :48)",
		"cite_alarm": "mockup :24",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Transportschroef Links",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Transportschroef Rechts",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Safety zone prewash"],
	},

	"L3C.6": {
		"code": "L3C.6",
		"tag_unit": "6",
		"title": "L3C.6 Maalmolen",   # mockup :28 (panel heading; identical string also on :14 as data-screen-label)
		"amps_fmt": "int",
		"stroom_from_machine": "Maalmolen",
		"stroom_tag_motor": "softstartersnijmolen",
		"cite_status": "mockup :29-30 (unit panel: \"Status\" chip \"Aan\", then the \"Hand\" / \"Auto\" button pair) ; header band :19-21 (\"Status Lijn 3C\" Auto, \"Status was\" Aan, \"Status Silo\" Aan)",
		"cite_timers": "mockup :31 (column headings \"Gewenst\" / \"Reëel\") ; mockup :32 (all five rows are on the single line :32)",
		"cite_cards": "mockup :36-40 (top container, top:100px left:490px — Maalmolen :37, ontgrendel deurmaalmolen :38-39) ; mockup :43-47 (bottom container, top:420px left:490px — Schroef 1 :44, Schroef 2 :45, Schroef 3 :46)",
		"cite_lamps": "mockup :50-52 (all eight lamps are on the single line :51)",
		"cite_alarm": "mockup :24 — amber ticker, span \"149\" then \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\" (a FOREIGN unit's alarm shown on the L3C.6 screen; the banner is line-global, not unit-scoped)",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Maalmolen",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"]},
			{"title": "ontgrendel\ndeurmaalmolen",
				"gewenst": [],
				"reeel": []},
		],
		"cards_bottom": [
			{"title": "Schroef 1",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Schroef 2",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Schroef 3",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Safety zone prewash", "Deur Molen", "Deur zeef", "Veiligheids schakelaar", "Endcontact molen", "Endcontact zeef"],
	},

	"L3C.10": {
		"code": "L3C.10L",
		"tag_unit": "10l",
		"title": "L3C.10 Transportschroef Links",   # mockup :28
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header trio), :29 (left-panel Status), :30 (Hand/Auto)",
		"cite_timers": "mockup :32",
		"cite_cards": "mockup :36-39 (card 1 :37, card 2 :38); empty bottom-row container :42-44",
		"cite_lamps": "mockup :48",
		"cite_alarm": "mockup :24",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Transportschroef Links",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Transportschroef Rechts",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Safety zone prewash", "Sensor loopbewaking"],
	},

	"L3C.11": {
		"code": "L3C.11",
		"tag_unit": "11",
		"title": "L3C.11 Flotatietank",   # mockup :28 (same string also at :14 data-screen-label and inside the alarm strip :24)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "Chrome band mockup :19-21 (\"Status Lijn 3C\"/Auto, \"Status was\"/Aan, \"Status Silo\"/Aan) + clock :22; left-panel unit status mockup :29 (\"Status\"/Aan) with the Hand/Auto pair at :30",
		"cite_timers": "mockup :32 (all five rows are on one physical line; panel container :27-33, column headings Gewenst/Reëel at :31)",
		"cite_cards": "TOP row mockup :36-40 (Intrekwals :37, Peddelwals 1,2,3,4 :38, Peddelwals 5,6,7,8 :39); BOTTOM row mockup :43-47 (Peddelwals 9,10 :44, Afvoerwals :45, Opvoerschroef :46)",
		"cite_lamps": "mockup :50-52 — the \"Safety indicators\" container exists but the inner flex-column div at :51 is EMPTY (`...align-items:flex-end;\"></div>`). Zero lamp labels on this screen. Corroborated by inventory :217, which says the real screen is \"six motor cards plus the timer panel and a 3D mimic, nothing else\".",
		"cite_alarm": "mockup :24 — amber strip, number span \"149\" then \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Intrekwals",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Peddelwals 1,2,3,4",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Peddelwals 5,6,7,8",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
			{"title": "Peddelwals 9,10",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Afvoerwals",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
			{"title": "Opvoerschroef",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"lamps": [],
	},

	"L3C.12": {
		"code": "L3C.12",
		"tag_unit": "12",
		"title": "L3C.12 Transportschroef",   # mockup :28 (also the data-screen-label attribute at :14)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header \"Status Lijn 3C\" Auto / \"Status was\" Aan / \"Status Silo\" Aan) and :29-30 (left-panel \"Status\" Aan + Hand/Auto pair)",
		"cite_timers": "mockup :32 (all five rows are on that one physical line; the Gewenst/Reëel column headers are :31)",
		"cite_cards": "mockup :36-38 (the single card is the whole of :37); the bottom-cards container :41-43 is EMPTY",
		"cite_lamps": "mockup :46-48 (both lamps on :47)",
		"cite_alarm": "mockup :24 — \"149\" + \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\" (a FOREIGN unit's standing alarm, not L3C.12's)",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Transportschroef",
				"gewenst": ["Frequentie", "Loopbewaking"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone wash"],
	},

	"L3C.16": {
		"code": "L3C.16",
		"tag_unit": "16",
		"title": "L3C.16 Plasmaq",   # mockup :28 (also data-screen-label="L3C.16 Plasmaq" at :14)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header \"Status Lijn 3C\"=Auto, \"Status was\"=Aan, \"Status Silo\"=Aan) and :29 (left-panel \"Status\"=Aan); mode buttons \"Hand\"/\"Auto\" at :30",
		"cite_timers": "mockup :32 (column headings \"Gewenst\"/\"Reëel\" at :31; panel wrapper :27-33)",
		"cite_cards": "mockup :35-38 (top row container, EMPTY) and :40-43 (bottom row container, EMPTY) — both hold only whitespace, zero card divs",
		"cite_lamps": "mockup :45-48 (all four lamps on the single line :47)",
		"cite_alarm": "mockup :24 — \"149\" + \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd"],
		"cards": [
		],
		"cards_bottom": [
		],
		"lamps": ["Plasmaq Start", "Plasmaq Standby", "Plasmaq Ready", "Plasmaq Running"],
	},

	"L3C.18": {
		"code": "L3C.18",
		"tag_unit": "18",
		"title": "L3C.18 Extruder Silo",   # mockup :28 (same string also on the root div's data-screen-label, :14)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19 \"Status Lijn 3C\"/\"Auto\", :20 \"Status was\"/\"Aan\", :21 \"Status Silo\"/\"Aan\"; left-panel :29 \"Status\"/\"Aan\"; Hand/Auto buttons :30",
		"cite_timers": "mockup :32 (all five rows are concatenated onto ONE physical line — line numbers cannot separate them)",
		"cite_cards": "mockup :36-38 top container (comment \"<!-- Top motor cards -->\" :35, div :36, body is whitespace only :37) and :41-43 bottom container (comment :40, div :41, body whitespace only :42) — BOTH ARE EMPTY. This screen renders no motor cards at all.",
		"cite_lamps": "mockup :47 (all three lamps on one physical line inside the :46 \"<!-- Safety indicators -->\" wrapper)",
		"cite_alarm": "mockup :24 — badge \"149\" + text \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone Extruder", "Deur Silo"],
	},

	"L3C.19": {
		"code": "L3C.19",
		"tag_unit": "19",
		"title": "L3C.19 Rondmengventilator",   # mockup :28 (also data-screen-label :14)
		"amps_fmt": "int",
		"stroom_from_machine": "",
		"stroom_tag_motor": "",
		"cite_status": "mockup :19-21 (header \"Status Lijn 3C\" Auto / \"Status was\" Aan / \"Status Silo\" Aan) and :29-30 (left-panel \"Status\" Aan + Hand/Auto)",
		"cite_timers": "mockup :32 (all five rows are on the one long line 32)",
		"cite_cards": "mockup :36-38 (top row, the single card is all of line 37); bottom-card container :41-43 is EMPTY",
		"cite_lamps": "mockup :46-48 (all three on line 47)",
		"cite_alarm": "mockup :24 — \"149\" + \"L3C.11 Flotatietank Flow Meting: Water Flow te laag\"",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd", "Bewaking StartTijd", "Bewaking StopTijd"],
		"cards": [
			{"title": "Rondmeng Ventilator",
				"gewenst": ["Frequentie"],
				"reeel": ["Frequentie", "Stroom"]},
		],
		"cards_bottom": [
		],
		"lamps": ["Werkschakelaar", "Safety zone Extruder", "Deur Ventilator"],
	},
}
