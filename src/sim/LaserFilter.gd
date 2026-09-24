class_name LaserFilter
extends StaticBody3D

# =============================================================================
# Rotary-disc melt-filter ("Laserfilter") — the big concentric circle on the
# 3C HMI. Filters polymer melt through laser-drilled screen discs graded
# L1 (130–150 µm) / L3a (150–180 µm) / L3b (180–210 µm) via two rotating discs
# and a scraper that continuously sheds caught debris into the lump cart
# parked at its discharge.
# #223 docs->code — grades per docs/plant/swi/TRAIN-de-laserfilter-3A-typen__121_CeDo33.md
#
# Models four real-plant facts (operator-confirmed):
#   1. Filter resolution is marked PHYSICALLY on the screen plate (grade +
#      concrete µm). The marking is invisible from the outside; the operator
#      only reads it during a filter change, while the housing is open.
#   2. Melt pressure differential ΔMP rises with debris loading. Normal
#      production runs a 175–235 bar sawtooth (docs/plant/hmi_reference.md);
#      300 bar is the "needs attention" alarm, clearing below 250 bar
#      (small hysteresis). ΔMP is a READOUT — it does not drive the disc.
#   3. Screen plate thickness wears down each scrape. New plate ships at
#      ~1.80 mm; below 1.40 mm the special knife-riding layer is gone and the
#      plate is scrapped. Decay scales with effective scraper RPM.
#   4. Operator scraper-RPM strategy: running BELOW the nominal RPM keeps
#      more lumps in the melt loop and reduces waste-kg/shift. Higher RPM
#      ejects more lumps but wastes more product. The risk is hitting the
#      ΔP autoboost threshold and losing the strategy entirely.
#
# Filter change procedure (E-interaction at the unit while it's running or
# scrap-flagged) — follows Cedo PROD-SWI-074 "Laserfilter wissel LF 2-406"
# (rev 01, 26-07-2023) for every documented step; the depressurize/repressurize
# waits bridge the undocumented pages of the 24-page SWI:
#
#   STOP_SCRAPER → DEPRESSURIZE → LOTO → PLACE_BORDES → REMOVE_COMPACTBUIS →
#   CAP_NUTS_OFF → SWING_KAP → OPEN → INSPECT → REMOVE → CLEAN_BRAKERPLATE →
#   CLEAN_STAALBORSTEL → REPLACE_KOPEREN_RING → INSERT → REFIT_AFVOERVIJZEL →
#   CLOSE → TORQUE_UITZETSCHROEF → REPRESSURIZE → REMOVE_LOTO → RESTART
#
#   SWI-sourced facts baked into the steps:
#   * LOTO: werkschakelaar sits on the OTHER side of the filter; padlock on
#     (SWI-074 step 14). Removed again at the end before restart.
#   * Beschermkap comes free by removing the compactbuis + 3 dopmoeren with a
#     13 mm steek/ringsleutel; pull straight toward you, then swing RIGHT —
#     mind the cabling on the hinge side (steps 16-17).
#   * Brakerplate + doorvoer opening cleaned with plamuurmes en buis, then the
#     speciale staalborstel — makes refitting afvoervijzel II easier (30-31).
#   * Koperen ring in the scraper's aandrijfopening is SINGLE-USE — discard
#     every change, fit a new one (step 32).
#   * Uitzetschroef is tightened to 500 Nm with the dedicated calibrated
#     Stahlwille torque wrench — tighten-only, stop at the click (SWI-084).
#   * Plates ≥ 1.40 mm go back to the cleaning cycle for reuse (vacuum-oven
#     burn-out ≤400°C — off-screen); below 1.40 mm the nitriding layer is gone
#     and the plate is scrap (zeefplaten-reiniging guide).
#
#   Each step is a single E press except STOP_SCRAPER / DEPRESSURIZE /
#   REPRESSURIZE which auto-advance after a wait. While the procedure is
#   running, is_line_down() returns true so an upstream ExtruderModel can
#   starve the feed (no melt is going through an open filter housing).
# =============================================================================

const FloorPileScript = preload("res://src/sim/FloorPile.gd")   # P6 — floor overflow beside a full cart

# ── Tunables ─────────────────────────────────────────────────────────────────
# #223 docs→code — the disc + discharge are MOTOR-driven, NOT ΔP-driven.
# ΔMP is a READOUT only (+ the 318-bar upstream trip below). EREMA LF 2/406 HMI:
# M1-speed = disc-motor rpm (operator setpoint), M1-load = disc-motor load %.
# SCRAPER_*_PSI are kept ONLY as ΔP alarm/attention thresholds — they no longer
# drive disc speed (that ΔP→speed coupling was the operator-flagged error).
# #223 docs->code — thresholds are on the bar-realistic ΔP scale (see item-13
# calibration block below). docs/plant/hmi_reference.md: real ΔMP sawtooths
# 175–235 bar in normal production; docs/plant/swi/laserfilter-smeltdrukverschil__062_CeDo72.md
# gives the 0–300 bar setpoint band. 300 bar = the "needs attention" alarm.
const SCRAPER_BOOST_PSI         : float = 4351.0   # ΔP "needs attention" alarm = 300 bar (readout only)
const SCRAPER_RELEASE_PSI       : float = 3626.0   # alarm-clear hysteresis = 250 bar
const NOMINAL_SCRAPER_RPM       : float = 25.0     # M1 disc-motor nominal rpm
const MAX_SCRAPER_RPM           : float = 60.0
const NOMINAL_VIJZEL_RPM        : float = 30.0     # afvoervijzel (discharge-screw) motor nominal rpm
const MAX_VIJZEL_RPM            : float = 90.0
# Upstream ABSOLUTE melt pressure that trips an immediate shutdown of the
# compactor + extruder + pelletiser. Operator override: CeDo runs the trip at
# 318 bar (the EREMA manual page lists 320; the plant is set to 318).
const UPSTREAM_TRIP_BAR         : float = 318.0
const PSI_PER_BAR               : float = 14.5038
const FRESH_THICKNESS_MM        : float = 1.80
const MIN_USABLE_THICKNESS_MM   : float = 1.40     # < this → scrap on next inspection
const SCRAP_LINE_TEXT           : String = "SCRAP"
const OK_LINE_TEXT              : String = "OK"
# Decay rate at nominal RPM: a fresh plate runs ~8 h before hitting 1.40 mm.
const THICKNESS_DECAY_MM_PER_H_NOMINAL : float = 0.05
# Debris-loading scale: how fast loading grows per kg of melt passing through.
# Tunable; balanced so a steady 1000 kg/h reaches the 300-psi autoboost in
# ~10 sim minutes at nominal RPM, which matches the manual's typical ramp.
const LOADING_PER_KG_THROUGHPUT : float = 0.18     # g loading per kg melt
const LOADING_CLEAR_G_PER_RPM_S : float = 0.40     # g cleared per RPM per second
# ── #223 docs->code — item 13: bar-realistic ΔP model ────────────────────────
# docs/plant/hmi_reference.md §1 shows the real ΔMP-MF gauge running a 175–235
# bar sawtooth in normal production (MP<MF ~207 bar, ΔMP ~182 bar). The old
# ΔP = loading * 0.20 psi/g model maxed out at ~34 bar, pinning the gauge low.
# New model per face:  ΔP = CLEAN-SCREEN BASE + CAKE TERM.
#   * BASE = clean-screen flow resistance, ∝ feed throughput. Calibrated so a
#     steady 1000 kg/h reads ~170 bar (2465 psi) of clean-screen drop — the
#     bottom of the documented sawtooth. Applies to BOTH faces equally.
#   * CAKE = debris cake on THAT face's loading_g. Calibrated (2500 psi/g) so a
#     nominal sawtooth (front loading 0.06→0.40 g between disc advances) swings
#     the total ~180→239 bar — matching the doc's 175–235 bar band — and a
#     heavy cake (≳0.9 g front) pushes past the 300 bar attention alarm toward
#     the 350 bar clamp. Cake keeps the 85/15 front/back bias via loading_g.
# Total ΔP (HMI / alarm) = max(front, back); clamped to 350 bar (5076 psi).
const CLEAN_BASE_PSI_PER_KG_H   : float = 2.4656   # 170 bar / 1000 kg/h clean-screen resistance
const CAKE_PSI_PER_G            : float = 2500.0   # debris-cake ΔP per g of face loading
const DELTA_P_MAX_PSI           : float = 5076.0   # clamp = 350 bar (matches HMI 0–350 scale)
const CAKE_FULL_LOAD_PSI        : float = 1886.0   # cake worth 130 bar = 100% M1 disc-motor load
# ── Sawtooth disc-rotation cycle ─────────────────────────────────────────────
# The rotary disc indexes in discrete steps rather than scraping continuously:
# loading accumulates between advances (ΔP ramps up monotonically), then a
# single step purges most of the cake at once and breaks off a sausage chunk.
# Boost mode SHORTENS the interval (faster step-rate) rather than just scaling
# scraper RPM, so a high-ΔP event clears faster by indexing more often.
const ROTATION_INTERVAL_S       : float = 8.0      # nominal seconds between disc advances
const MIN_ROTATION_INTERVAL_S   : float = 2.0      # interval at full boost intensity
const ROTATION_PURGE_FRACTION   : float = 0.85     # fraction of loading shed per advance
# #223 docs->code — item 21: the three documented laserfilter grades.
# docs/plant/swi/TRAIN-de-laserfilter-3A-typen__121_CeDo33.md: L1 130–150 µm,
# L3a 150–180 µm, L3b 180–210 µm. Each grade is a µm band; a fresh insert picks
# a random grade, then a concrete µm inside its band (kept as screen_mesh_um so
# the HMI/SCADA readers still get a single concrete micron value).
const SCREEN_GRADES : Dictionary = {
	"L1":  Vector2i(130, 150),
	"L3a": Vector2i(150, 180),
	"L3b": Vector2i(180, 210),
}

