class_name LaserFilter
extends StaticBody3D

# =============================================================================
# Rotary-disc melt-filter ("Laserfilter") — the big concentric circle on the
# 3C HMI. Filters polymer melt to 130 / 140 / 150 µm via two rotating discs
# and a scraper that continuously sheds caught debris into the lump cart
# parked at its discharge.
#
# Models four real-plant facts (operator-confirmed):
#   1. Filter resolution is marked PHYSICALLY on the screen plate (130/140/150
#      µm). The marking is invisible from the outside; the operator only reads
#      it during a filter change, while the housing is open.
#   2. Melt pressure differential ΔP (psi) rises with debris loading. Crossing
#      ~300 psi automatically boosts scraper RPM × 1.5 to clear the pack.
#      Releases when ΔP drops back below 250 psi (small hysteresis).
#   3. Screen plate thickness wears down each scrape. New plate ships at
#      ~1.80 mm; below 1.40 mm the special knife-riding layer is gone and the
#      plate is scrapped. Decay scales with effective scraper RPM.
#   4. Operator scraper-RPM strategy: running BELOW the nominal RPM keeps
#      more lumps in the melt loop and reduces waste-kg/shift. Higher RPM
#      ejects more lumps but wastes more product. The risk is hitting the
#      ΔP autoboost threshold and losing the strategy entirely.
#
# Filter change procedure (E-interaction at the unit while it's running or
# scrap-flagged):
#       STOP_SCRAPER → DEPRESSURIZE → OPEN → INSPECT → REMOVE → INSERT →
#       CLOSE → REPRESSURIZE → RESTART
#   Each step is a single E press except STOP_SCRAPER / DEPRESSURIZE /
#   REPRESSURIZE which auto-advance after a wait. While the procedure is
#   running, is_line_down() returns true so an upstream ExtruderModel can
#   starve the feed (no melt is going through an open filter housing).
# =============================================================================

# ── Tunables ─────────────────────────────────────────────────────────────────
const SCRAPER_BOOST_PSI         : float = 300.0
const SCRAPER_RELEASE_PSI       : float = 250.0    # hysteresis so it doesn't chatter
const SCRAPER_BOOST_FACTOR      : float = 1.50
const NOMINAL_SCRAPER_RPM       : float = 25.0
const MAX_SCRAPER_RPM           : float = 60.0
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
const DELTA_P_PER_LOADING_G     : float = 0.20     # psi per g loading
# ── Sawtooth disc-rotation cycle ─────────────────────────────────────────────
# The rotary disc indexes in discrete steps rather than scraping continuously:
# loading accumulates between advances (ΔP ramps up monotonically), then a
# single step purges most of the cake at once and breaks off a sausage chunk.
# Boost mode SHORTENS the interval (faster step-rate) rather than just scaling
# scraper RPM, so a high-ΔP event clears faster by indexing more often.
const ROTATION_INTERVAL_S       : float = 8.0      # nominal seconds between disc advances
const MIN_ROTATION_INTERVAL_S   : float = 2.0      # interval at full boost intensity
const ROTATION_PURGE_FRACTION   : float = 0.85     # fraction of loading shed per advance
# Stock of fresh screen plates, picked at random per insert.
const SCREEN_MESH_OPTIONS_UM    : Array[int] = [130, 140, 150]

# ── Asymmetric clog (operator-confirmed) ─────────────────────────────────────
# >90% of the time the FRONT (inlet) face clogs first because it catches debris
# before the back face. Operator-confirmed bias: ~85% of new loading lands on
# the front face. The screen is symmetric — the asymmetry is purely in LOADING.
const FRONT_LOAD_BIAS           : float = 0.85
# Root-cause amplification thresholds. Upstream pressure proxy and extruder
# RPM are reported into this node by ExtruderMachine; high values mean the
# inlet face is being slammed harder, so the front-side loading rate grows.
const UPSTREAM_PRESSURE_BASE_PSI : float = 250.0
const UPSTREAM_PRESSURE_SCALE_PSI : float = 250.0  # +1.0× amplification per this many psi over base
const EXTRUDER_RPM_BASE          : float = 110.0   # above this, additional front amplification kicks in
const EXTRUDER_RPM_SCALE         : float = 60.0    # +1.0× per this many rpm over base