# ── Asymmetric clog (operator-confirmed) ─────────────────────────────────────
# >90% of the time the FRONT (inlet) face clogs first because it catches debris
# before the back face. Operator-confirmed bias: ~85% of new loading lands on
# the front face. The screen is symmetric — the asymmetry is purely in LOADING.
const FRONT_LOAD_BIAS           : float = 0.85
# Root-cause amplification thresholds. Upstream pressure proxy and extruder
# RPM are reported into this node by ExtruderMachine; high values mean the
# inlet face is being slammed harder, so the front-side loading rate grows.
# Anchored in BAR since 2026-09-24. They were 250 / 250 PSI, tuned against an
# upstream signal that sat at 280 psi (a unit error — the plant's 280 is bar).
# Scaling both by the same factor keeps the amplification at nominal identical
# (+0.12x at 280 bar) now that the signal carries real bar-scale pressure.
const UPSTREAM_PRESSURE_BASE_PSI : float = 250.0 * PSI_PER_BAR
const UPSTREAM_PRESSURE_SCALE_PSI : float = 250.0 * PSI_PER_BAR  # +1.0× amplification per 250 bar over base
const EXTRUDER_RPM_BASE          : float = 110.0   # above this, additional front amplification kicks in
const EXTRUDER_RPM_SCALE         : float = 60.0    # +1.0× per this many rpm over base

# ── Procedure timings (sim seconds) ──────────────────────────────────────────
const T_STOP_SCRAPER_S    : float = 1.0
const T_DEPRESSURIZE_S    : float = 3.0
const T_REPRESSURIZE_S    : float = 5.0

enum Change {
	IDLE, STOP_SCRAPER, DEPRESSURIZE,
	# SWI-074 steps 14-17: isolate + free the beschermkap
	LOTO, PLACE_BORDES, REMOVE_COMPACTBUIS, CAP_NUTS_OFF, SWING_KAP,
	OPEN, INSPECT, REMOVE,
	# SWI-074 steps 30-32: internal cleaning + single-use wear ring
	CLEAN_BRAKERPLATE, CLEAN_STAALBORSTEL, REPLACE_KOPEREN_RING,
	INSERT, REFIT_AFVOERVIJZEL, CLOSE,
	# SWI-084: 500 Nm click-wrench on the uitzetschroef
	TORQUE_UITZETSCHROEF,
	REPRESSURIZE, REMOVE_LOTO, RESTART
}

# ── Live state ───────────────────────────────────────────────────────────────
# #A3 — Cumulative lump-kg ejected this shift. The SCADA reads this to show
# the operator how much waste their scraper-RPM strategy is actually saving
# (low RPM → smaller number). Reset by ShiftClock at handover.
var lumps_kg_this_shift  : float = 0.0
# SWI-074/084 consumable + reuse bookkeeping (read by HMI / SCADA):
#   * koperen ring is single-use — one consumed per completed change.
#   * plates ≥1.40 mm at inspection go back to the cleaning cycle (reuse);
#     thinner plates are scrap. Decided at the INSPECT step.
var koperen_rings_used   : int   = 0
var plates_to_cleaning   : int   = 0
var plates_scrapped      : int   = 0
var screen_mesh_um       : int   = 165                   # concrete µm (HMI/SCADA read this)
var screen_grade         : String = "L3a"                # #223 item 21: L1 / L3a / L3b (docs)
var screen_thickness_mm  : float = FRESH_THICKNESS_MM
var scraper_rpm          : float = NOMINAL_SCRAPER_RPM   # M1 disc-motor operator setpoint (rpm)
var afvoervijzel_rpm     : float = NOMINAL_VIJZEL_RPM    # discharge-screw motor setpoint (rpm)
var feed_throughput_kg_h : float = 0.0                   # set by ExtruderModel each tick
var m1_load_pct          : float = 0.0                   # HMI: disc-motor load % (from cake loading)
var is_tripped           : bool  = false                 # latched by the 318-bar upstream shutdown
# Emitted when upstream pressure crosses UPSTREAM_TRIP_BAR — ExtruderMachine
# connects this to stop the compactor + extruder + pelletiser together.
signal upstream_pressure_trip(bar)
var _change_state        : int   = Change.IDLE
var _change_step_t       : float = 0.0

# ── Sawtooth rotation state ──────────────────────────────────────────────────
# Time accumulator since the last disc advance. When it crosses the effective
# interval (lerp between nominal and min based on boost intensity), the disc
# steps and purges most of the loading at once.
var _rotation_timer      : float = 0.0
var _last_advance_t      : float = 0.0   # sim-time of the most recent advance (diagnostic)

# ── Asymmetric clog live state ───────────────────────────────────────────────
# Front (inlet) face accumulates ~85% of debris; back face the remainder.
# Each side has its own ΔP from the same _face_delta_p_psi() base+cake mapping.
# Total ΔP for autoboost / HMI = max(front, back).
var front_loading_g      : float = 0.0
var back_loading_g       : float = 0.0
var delta_p_front_psi    : float = 0.0
var delta_p_back_psi     : float = 0.0

# Upstream root-cause indicators (set by ExtruderMachine each tick). Read by
# the HMI to explain why the front face is clogging so fast.
var upstream_pressure_psi_indicator : float = 0.0
var extruder_rpm_indicator          : float = 0.0
# Un-melted lump feed rate (g/s) from cold extruder zones — slams the inlet
# face. Reported by ExtruderMachine when motor_torque_pct is high.
var lump_feed_rate_g_s              : float = 0.0