# ── Procedure timings (sim seconds) ──────────────────────────────────────────
const T_STOP_SCRAPER_S    : float = 1.0
const T_DEPRESSURIZE_S    : float = 3.0
const T_REPRESSURIZE_S    : float = 5.0

enum Change {
	IDLE, STOP_SCRAPER, DEPRESSURIZE, OPEN, INSPECT, REMOVE, INSERT, CLOSE,
	REPRESSURIZE, RESTART
}

# ── Live state ───────────────────────────────────────────────────────────────
# #A3 — Cumulative lump-kg ejected this shift. The SCADA reads this to show
# the operator how much waste their scraper-RPM strategy is actually saving
# (low RPM → smaller number). Reset by ShiftClock at handover.
var lumps_kg_this_shift  : float = 0.0
var screen_mesh_um       : int   = 140
var screen_thickness_mm  : float = FRESH_THICKNESS_MM
var scraper_rpm          : float = NOMINAL_SCRAPER_RPM   # operator setpoint
var feed_throughput_kg_h : float = 0.0                   # set by ExtruderModel each tick
var auto_boost_active    : bool  = false
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
# Each side has its own ΔP from the same DELTA_P_PER_LOADING_G mapping.
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

# Optional discharge target — when set, scraped lumps drop into this cart.
var lump_cart            : Node  = null

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
	# Pick a screen-mesh value at random per spawn (matches a real plant where
	# the stock room contains a mix of 130/140/150 µm plates).
	screen_mesh_um = SCREEN_MESH_OPTIONS_UM[randi() % SCREEN_MESH_OPTIONS_UM.size()]

# =============================================================================
func _physics_process(delta: float) -> void:
	# Lazy lump-cart resolution: the cart parked at this extruder's
	# `lump_cart_spot` is the closest "lump_cart" group member. Re-checked
	# each tick only while we still don't have one, so a cart placed mid-game
	# starts collecting on the next tick.
	if lump_cart == null or not is_instance_valid(lump_cart):
		lump_cart = _closest_lump_cart()
	if _change_state != Change.IDLE:
		_advance_change(delta)
		return
	# Cascade halt (vacuum-alarm cascade-stop from ExtruderMachine): freeze the
	# scraper, hold all loading in place. Material conservation: nothing
	# accumulates while halted (upstream is also stopped). The procedure can
	# only be started after cascade_resume() clears the halt.
	if is_halted:
		return
	# Effective scraper RPM: operator setpoint × auto-boost factor if active.
	# Capped at MAX_SCRAPER_RPM so a 250 rpm setpoint + boost doesn't run away.
	# Still used for plate-wear scaling and as the sausage growth rate proxy
	# (a faster disc index ⇒ thicker rope between break-offs).
	var eff_rpm : float = clampf(
		scraper_rpm * (SCRAPER_BOOST_FACTOR if auto_boost_active else 1.0),
		0.0, MAX_SCRAPER_RPM)
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
	delta_p_front_psi = clampf(front_loading_g * DELTA_P_PER_LOADING_G, 0.0, 500.0)
	delta_p_back_psi  = clampf(back_loading_g  * DELTA_P_PER_LOADING_G, 0.0, 500.0)
	# ΔP autoboost gate with hysteresis — fires on TOTAL (max of front+back).
	# So even a one-sided front clog will trigger the boost as it should.
	var total_dp : float = max(delta_p_front_psi, delta_p_back_psi)
	if not auto_boost_active and total_dp > SCRAPER_BOOST_PSI:
		auto_boost_active = true
	elif auto_boost_active and total_dp < SCRAPER_RELEASE_PSI:
		auto_boost_active = false
	# Boost intensity 0..1 — drives the rotation-interval lerp. While the
	# autoboost is latched, intensity is 1.0 (fastest indexing); otherwise it
	# scales with how close current ΔP is to the boost threshold so the disc
	# already speeds up a bit as the cake approaches alarm.
	var boost_intensity : float = 1.0 if auto_boost_active else \
		clampf(total_dp / SCRAPER_BOOST_PSI, 0.0, 1.0)
	# ── Sawtooth advance gate ───────────────────────────────────────────────
	# Increment the timer; when it crosses the effective interval, step the
	# disc (purge + sausage break-off). The interval shortens with boost.
	_rotation_timer += delta
	var effective_interval : float = lerpf(ROTATION_INTERVAL_S, MIN_ROTATION_INTERVAL_S, boost_intensity)
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
	var growth_g_s : float = (front_add_g_s + back_add_g_s)
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

# Sawtooth ΔMP cycle: purge most of the accumulated cake in one step and break off the in-progress sausage.
func _disc_advance() -> void:
	# Lumps shed in this purge are the fraction of the current cake we're
	# sweeping off; credit them to the shift-waste counter and (if present)
	# the cart parked under the discharge.
	var purged_g : float = (front_loading_g + back_loading_g) * ROTATION_PURGE_FRACTION
	front_loading_g = maxf(0.0, front_loading_g * (1.0 - ROTATION_PURGE_FRACTION))
	back_loading_g  = maxf(0.0, back_loading_g  * (1.0 - ROTATION_PURGE_FRACTION))
	delta_p_front_psi = clampf(front_loading_g * DELTA_P_PER_LOADING_G, 0.0, 500.0)
	delta_p_back_psi  = clampf(back_loading_g  * DELTA_P_PER_LOADING_G, 0.0, 500.0)
	var lumps_kg : float = purged_g * 0.001
	if lumps_kg > 1.0e-5:
		lumps_kg_this_shift += lumps_kg
		if lump_cart != null and is_instance_valid(lump_cart) \
				and lump_cart.has_method("receive_lump"):
			lump_cart.call("receive_lump", lumps_kg)
	# Discharge the in-progress rope as a discrete chunk sized by what's grown
	# since the last advance.
	_break_off_sausage()
	_last_advance_t += _rotation_timer
	_rotation_timer = 0.0

# =============================================================================
# #B — Sausage extrusion from the scraper discharge
# =============================================================================
# The scraper sheds caught melt + grit through an eject port at the BOTTOM of
# the filter disc. In real life it's a continuous ~70 mm rope that piles up on
# the floor (or in a cart placed under it) and cools to a solid in a few
# minutes. We model that as:
#   * `_sausage` : the current in-progress rope, growing each tick by a length
#                  proportional to `clear_g_s` (so a low-RPM scraper extrudes
#                  a thinner rate). It's a single MeshInstance3D + tiny script-
#                  hosted parent so the colour can lerp from hot to cool.
#   * When length exceeds SAUSAGE_MAX_LEN_M OR vertical clearance below the
#     eject port hits zero, the rope BREAKS OFF into a RigidBody3D chunk that
#     falls under gravity and accumulates wherever the operator has set up
#     the catch zone (floor, cart pocket area, drip pan, etc.).
const SAUSAGE_DIAMETER_M     : float = 0.07
const SAUSAGE_GROW_M_PER_G   : float = 0.002    # m of rope length per g of scraper output
const SAUSAGE_MAX_LEN_M      : float = 0.55     # break off above this length
const SAUSAGE_HOT_COLOR      : Color = Color(1.00, 0.32, 0.06)
const SAUSAGE_COOL_COLOR     : Color = Color(0.18, 0.16, 0.14)
const SAUSAGE_COOL_TIME_S    : float = 180.0    # rope cools over 3 sim-minutes
const EJECT_LOCAL_OFFSET     : Vector3 = Vector3(0.0, -0.55, 0.0)  # ~ bottom of the filter disc

var _sausage         : MeshInstance3D = null
var _sausage_len_m   : float = 0.0
var _sausage_age_s   : float = 0.0
var _sausage_mat     : StandardMaterial3D = null