# Cascade halt: ExtruderMachine sets this true when the vacuum-alarm cascade
# fires. Freezes the scraper and blocks the filter-change procedure.
var is_halted : bool = false

# Optional discharge targets — when set, scraped lumps drop into these carts.
# #225.2 (operator 2026-07-14): the afvoervijzel discharges through a VERTICAL
# nozzle on BOTH sides of the disc. A lump cart sits under each.
# PLANT VOCABULARY (naming sweep 2026-08-07; measured 2026-08-03 with the
# test_lump_cart_coverage diagnostics): under the yaw every LINE_*_SEQ macro
# gives this filter, the +X mouth lands on the ACHTER (bordes) side — the
# raised cart — and the -X mouth on the VOOR side — the ground cart. The old
# labels ("aisle +X / wall -X") claimed the opposite; only the NAMES were
# wrong, each catch window always bound its own cart. CAVEAT: NpcTaskBench
# places the filter UNROTATED, so there the channel↔cart pairing mirrors
# (achter/+X holds the bench's ground cart) — see the BENCH MIRROR note in
# NpcTaskBench.gd.
var lump_cart_achter     : Node  = null   # achter (+X local; bordes/raised cart in MainWorld) — channel 0, single-cart default
var lump_cart_voor       : Node  = null   # voor (-X local; ground cart in MainWorld) — channel 1

# =============================================================================
# BACKWARD-COMPAT COMPUTED PROPERTIES
# =============================================================================
# Other modules (HMI, SCADA, autonomy) still read `filter_loading_g` and
# `delta_p_psi` as if they were single values. Expose them as computed
# properties so the asymmetric split is transparent to callers.
var filter_loading_g : float:
	get:
		return front_loading_g + back_loading_g
	set(value):
		# Legacy writers: split incoming total across the two faces using the
		# operator-confirmed bias. Used by reset paths and external resets.
		front_loading_g = value * FRONT_LOAD_BIAS
		back_loading_g  = value * (1.0 - FRONT_LOAD_BIAS)

var delta_p_psi : float:
	get:
		return max(delta_p_front_psi, delta_p_back_psi)
	set(value):
		# Legacy writers (e.g. the DEPRESSURIZE bleed) set this directly.
		# Mirror the value to both faces so the bleed clears both equally.
		delta_p_front_psi = value
		delta_p_back_psi  = value

# Operator-readable imbalance: positive = front clogged more than back.
# A persistently high value is the HMI's flag for "upstream pressure or
# extruder RPM is wrong" — i.e. the operator's "right side clogged again"
# anecdote.
var delta_p_imbalance_psi : float:
	get:
		return delta_p_front_psi - delta_p_back_psi

# =============================================================================
func _ready() -> void:
	add_to_group("laser_filter")
	# #223 docs->code — item 21: pick a documented grade (L1/L3a/L3b) + a concrete
	# µm inside its band per spawn (stock room holds a mix of grades).
	_pick_screen_grade()

# #223 docs->code — item 21: pick a random screen grade and a concrete µm inside
# its documented band. Sets both screen_grade (L1/L3a/L3b) and screen_mesh_um.
# docs/plant/swi/TRAIN-de-laserfilter-3A-typen__121_CeDo33.md.
func _pick_screen_grade() -> void:
	var grades : Array = SCREEN_GRADES.keys()
	screen_grade = grades[randi() % grades.size()]
	var band : Vector2i = SCREEN_GRADES[screen_grade]
	screen_mesh_um = band.x + (randi() % (band.y - band.x + 1))

# =============================================================================
func _physics_process(delta: float) -> void:
	# #225 — Cart binding, re-checked on a 2 s cadence (not just while null):
	# only a cart actually parked in the CATCH WINDOW under the discharge mouth
	# binds; a hauled-away / freed cart unbinds so the next parked cart takes
	# over. Prevents the old unbounded-nearest bug where a cart metres away
	# (or on the NEIGHBOURING line) silently received the kg credit while the
	# physical chunks piled on the floor.
	# Rebind BOTH nozzle carts by their own catch window (achter +X / voor -X).
	_cart_recheck_t += delta
	var _need_recheck : bool = _cart_recheck_t >= CART_RECHECK_S \
		or lump_cart_achter == null or not is_instance_valid(lump_cart_achter) \
		or lump_cart_voor == null or not is_instance_valid(lump_cart_voor)
	if _need_recheck:
		_cart_recheck_t = 0.0
		lump_cart_achter = _rebind_cart(lump_cart_achter, eject_global_achter())
		lump_cart_voor   = _rebind_cart(lump_cart_voor,   eject_global_voor())
	_absorb_settled_chunks(delta)
	if _change_state != Change.IDLE:
		_advance_change(delta)
		return
	# Cascade halt (vacuum-alarm cascade-stop from ExtruderMachine): freeze the
	# scraper, hold all loading in place. Material conservation: nothing
	# accumulates while halted (upstream is also stopped). The procedure can
	# only be started after cascade_resume() clears the halt.
	if is_halted:
		return
	# #223 — disc speed is the M1 MOTOR setpoint, full stop. No ΔP auto-boost:
	# ΔMP does not drive the disc (operator correction). eff_rpm scales plate
	# wear and the sausage index rate.
	var eff_rpm : float = clampf(scraper_rpm, 0.0, MAX_SCRAPER_RPM)
	# HMI M1-load %: disc-motor load rises with the cake on the more-clogged face.
	# #223 docs->code — cake-scaled (item 13): 100% at CAKE_FULL_LOAD_PSI (130 bar cake).
	m1_load_pct = clampf(max(front_loading_g, back_loading_g) * CAKE_PSI_PER_G / CAKE_FULL_LOAD_PSI * 100.0, 0.0, 100.0)
	# NO-FLOW GATE (operator 2026-07-16 "pressure rising while everything reads 0"):
	# ΔMP is a FLOW-driven pressure drop — with zero melt through the screen it must
	# read ambient (0), not keep integrating a phantom cake. Hold ΔP + M1-load at 0
	# and freeze loading/disc/wear while nothing is flowing; it all re-manifests the
	# instant real melt returns. (Paired with the ExtruderMachine gate so an unfed /
	# idle extruder forwards feed_throughput_kg_h = 0, not the 50 kg/h idle spin.)
	if feed_throughput_kg_h <= 0.0:
		delta_p_front_psi  = 0.0
		delta_p_back_psi   = 0.0
		m1_load_pct        = 0.0
		lump_feed_rate_g_s = 0.0
		return
	# #223 — 320-bar UPSTREAM hard trip: immediate shutdown of compactor +
	# extruder + pelletiser. Latches; halts the filter (is_line_down → the
	# upstream ExtruderModel stops feeding) and signals ExtruderMachine to stop
	# the trio together.
	if not is_tripped and upstream_pressure_psi_indicator / PSI_PER_BAR > UPSTREAM_TRIP_BAR:
		is_tripped = true
		is_halted = true
		upstream_pressure_trip.emit(upstream_pressure_psi_indicator / PSI_PER_BAR)
	# Loading rises with melt throughput. Discrete disc advances purge it
	# (see _disc_advance); BETWEEN advances loading rises monotonically so ΔP
	# climbs in a sawtooth pattern.
	var add_g_s   : float = feed_throughput_kg_h / 3600.0 * LOADING_PER_KG_THROUGHPUT
	# ── Asymmetric clog distribution ────────────────────────────────────────
	# Front (inlet) face takes ~85% of new loading; back takes ~15%. Front
	# additionally amplifies when upstream pressure or extruder RPM is high
	# (operator-confirmed root causes — the inlet face is being slammed
	# harder, so debris compacts onto it faster).
	var front_amp : float = 1.0
	front_amp += maxf(0.0, (upstream_pressure_psi_indicator - UPSTREAM_PRESSURE_BASE_PSI) / UPSTREAM_PRESSURE_SCALE_PSI)
	front_amp += maxf(0.0, (extruder_rpm_indicator          - EXTRUDER_RPM_BASE)          / EXTRUDER_RPM_SCALE)
	# Un-melted lumps coming in from a cold extruder slam the inlet face.
	# Added straight onto the front loading (not split).
	var front_add_g_s : float = add_g_s * FRONT_LOAD_BIAS * front_amp + lump_feed_rate_g_s
	var back_add_g_s  : float = add_g_s * (1.0 - FRONT_LOAD_BIAS)
	# Accumulate loading between advances (no continuous clearance — that
	# happens in discrete steps inside _disc_advance).
	front_loading_g = maxf(0.0, front_loading_g + front_add_g_s * delta)
	back_loading_g  = maxf(0.0, back_loading_g  + back_add_g_s  * delta)
	# #223 docs->code — item 13: bar-realistic ΔP = clean-screen base + cake.
	delta_p_front_psi = _face_delta_p_psi(front_loading_g)
	delta_p_back_psi  = _face_delta_p_psi(back_loading_g)
	# #223 — ΔMP is a READOUT ONLY now (front/back split, computed above). It no
	# longer changes disc speed — the disc indexes at the M1 motor rpm.
	# ── Sawtooth advance gate ───────────────────────────────────────────────
	# Increment the timer; when it crosses the effective interval, step the disc
	# (purge + sausage break-off). Index rate is set by the DISC MOTOR rpm:
	# faster motor → shorter interval. (Was driven by ΔP boost — removed.)
	_rotation_timer += delta
	var effective_interval : float = clampf(
		ROTATION_INTERVAL_S * NOMINAL_SCRAPER_RPM / maxf(eff_rpm, 1.0),
		MIN_ROTATION_INTERVAL_S, ROTATION_INTERVAL_S)
	if _rotation_timer >= effective_interval:
		_disc_advance()
	# Plate wear: higher RPM = more contact with the scraper edge = faster
	# decay. The "low-RPM strategy" benefits BOTH waste-kg AND plate life.
	var rpm_factor : float = eff_rpm / NOMINAL_SCRAPER_RPM
	var decay_mm_s : float = THICKNESS_DECAY_MM_PER_H_NOMINAL * rpm_factor / 3600.0
	screen_thickness_mm = maxf(0.0, screen_thickness_mm - decay_mm_s * delta)
	# #B — Physical sausage extrusion. Between disc advances, the rope grows
	# at a rate proportional to incoming loading (it captures whatever is
	# being caught on the disc). On _disc_advance the rope breaks off and a
	# discrete LumpChunk RB drops. Cooling colour lerp stays continuous so
	# slow extrusions land chunks that are already half-cool.
	# #223 — the afvoervijzel (discharge-screw) MOTOR augers the shed cake out as
	# the rope; its rpm sets the discharge rate. At nominal rpm this is unchanged;
	# rpm 0 stops discharge (lumps back up in the housing).
	var vijzel_factor : float = clampf(afvoervijzel_rpm / NOMINAL_VIJZEL_RPM, 0.0, MAX_VIJZEL_RPM / NOMINAL_VIJZEL_RPM)
	var growth_g_s : float = (front_add_g_s + back_add_g_s) * vijzel_factor
	_grow_sausage(delta, growth_g_s)

# =============================================================================
# PUBLIC API
# =============================================================================
## Called by the upstream ExtruderModel each physics tick to tell the filter
## how much melt is flowing through it. If never called, the filter idles at
## zero throughput and accumulates no debris.
func set_feed_throughput(kg_h: float) -> void:
	feed_throughput_kg_h = maxf(0.0, kg_h)

## Upstream pressure proxy (head-filter or extruder die ΔP). ExtruderMachine
## calls this every tick. High values amplify the FRONT loading rate — this
## is the operator-confirmed root-cause path for "right side clogged again":
## head filter is too clogged → upstream pressure climbs → front of laser
## filter gets slammed → front_loading_g runs away faster than back.
func set_upstream_pressure_indicator(p_psi: float) -> void:
	upstream_pressure_psi_indicator = maxf(0.0, p_psi)

## Extruder RPM proxy. Above ~110 rpm the inlet face gets additional debris
## velocity → more aggressive front-side packing. Set by ExtruderMachine each
## tick from its ExtruderConfig.screw_rpm.
func set_extruder_rpm_indicator(rpm: float) -> void:
	extruder_rpm_indicator = maxf(0.0, rpm)

## Un-melted lump feed rate from cold extruder zones. ExtruderMachine reports
## this when motor_torque_pct is high (cold barrel → high viscosity → un-
## melted material passes through to the laser filter). Lumps slam the inlet
## face, so this number is added directly to front_loading_g per tick.
func set_lump_feed_rate(g_per_s: float) -> void:
	lump_feed_rate_g_s = maxf(0.0, g_per_s)

## True while the operator has the housing open or the filter is stopped for
## change-out, OR while a cascade-stop from upstream is active. Upstream
## ExtruderModel should treat this as a hard stop.
func is_line_down() -> bool:
	return is_halted or _change_state != Change.IDLE

## Cascade-stop entry point: ExtruderMachine calls this when its 2-minute
## vacuum alarm cascades to FAULT. The scraper freezes, no further loading
## accumulates, and the filter-change procedure is blocked until
## cascade_resume() is called (the operator addresses the alarm). The PCU
## keeps running (handled at ExtruderMachine, not here).
func cascade_stop() -> void:
	is_halted = true
	# Freeze the discharge: any in-progress sausage rope just sits there. The
	# scraper's effective RPM is held at zero by the is_halted gate at the top
	# of _physics_process.

## Releases the cascade halt. After resume, the scraper restarts at its
## current setpoint (the operator may have changed it during the alarm).
func cascade_resume() -> void:
	is_halted = false

# #223 docs->code — item 13: bar-realistic ΔP for one filter face.
# docs/plant/hmi_reference.md §1 (ΔMP 175–235 bar) + docs/plant/swi/laserfilter-
# smeltdrukverschil__062_CeDo72.md (0–300 bar band). ΔP = clean-screen BASE
# (flow resistance ∝ throughput, both faces) + CAKE (this face's loading_g).
# Clamped to the 350 bar HMI scale.
func _face_delta_p_psi(loading_g: float) -> float:
	var base_psi : float = feed_throughput_kg_h * CLEAN_BASE_PSI_PER_KG_H
	return clampf(base_psi + loading_g * CAKE_PSI_PER_G, 0.0, DELTA_P_MAX_PSI)