func _grow_sausage(delta: float, clear_g_s: float) -> void:
	_ensure_sausage()
	# Length growth: proportional to the cleared-debris rate (low RPM ⇒ thin
	# trickle, autoboost ⇒ thick rope). Capped per-tick so a giant time step
	# from a hitch can't extrude metres of rope at once.
	var grow_m : float = min(0.05, clear_g_s * delta * SAUSAGE_GROW_M_PER_G)
	_sausage_len_m += grow_m
	_sausage_age_s += delta
	# Rebuild the cylinder mesh + visual transform each tick. The rope hangs
	# DOWN from the eject port (local -Y), so position the cylinder so its TOP
	# sits at the port and it grows downward.
	var cyl := _sausage.mesh as CylinderMesh
	if cyl != null:
		cyl.height = max(0.01, _sausage_len_m)
		cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
		cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	_sausage.position = EJECT_LOCAL_OFFSET + Vector3(0.0, -_sausage_len_m * 0.5, 0.0)
	# Colour lerp: hot orange-red → cool grey as the rope ages.
	if _sausage_mat != null:
		var t : float = clampf(_sausage_age_s / SAUSAGE_COOL_TIME_S, 0.0, 1.0)
		_sausage_mat.albedo_color = SAUSAGE_HOT_COLOR.lerp(SAUSAGE_COOL_COLOR, t)
		# Hot rope glows; faded rope doesn't.
		_sausage_mat.emission_enabled = true
		_sausage_mat.emission = SAUSAGE_HOT_COLOR
		_sausage_mat.emission_energy_multiplier = lerpf(2.4, 0.0, t)
	# Break off when too long. The rope reaches the floor naturally at length
	# matching the eject-port-height-above-floor, which on a normal-height
	# laser filter is ~SAUSAGE_MAX_LEN_M. Break event spawns a falling chunk
	# and resets the in-progress rope to zero length.
	if _sausage_len_m >= SAUSAGE_MAX_LEN_M:
		_break_off_sausage()

func _ensure_sausage() -> void:
	if _sausage != null and is_instance_valid(_sausage):
		return
	_sausage_mat = StandardMaterial3D.new()
	_sausage_mat.albedo_color = SAUSAGE_HOT_COLOR
	_sausage_mat.metallic = 0.0
	_sausage_mat.roughness = 0.85
	_sausage = MeshInstance3D.new()
	_sausage.name = "ScraperSausage"
	var cyl := CylinderMesh.new()
	cyl.height = 0.01
	cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
	cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	_sausage.mesh = cyl
	_sausage.material_override = _sausage_mat
	add_child(_sausage)

## Break the in-progress rope off and spawn a fallen chunk under gravity. The
## chunk inherits the rope's CURRENT colour (so a thin slow extrusion drops
## chunks that are already half-cool) and lands wherever physics takes it.
func _break_off_sausage() -> void:
	if _sausage == null or not is_instance_valid(_sausage):
		return
	# Spawn a free-falling RB at the rope's current world position with the
	# rope's current dimensions. It'll bounce / settle / be caught by a cart
	# parked underneath via the cart's pocket + floor collision.
	var chunk := RigidBody3D.new()
	chunk.name = "LumpChunk"
	chunk.mass = max(0.05, _sausage_len_m * PI * (SAUSAGE_DIAMETER_M * 0.5) ** 2 * 950.0)
	chunk.add_to_group("lump_chunk")
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = _sausage_len_m
	cyl.top_radius = SAUSAGE_DIAMETER_M * 0.5
	cyl.bottom_radius = SAUSAGE_DIAMETER_M * 0.5
	mi.mesh = cyl
	# Re-use the current rope material so the chunk picks up the same colour.
	mi.material_override = _sausage_mat.duplicate() if _sausage_mat else null
	chunk.add_child(mi)
	var col := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.height = _sausage_len_m
	sh.radius = SAUSAGE_DIAMETER_M * 0.5
	col.shape = sh
	chunk.add_child(col)
	# Parent the chunk to the world (our parent's parent — the MainWorld scene)
	# at the rope's CURRENT world transform so it falls cleanly. Drop into our
	# parent if the world chain isn't reachable.
	var dest : Node = get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else get_parent()
	if dest != null:
		dest.add_child(chunk)
		chunk.global_transform = _sausage.global_transform
	# Reset the in-progress rope.
	_sausage_len_m = 0.0
	_sausage_age_s = 0.0