# Sawtooth ΔMP cycle: purge most of the accumulated cake in one step and break off the in-progress sausage.
func _disc_advance() -> void:
	# Lumps shed in this purge are the fraction of the current cake we're
	# sweeping off; credit them to the shift-waste counter and (if present)
	# the cart parked under the discharge.
	var purged_g : float = (front_loading_g + back_loading_g) * ROTATION_PURGE_FRACTION
	front_loading_g = maxf(0.0, front_loading_g * (1.0 - ROTATION_PURGE_FRACTION))
	back_loading_g  = maxf(0.0, back_loading_g  * (1.0 - ROTATION_PURGE_FRACTION))
	# #223 docs->code — item 13: recompute on the bar-realistic base+cake scale.
	delta_p_front_psi = _face_delta_p_psi(front_loading_g)
	delta_p_back_psi  = _face_delta_p_psi(back_loading_g)
	var lumps_kg : float = purged_g * 0.001
	var act : Array = _active_channels()
	if lumps_kg > 1.0e-5:
		lumps_kg_this_shift += lumps_kg
		# Credit each ACTIVE nozzle's cart an equal share. Achter-only (a
		# single-cart line) → full credit, no regression; both carts → half
		# each. kg stays on the receive_lump path (regression-safe).
		var share_kg : float = lumps_kg / float(act.size())
		for i in act:
			var c : Node = lump_cart_achter if i == 0 else lump_cart_voor
			var refused : float = share_kg
			if c != null and is_instance_valid(c) and c.has_method("receive_lump"):
				var r = c.call("receive_lump", share_kg)
				refused = float(r) if r != null else 0.0
			# P6 (2026-09-23): what the cart could not take — it is at CAPACITY,
			# or no cart is parked under this nozzle — lands on the floor as a
			# FloorPile beside the cart instead of vanishing (it used to be
			# counted in lumps_kg_this_shift and then dropped; nothing ever read
			# is_full()). Operator spec, LumpCart.gd 2026-07-11: when full "the
			# discharge backs up / overflows on the floor".
			if refused > 0.0:
				_spill_to_floor(i, refused)
	# Discharge each ACTIVE nozzle's in-progress rope as a discrete chunk.
	for i in act:
		_break_off_chan(i)
	_last_advance_t += _rotation_timer
	_rotation_timer = 0.0

# =============================================================================
# #B — Sausage extrusion from the scraper discharge
# =============================================================================
# The scraper sheds caught melt + grit through TWO eject ports (achter +X /
# voor -X) at the bottom sides of the filter disc. In real life it's a
# continuous ~70 mm rope that piles into the cart under each nozzle and cools
# to a solid in a few minutes. We model that as:
#   * `_saus[i]` : channel i's in-progress rope (i=0 achter, i=1 voor), growing
#                  each tick by a length proportional to `clear_g_s` (so a
#                  low-RPM scraper extrudes a thinner rate). Each is one
#                  MeshInstance3D + material whose colour lerps hot→cool.
#   * When a channel's length exceeds SAUSAGE_MAX_LEN_M (or the disc advances),
#     that rope BREAKS OFF into a RigidBody3D chunk that falls under gravity
#     into the bound cart (or onto the floor as honest litter).
const SAUSAGE_DIAMETER_M     : float = 0.07
const SAUSAGE_GROW_M_PER_G   : float = 0.002    # m of rope length per g of scraper output
const SAUSAGE_MAX_LEN_M      : float = 0.55     # break off above this length
const SAUSAGE_HOT_COLOR      : Color = Color(1.00, 0.32, 0.06)
const SAUSAGE_COOL_COLOR     : Color = Color(0.18, 0.16, 0.14)
const SAUSAGE_COOL_TIME_S    : float = 180.0    # rope cools over 3 sim-minutes
# #225.2 — TWO outlet mouths of the afvoervijzel discharge, LOCAL to this node
# (origin at FLOOR level). Operator (2026-07-14): a VERTICAL discharge nozzle
# on BOTH sides of the disc — achter (+X) and voor (-X), plant sides per the
# 2026-08-03 measurement (see the lump_cart_achter block above) — each dropping
# straight down into its own cart. Mirrors _m_laser_filter's twin-spout
# geometry: lumps auger sideways just clear of the disc housing, then drop from
# a mouth whose lip (~1.13 m) clears the 0.95 m cart rim — so the rope/chunks
# land IN the bucket, never on the housing or the extruder. Vars (not const) so
# a differently-plumbed placeable can re-aim them.
# Renamed 2026-08-07 (was eject_local_offset / eject_wall_local — crossed
# labels); every external reader/test was grepped and updated in the same sweep.
var eject_achter_local       : Vector3 = Vector3( 1.30, 1.13, 0.0)   # achter (+X)
var eject_voor_local         : Vector3 = Vector3(-1.30, 1.13, 0.0)   # voor  (-X)

func eject_global_achter() -> Vector3: # achter (+X) — channel 0, single-cart default
	return to_global(eject_achter_local)
func eject_global_voor() -> Vector3:   # voor (-X)
	return to_global(eject_voor_local)

# Local mouth for channel i (0 = achter/+X, 1 = voor/-X).
func _chan_eject_local(i: int) -> Vector3:
	return eject_achter_local if i == 0 else eject_voor_local

# Two independent discharge channels. Each keeps its own in-progress rope
# (MeshInstance3D + material + length/age). Dicts are pass-by-ref so the helpers
# below mutate them in place.
var _saus : Array = [
	{"mi": null, "len": 0.0, "age": 0.0, "mat": null},
	{"mi": null, "len": 0.0, "age": 0.0, "mat": null},
]

## Which discharge nozzles are ACTIVE this tick: a nozzle only augers out if a
## cart is parked under it. Achter-only (a single-cart line) → all discharge
## routes to the achter channel exactly as before; both carts → split evenly.
## If NO cart is parked anywhere, the achter channel still extrudes so the
## rope visibly piles as honest "no cart parked" feedback (as it did before).
func _active_channels() -> Array:
	var act : Array = []
	if lump_cart_achter != null and is_instance_valid(lump_cart_achter):
		act.append(0)
	if lump_cart_voor != null and is_instance_valid(lump_cart_voor):
		act.append(1)
	if act.is_empty():
		act.append(0)
	return act

## Grow the ACTIVE nozzle ropes. The augered output is split evenly across them.
## Public 2-arg signature preserved (main loop + tests call it unchanged).
func _grow_sausage(delta: float, clear_g_s: float) -> void:
	var act : Array = _active_channels()
	var per : float = clear_g_s / float(act.size())
	for i in act:
		_grow_sausage_chan(i, delta, per)

func _grow_sausage_chan(i: int, delta: float, clear_g_s: float) -> void:
	_ensure_sausage(i)
	var st : Dictionary = _saus[i]
	# Length growth ∝ cleared-debris rate; per-tick cap so a hitch can't extrude
	# metres at once.
	var grow_m : float = min(0.05, clear_g_s * delta * SAUSAGE_GROW_M_PER_G)
	st["len"] = float(st["len"]) + grow_m
	st["age"] = float(st["age"]) + delta
	var ln : float = float(st["len"])
	var mi : MeshInstance3D = st["mi"]
	# Rope hangs DOWN from the eject port (local -Y): TOP sits at the port.
	var cyl := mi.mesh as CylinderMesh
	if cyl != null:
		cyl.height = max(0.01, ln)
		cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
		cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	mi.position = _chan_eject_local(i) + Vector3(0.0, -ln * 0.5, 0.0)
	# Colour lerp: hot orange-red → cool grey as the rope ages.
	var mat : StandardMaterial3D = st["mat"]
	if mat != null:
		var t : float = clampf(float(st["age"]) / SAUSAGE_COOL_TIME_S, 0.0, 1.0)
		mat.albedo_color = SAUSAGE_HOT_COLOR.lerp(SAUSAGE_COOL_COLOR, t)
		mat.emission_enabled = true
		mat.emission = SAUSAGE_HOT_COLOR
		mat.emission_energy_multiplier = lerpf(2.4, 0.0, t)
	# Break off when too long (reaches the cart naturally at ~SAUSAGE_MAX_LEN_M).
	if ln >= SAUSAGE_MAX_LEN_M:
		_break_off_chan(i)