## Nearest "lump_cart" group member, by world distance. Searched lazily from
## _physics_process while we don't have one — that way the discharge wires up
## the instant the operator parks a cart at the spot.
func _closest_lump_cart() -> Node:
	var best : Node = null
	var best_d2 : float = INF
	for n in get_tree().get_nodes_in_group("lump_cart"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d2 : float = (n3.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best

## Quick check used by autonomy / HMI to know whether a change is overdue.
func filter_change_needed() -> bool:
	return screen_thickness_mm < MIN_USABLE_THICKNESS_MM \
		or delta_p_psi > SCRAPER_BOOST_PSI + 50.0

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
				return "Filterwissel — start [E]   (ΔP F%.0f / B%.0f psi · %.2f mm)" \
					% [delta_p_front_psi, delta_p_back_psi, screen_thickness_mm]
			return "Laserfilter ΔP F%.0f / B%.0f psi   (Δ%+.0f, %s)" % [
				delta_p_front_psi, delta_p_back_psi, delta_p_imbalance_psi,
				"boost actief" if auto_boost_active else "normaal"]
		Change.STOP_SCRAPER:  return "Schraper stoppen…"
		Change.DEPRESSURIZE:  return "Drukverlaging — wacht…"
		Change.OPEN:          return "Behuizing openen [E]"
		Change.INSPECT:
			# Screen plate itself is symmetric (single thickness + mesh value);
			# the asymmetric model lives in LOADING, not the plate. So inspect
			# still shows screen_mesh_um + screen_thickness_mm. Loading at the
			# point of inspect is irrelevant because OPEN already vented it.
			return "%d µm · %.2f mm — %s [E]" % [
				screen_mesh_um, screen_thickness_mm,
				SCRAP_LINE_TEXT if not is_usable() else OK_LINE_TEXT]
		Change.REMOVE:        return "Oude filter verwijderen [E]"
		Change.INSERT:        return "Nieuwe filter plaatsen [E]"
		Change.CLOSE:         return "Behuizing sluiten [E]"
		Change.REPRESSURIZE:  return "Druk opbouwen — wacht…"
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
		Change.OPEN, Change.INSPECT, Change.REMOVE, Change.INSERT, \
		Change.CLOSE, Change.RESTART:
			_advance_to_next_state()

# =============================================================================
# PROCEDURE STATE MACHINE
# =============================================================================
func _advance_to_next_state() -> void:
	_change_step_t = 0.0
	match _change_state:
		Change.OPEN:    _change_state = Change.INSPECT
		Change.INSPECT: _change_state = Change.REMOVE
		Change.REMOVE:  _change_state = Change.INSERT
		Change.INSERT:
			# Insert a fresh pack from stock. Resolution is whatever the
			# stockroom happens to have today.
			screen_thickness_mm = FRESH_THICKNESS_MM
			screen_mesh_um = SCREEN_MESH_OPTIONS_UM[randi() % SCREEN_MESH_OPTIONS_UM.size()]
			# Reset BOTH faces independently — a fresh pack is symmetric. The
			# computed `filter_loading_g` and `delta_p_psi` will read zero.
			front_loading_g = 0.0
			back_loading_g  = 0.0
			delta_p_front_psi = 0.0
			delta_p_back_psi  = 0.0
			auto_boost_active = false
			_change_state = Change.CLOSE
		Change.CLOSE:   _change_state = Change.REPRESSURIZE
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
			var bleed : float = (SCRAPER_BOOST_PSI + 100.0) / T_DEPRESSURIZE_S * delta
			delta_p_front_psi = maxf(0.0, delta_p_front_psi - bleed)
			delta_p_back_psi  = maxf(0.0, delta_p_back_psi  - bleed)
			if _change_step_t >= T_DEPRESSURIZE_S:
				_change_state = Change.OPEN
				_change_step_t = 0.0
		Change.REPRESSURIZE:
			if _change_step_t >= T_REPRESSURIZE_S:
				_change_state = Change.RESTART
				_change_step_t = 0.0
		_:
			# Operator-driven states: nothing to do here, waiting for E.
			pass