func _ensure_sausage(i: int) -> void:
	var st : Dictionary = _saus[i]
	if st["mi"] != null and is_instance_valid(st["mi"]):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SAUSAGE_HOT_COLOR
	mat.metallic = 0.0
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.name = "ScraperSausage%d" % i
	var cyl := CylinderMesh.new()
	cyl.height = 0.01
	cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
	cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	mi.mesh = cyl
	mi.material_override = mat
	add_child(mi)
	st["mi"] = mi
	st["mat"] = mat

## A broken-off lump as a free RigidBody3D (not yet in the tree). Static so
## test_lump_chunk_ccd builds the exact production chunk.
## continuous_cd (phys-07): measured 2026-09-22 under Rapier3D, a chunk crossing
## the 2.5 cm cart-floor plate at -50 m/s from outside the contact-prediction
## margin tunnels straight through without it and is caught with it. A normal
## 1.5 m drop (~5.4 m/s) is caught either way — this covers flung/launched chunks.
static func make_lump_chunk(ln: float, mat: StandardMaterial3D) -> RigidBody3D:
	var chunk := RigidBody3D.new()
	chunk.name = "LumpChunk"
	chunk.mass = max(0.05, ln * PI * (SAUSAGE_DIAMETER_M * 0.5) ** 2 * 950.0)
	chunk.continuous_cd = true
	chunk.add_to_group("lump_chunk")
	var cmi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = ln
	cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
	cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	cmi.mesh = cyl
	cmi.material_override = mat.duplicate() if mat else null
	chunk.add_child(cmi)
	var col := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.height = ln
	sh.radius = SAUSAGE_DIAMETER_M * 0.5
	col.shape = sh
	chunk.add_child(col)
	return chunk

## Break channel i's in-progress rope off and spawn a fallen chunk under gravity.
## The chunk inherits the rope's CURRENT colour and lands wherever physics takes
## it (into the bound cart under that nozzle, or on the floor as honest litter).
func _break_off_chan(i: int) -> void:
	var st : Dictionary = _saus[i]
	var mi : MeshInstance3D = st["mi"]
	if mi == null or not is_instance_valid(mi):
		return
	var ln : float = max(0.02, float(st["len"]))
	var chunk := make_lump_chunk(ln, st["mat"])
	# Parent to the world (our parent's parent — the MainWorld scene) at the
	# rope's CURRENT world transform. Fall back to our parent if unreachable.
	var dest : Node = get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else get_parent()
	if dest != null:
		dest.add_child(chunk)
		_live_chunks.append(chunk)   # tracked for absorb-into-cart + litter cap
		chunk.global_transform = mi.global_transform
	# Reset this channel's in-progress rope.
	st["len"] = 0.0
	st["age"] = 0.0

# #225 — Catch window: how far the cart's centre may sit from the discharge
# mouth (XZ) and still catch the drop. Cart bucket interior half-extents are
# ~0.37 x 0.57 (0.85 x 1.30 outer); the slop lets a sloppily-parked cart still
# bind — chunks near the rim may bounce out, which is honest.
const CART_CATCH_DX : float = 0.55
const CART_CATCH_DZ : float = 0.85
const CART_RECHECK_S : float = 2.0
var _cart_recheck_t : float = 0.0

func _cart_in_catch_window(cart: Node, eject: Vector3) -> bool:
	var c3 := cart as Node3D
	if c3 == null:
		return false
	return absf(c3.global_position.x - eject.x) <= CART_CATCH_DX \
		and absf(c3.global_position.z - eject.z) <= CART_CATCH_DZ

## Keep the currently-bound cart if it's still in this nozzle's catch window;
## otherwise re-scan for the nearest cart in the window. Called for BOTH nozzles
## each recheck. The two windows are ~2.6 m apart in X (±1.30) vs a 0.55 m
## half-window, so a cart can never satisfy both — no cross-binding.
func _rebind_cart(current: Node, eject: Vector3) -> Node:
	if current != null and is_instance_valid(current) and _cart_in_catch_window(current, eject):
		return current
	return _closest_lump_cart(eject)

## Nearest "lump_cart" group member INSIDE the catch window under the given
## discharge mouth (#225 — was unbounded nearest-anywhere, which credited carts
## that could never physically catch the drop). Re-run from _physics_process on
## a cadence so the discharge wires up the moment a cart is parked at the spot.
func _closest_lump_cart(eject: Vector3) -> Node:
	var best : Node = null
	var best_d2 : float = INF
	for n in get_tree().get_nodes_in_group("lump_cart"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		if absf(n3.global_position.x - eject.x) > CART_CATCH_DX \
				or absf(n3.global_position.z - eject.z) > CART_CATCH_DZ:
			continue
		var d2 : float = (n3.global_position - eject).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best

# =============================================================================
# #225 — Chunk lifecycle. The kg accounting stays on the receive_lump() path
# (credited at _disc_advance when a cart is bound — unchanged, regression-safe);
# the RigidBody3D chunks are the VISUAL truth. A chunk that comes to rest inside
# the bound cart's bucket is absorbed (freed — its kg is already in the cart),
# a chunk that misses stays on the floor as honest litter for housekeeping.
# Litter is capped so an unattended filter can't accumulate unbounded RBs.
const CHUNK_ABSORB_CHECK_S : float = 1.0
const CHUNK_REST_SPEED     : float = 0.30
const MAX_LOOSE_CHUNKS     : int   = 16
var _live_chunks : Array = []
var _chunk_check_t : float = 0.0

func _absorb_settled_chunks(delta: float) -> void:
	_chunk_check_t += delta
	if _chunk_check_t < CHUNK_ABSORB_CHECK_S:
		return
	_chunk_check_t = 0.0
	var kept : Array = []
	for c in _live_chunks:
		var chunk := c as RigidBody3D
		if chunk == null or not is_instance_valid(chunk):
			continue
		var absorbed : bool = false
		# A chunk resting inside EITHER nozzle's bound cart is absorbed.
		for cart in [lump_cart_achter, lump_cart_voor]:
			var cart3 := cart as Node3D
			if cart3 == null or not is_instance_valid(cart3):
				continue
			# P6: a full cart does not swallow chunks — they stay where they
			# landed (on the heap, over the rim) as the visible overflow. The
			# litter cap below still bounds them.
			if cart3.has_method("is_full") and bool(cart3.call("is_full")):
				continue
			var dp : Vector3 = chunk.global_position - cart3.global_position
			# Inside the bucket footprint, below rim height, and settled.
			if absf(dp.x) <= 0.42 and absf(dp.z) <= 0.64 and dp.y <= 1.05 \
					and chunk.linear_velocity.length() < CHUNK_REST_SPEED:
				chunk.queue_free()
				absorbed = true
				break
		if not absorbed:
			kept.append(chunk)
	# Litter cap: free the OLDEST loose chunks beyond the cap.
	while kept.size() > MAX_LOOSE_CHUNKS:
		var old := kept.pop_front() as RigidBody3D
		if old != null and is_instance_valid(old):
			old.queue_free()
	_live_chunks = kept

# =============================================================================
# P6 (2026-09-23) — floor overflow at a full (or absent) cart.
# The refused kg from _disc_advance() goes into ONE FloorPile per nozzle (the
# same class LineFlow uses for uncaught chute reject, so the operator shovels
# it with the same tool). WHERE: at the cart's own spot, straight under the
# nozzle — which is where the rope and the chunks physically land. Lumps that
# no longer fit heap over the rim and slide down the sides, so the mound
# grows AROUND the cart's base (its cone stays under the underframe until it
# spreads past the wheels). The mound is SOFT (FloorPile.solid = false): a
# StaticBody3D growing inside a RigidBody3D cart's footprint ejects the cart.
# A first draft put a solid pile BESIDE the cart instead; measured 2026-09-23
# (test_lump_cart_overflow S9) that on lines 1, 3A and 3B the achter cart
# stands on its bordes between the filter and the extruder's 14 m collider,
# so no free floor exists on that side at all — and a solid pile there would
# have blocked the forklift's corridor to the cart. Bulk density is an
# assumption stated once: solid LDPE is ~920 kg/m³ and a heap of ~70 mm rope
# chunks packs at roughly 40 %, so 400 kg/m³ (FloorPile's 200 default is
# loose film). Not persisted across save/load — the same gap LineFlow's chute
# piles have.
# =============================================================================
const SPILL_PILE_RADIUS_M : float = 1.0     # ~270 kg at 400 kg/m³ before FloorPile refuses more
const SPILL_SEARCH_M      : float = 1.5     # reuse a FloorPile already within this of the spill point
const LUMP_BULK_DENSITY   : float = 400.0
var lumps_kg_on_floor : float = 0.0   # spilled beside the carts this shift (conserved; shovelable)
var lumps_kg_lost     : float = 0.0   # refused even by a maxed pile — the only place kg still vanishes
var _spill_piles : Array = [null, null]
var _spill_lost_warned : bool = false

## Floor point the overflow of nozzle `chan` lands on (global): straight under
## the nozzle, on whatever the cart stands on (floor or bordes).
func spill_point_global(chan: int) -> Vector3:
	var e : Vector3 = _chan_eject_local(chan)
	var above : Vector3 = to_global(e)
	var p : Vector3 = above
	p.y = _floor_y_below(above)
	return p

## Floor height under `from` (ray down 6 m). Skips this body, carts, chunks and
## piles — the things that stand ON the floor there — by re-casting past each,
## so the mound lands on the floor the cart stands on, not on the cart. Falls
## back to the filter's own base height when nothing is hit (no floor body in
## a probe).
func _floor_y_below(from: Vector3) -> float:
	var w3d := get_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		return global_position.y
	var excl : Array[RID] = [get_rid()]
	for _pass in 6:
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -6.0, 0.0))
		q.exclude = excl
		var hit := w3d.direct_space_state.intersect_ray(q)
		if not hit.has("position"):
			return global_position.y
		var col = hit.get("collider")
		var n := col as Node
		var skip := false
		if n != null:
			var par := n.get_parent()
			skip = n.is_in_group("lump_cart") or n.is_in_group("lump_chunk") \
				or (par != null and par.is_in_group("floor_pile"))
		if skip and hit.has("rid"):
			excl.append(hit["rid"])
			continue
		return float((hit["position"] as Vector3).y)
	return global_position.y

## The pile for nozzle `chan`: the one already bound, else a FloorPile already
## lying at the spill point (after a rebuild, or LineFlow's own chute pile),
## else a new one parented like the chunks (the world scene).
func _spill_pile(chan: int) -> Node:
	var cur = _spill_piles[chan]
	if cur != null and is_instance_valid(cur):
		return cur
	var at : Vector3 = spill_point_global(chan)
	var best : Node = null
	var best_d : float = SPILL_SEARCH_M
	for p in get_tree().get_nodes_in_group("floor_pile"):
		var p3 := p as Node3D
		if p3 == null:
			continue
		var d : float = p3.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = p3
	if best == null:
		var pile = FloorPileScript.new()
		pile.name = "LumpSpill%d" % chan
		pile.max_radius_m = SPILL_PILE_RADIUS_M
		pile.pile_color = SAUSAGE_COOL_COLOR
		pile.solid = false   # soft — see the header: a collider here ejects the cart
		var dest : Node = get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else get_parent()
		if dest == null:
			dest = self
		dest.add_child(pile)
		(pile as Node3D).global_position = at
		best = pile
	_spill_piles[chan] = best
	return best

func _spill_to_floor(chan: int, kg: float) -> void:
	if kg <= 0.0:
		return
	var pile : Node = _spill_pile(chan)
	var left : float = kg
	if pile != null and pile.has_method("add"):
		left = float(pile.call("add", kg, LUMP_BULK_DENSITY))
	lumps_kg_on_floor += kg - left
	if left > 0.0:
		lumps_kg_lost += left
		if not _spill_lost_warned:
			_spill_lost_warned = true
			push_warning("[LaserFilter] lump spill pile at nozzle %d is at its %.1f m radius — %.2f kg refused (counted in lumps_kg_lost; shovel it or park an empty cart)"
				% [chan, SPILL_PILE_RADIUS_M, left])

## Quick check used by autonomy / HMI to know whether a change is overdue.
func filter_change_needed() -> bool:
	# #223 docs->code — item 13: margin scaled to the bar-realistic ΔP (+725 psi
	# = 50 bar above the 300 bar attention alarm, i.e. sustained ~350 bar).
	return screen_thickness_mm < MIN_USABLE_THICKNESS_MM \
		or delta_p_psi > SCRAPER_BOOST_PSI + 725.0

func is_usable() -> bool:
	return screen_thickness_mm >= MIN_USABLE_THICKNESS_MM

## #A3 — ShiftClock calls this at handover to zero the shift waste counter.
func reset_shift_counters() -> void:
	lumps_kg_this_shift = 0.0

# =============================================================================
# CROSSHAIR INTERACTION (E)
# =============================================================================
func crosshair_prompt(_p: Node3D) -> String:
	# Cascade-halted: the operator can see the unit is down but the change
	# procedure is blocked until the upstream alarm is cleared.
	if is_halted and _change_state == Change.IDLE:
		return "Laserfilter — gestopt (cascade-halt — verhelp eerst de vacuüm-alarm)"
	match _change_state:
		Change.IDLE:
			if filter_change_needed():
				# Show the asymmetric ΔP split — operator reads imbalance to
				# spot upstream pressure / extruder-RPM issues at a glance.
				# #223 docs->code — item 13: operator thinks in BAR (÷ PSI_PER_BAR).
				return "Filterwissel — start [E]   (ΔP F%.0f / B%.0f bar · %.2f mm)" \
					% [delta_p_front_psi / PSI_PER_BAR, delta_p_back_psi / PSI_PER_BAR, screen_thickness_mm]
			# #223 docs->code — item 13: ΔP shown in BAR (÷ PSI_PER_BAR).
			return "Laserfilter ΔP F%.0f / B%.0f bar   (Δ%+.0f, %s)" % [
				delta_p_front_psi / PSI_PER_BAR, delta_p_back_psi / PSI_PER_BAR,
				delta_p_imbalance_psi / PSI_PER_BAR,
				"GETRIPT" if is_tripped else "normaal"]
		Change.STOP_SCRAPER:  return "Schraper stoppen…"
		Change.DEPRESSURIZE:  return "Drukverlaging — wacht…"
		# ── SWI-074 stap 14-17 ───────────────────────────────────────────────
		Change.LOTO:
			return "Werkschakelaar UIT (andere kant filter) + hangslot [E]"
		Change.PLACE_BORDES:
			return "Bordes plaatsen — let op het openen van de deur [E]"
		Change.REMOVE_COMPACTBUIS:
			return "Compactbuis verwijderen [E]"
		Change.CAP_NUTS_OFF:
			return "3× dopmoer losdraaien — steek/ringsleutel 13 mm [E]"
		Change.SWING_KAP:
			return "Kap recht naar je toe, dan naar rechts wegdraaien — let op bekabeling scharnierzijde [E]"
		Change.OPEN:          return "Behuizing openen [E]"
		Change.INSPECT:
			# Screen plate itself is symmetric (single thickness + mesh value);
			# the asymmetric model lives in LOADING, not the plate. So inspect
			# still shows screen_mesh_um + screen_thickness_mm. Loading at the
			# point of inspect is irrelevant because OPEN already vented it.
			# ≥1.40 mm → cleaning cycle for reuse; below → nitreerlaag gone, scrap.
			return "%d µm · %.2f mm — %s [E]" % [
				screen_mesh_um, screen_thickness_mm,
				SCRAP_LINE_TEXT if not is_usable() else OK_LINE_TEXT + " → reiniging"]
		Change.REMOVE:        return "Oude zeefplaat verwijderen [E]"
		# ── SWI-074 stap 30-32 ───────────────────────────────────────────────
		Change.CLEAN_BRAKERPLATE:
			return "Brakerplate + doorvoeropening schoonmaken — plamuurmes en buis [E]"
		Change.CLEAN_STAALBORSTEL:
			return "Overtollig smelt verwijderen — speciale staalborstel [E]"
		Change.REPLACE_KOPEREN_RING:
			return "Koperen ring uit aandrijfopening schraper — EENMALIG gebruik, nieuwe plaatsen [E]"
		Change.INSERT:        return "Nieuwe zeefplaat plaatsen [E]"
		Change.REFIT_AFVOERVIJZEL:
			return "Afvoervijzel II terugplaatsen [E]"
		Change.CLOSE:         return "Kap terug + dopmoeren aandraaien [E]"
		# ── SWI-084 ──────────────────────────────────────────────────────────
		Change.TORQUE_UITZETSCHROEF:
			return "Uitzetschroef aandraaien — Stahlwille momentsleutel 500 Nm, stop direct na klik [E]"
		Change.REPRESSURIZE:  return "Druk opbouwen — wacht…"
		Change.REMOVE_LOTO:
			return "Hangslot verwijderen + werkschakelaar AAN [E]"
		Change.RESTART:       return "Schraper herstarten [E]"
	return ""

func crosshair_interact(_p: Node3D) -> void:
	# Cascade-halted: refuse to start the change procedure. Operator must
	# clear the upstream vacuum alarm first (cascade_resume() called by
	# ExtruderMachine when the alarm is addressed).
	if is_halted and _change_state == Change.IDLE:
		return
	match _change_state:
		Change.IDLE:
			_change_state = Change.STOP_SCRAPER
			_change_step_t = 0.0
		Change.LOTO, Change.PLACE_BORDES, Change.REMOVE_COMPACTBUIS, \
		Change.CAP_NUTS_OFF, Change.SWING_KAP, \
		Change.OPEN, Change.INSPECT, Change.REMOVE, \
		Change.CLEAN_BRAKERPLATE, Change.CLEAN_STAALBORSTEL, \
		Change.REPLACE_KOPEREN_RING, \
		Change.INSERT, Change.REFIT_AFVOERVIJZEL, Change.CLOSE, \
		Change.TORQUE_UITZETSCHROEF, Change.REMOVE_LOTO, Change.RESTART:
			_advance_to_next_state()

# =============================================================================
# PROCEDURE STATE MACHINE
# =============================================================================
func _advance_to_next_state() -> void:
	_change_step_t = 0.0
	match _change_state:
		# SWI-074 steps 14-17: LOTO → bordes → compactbuis → dopmoeren → kap.
		Change.LOTO:               _change_state = Change.PLACE_BORDES
		Change.PLACE_BORDES:       _change_state = Change.REMOVE_COMPACTBUIS
		Change.REMOVE_COMPACTBUIS: _change_state = Change.CAP_NUTS_OFF
		Change.CAP_NUTS_OFF:       _change_state = Change.SWING_KAP
		Change.SWING_KAP:          _change_state = Change.OPEN
		Change.OPEN:    _change_state = Change.INSPECT
		Change.INSPECT:
			# Reuse decision happens HERE, while the operator can read the plate:
			# ≥1.40 mm → cleaning cycle (vacuum-oven burn-out, off-screen);
			# thinner → nitreerlaag gone, scrap. (zeefplaten-reiniging guide)
			if is_usable():
				plates_to_cleaning += 1
			else:
				plates_scrapped += 1
			_change_state = Change.REMOVE
		Change.REMOVE:  _change_state = Change.CLEAN_BRAKERPLATE
		# SWI-074 steps 30-32: internal cleaning + single-use koperen ring.
		Change.CLEAN_BRAKERPLATE:  _change_state = Change.CLEAN_STAALBORSTEL
		Change.CLEAN_STAALBORSTEL: _change_state = Change.REPLACE_KOPEREN_RING
		Change.REPLACE_KOPEREN_RING:
			# The ring "kan niet meer gebruikt worden" — one consumed per change.
			koperen_rings_used += 1
			_change_state = Change.INSERT
		Change.INSERT:
			# Insert a fresh pack from stock. Resolution is whatever the
			# stockroom happens to have today.
			screen_thickness_mm = FRESH_THICKNESS_MM
			# #223 docs->code — item 21: pick a documented grade + concrete µm.
			_pick_screen_grade()
			# Reset BOTH faces independently — a fresh pack is symmetric. The
			# computed `filter_loading_g` and `delta_p_psi` will read zero.
			front_loading_g = 0.0
			back_loading_g  = 0.0
			delta_p_front_psi = 0.0
			delta_p_back_psi  = 0.0
			is_tripped = false
			_change_state = Change.REFIT_AFVOERVIJZEL
		# Cleaning the doorvoeropening earlier makes this re-fit easier (the
		# stated purpose of SWI-074 step 30) — in sim terms simply the next step.
		Change.REFIT_AFVOERVIJZEL: _change_state = Change.CLOSE
		Change.CLOSE:   _change_state = Change.TORQUE_UITZETSCHROEF
		# SWI-084: dedicated calibrated click-wrench, tighten-only, 500 Nm.
		Change.TORQUE_UITZETSCHROEF: _change_state = Change.REPRESSURIZE
		Change.REMOVE_LOTO: _change_state = Change.RESTART
		Change.RESTART:
			scraper_rpm = NOMINAL_SCRAPER_RPM
			_change_state = Change.IDLE

## Drives the auto-advancing wait states (stop scraper, depressurize,
## repressurize). The E-driven states sit in their match arm doing nothing
## until the operator presses E.
func _advance_change(delta: float) -> void:
	_change_step_t += delta
	match _change_state:
		Change.STOP_SCRAPER:
			scraper_rpm = 0.0
			if _change_step_t >= T_STOP_SCRAPER_S:
				_change_state = Change.DEPRESSURIZE
				_change_step_t = 0.0
		Change.DEPRESSURIZE:
			# Bleed pressure linearly to zero over T_DEPRESSURIZE_S. Bleeds
			# both faces independently so an asymmetric clog vents correctly
			# (the bleed valve drains the whole housing). The setter on
			# delta_p_psi would force both sides equal — we want each side to
			# decay from its own current value.
			# #223 docs->code — item 13: bleed rate on the bar-realistic scale.
			# (SCRAPER_BOOST_PSI + 725) = 5076 psi = the 350 bar clamp, so the
			# bleed drains a fully-pinned housing to zero within T_DEPRESSURIZE_S.
			var bleed : float = (SCRAPER_BOOST_PSI + 725.0) / T_DEPRESSURIZE_S * delta
			delta_p_front_psi = maxf(0.0, delta_p_front_psi - bleed)
			delta_p_back_psi  = maxf(0.0, delta_p_back_psi  - bleed)
			if _change_step_t >= T_DEPRESSURIZE_S:
				# SWI-074: isolate + padlock BEFORE any mechanical work starts.
				_change_state = Change.LOTO
				_change_step_t = 0.0
		Change.REPRESSURIZE:
			if _change_step_t >= T_REPRESSURIZE_S:
				# Padlock comes off last, then the scraper restart.
				_change_state = Change.REMOVE_LOTO
				_change_step_t = 0.0
