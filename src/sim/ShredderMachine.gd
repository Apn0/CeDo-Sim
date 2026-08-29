class_name ShredderMachine
extends StaticBody3D

# =============================================================================
# Shredder sim brain — Shredder 1 (coarse, Line 1 + 3C/6) / Shredder 2 (fine,
# 3A/3B). Attached to the `shredder_1` / `shredder_2` placeables at build time
# (PlaceableCatalog.build_node), so the procedural model's rotor / stator / hopper
# geometry hangs underneath and the leg/collision/group plumbing keeps working.
#
# Makes the shredder FUNCTIONAL + REPEATABLE (was a static visual):
#   * Relay-panel control (ShredderRelayPanel): KEY SWITCH (I Auto / II Hand /
#     III Onderhoud), GREEN "Automaat start", RED "Noodstop" e-stop.
#   * Throughput physics: feed kg/h in → shredded output, capped at the machine's
#     rated capacity; overfeed backs up in a buffer (bunker) and spills as
#     overflow; motor load % rises with feed; sustained overload TRIPS the motor.
#   * Rotor spin gated on the run state — the two RotatingMechanism rotors only
#     turn while the machine is actually running (not stopped / e-stopped /
#     tripped / open / rotor-locked).
#   * SWI procedures as crosshair (E) interactions:
#       - start / stop            (SWI-048/049 opstarten sorteerlijn, SWI-035 stop)
#       - NOODSTOP reset          (quarter-turn)
#       - motor-overload reset
#       - OPEN housing            (SWI-027 sh1 / SWI-040 sh2) — only in Onderhoud
#       - BLOK rotor / deblok     (SWI-033 rotor blokkeren) — LOTO for cleaning
#       - CLEAN + close           (SWI-034 sh1; NO SWI exists for sh2 cleaning)
#         Citation audit 2026-08-11: this line used to cite "SWI-042 sh2".
#         SWI-042 is "Leegdraaien lijn 3 voor meswissel" (empty-running line 3
#         for a knife change), not a shredder-2 cleaning procedure, and the SWI
#         index has no shredder-2 cleaning doc at all — only SWI-040 "Lijn 3
#         openen shredder 2". Treat sh2 cleaning as undocumented.
#
# Data (docs): whole-plant film feed 4500 kg/h (7.5 bales × 600 kg); ~2082 kg/h
# clean flake after magnet + 2× TITECH; shredder-2 overflow ~100 kg/dienst; bunker
# 750 kg/10 min. Rated caps below are grounded on those; refine with the operator.
# =============================================================================

enum Kind { COARSE, FINE }
enum Key  { AUTO, HAND, ONDERHOUD }

# ── Config (resolved from placeable_id in _ready) ────────────────────────────
var kind        : int   = Kind.COARSE
var rated_kg_h  : float = 4500.0                 # coarse handles the whole bale feed
const RATED_COARSE : float = 4500.0
const RATED_FINE   : float = 2200.0
const OVERFLOW_KG  : float = 750.0               # bunker/buffer cap before it spills
const TRIP_PCT     : float = 118.0               # motor load that (sustained) trips
const TRIP_TIME_S  : float = 5.0                 # seconds of overload before the trip

# ── Knife-geometry cutting-capacity cross-check (operator 2026-08-29) ────────
# shredder_1's rotor/stator geometry, per the operator's own live estimate —
# NOT a measured plant figure like RATED_COARSE above; easy to correct once
# real numbers exist. Same machine on line 1 and 3C (BuildMode.gd's LINE_1_SEQ
# / LINE_3C_SEQ comment: "3C/6 = the big-RED coarse shredder... Same id as
# Line 1"), so one set of numbers covers both.
const KNIFE_ROTOR_COUNT   : int   = 75    # total knives around the rotor
const KNIFE_STATOR_COUNT  : int   = 15    # fixed counter-knives
const KNIFE_STATOR_EDGE_M : float = 5.0   # TOTAL cutting edge across all 15
                                           # (operator: "total across all",
                                           # i.e. NOT per-knife — ~0.33 m each)
# Minimum rotor set point ("it has to ramp up... the minimum set point was
# 30 RPM"). Independently corroborated within ~2 rpm by
# docs/plant/checklist_lijn1.md row 9 (FORM-007): "Toerental shredder ...
# 32-50 rpm" — that same doc flags an unreconciled 35-60 rpm figure for
# "Shredder 1" on FORM-008 (checklist_3a_3b.md:99) as an OPEN question, not
# settled ground truth, so treat 30 as the operator's live number, not as
# something the docs already nailed down.
const KNIFE_ROTOR_RPM_MIN : float = 30.0

## Total length of stator cutting edge a rotor knife sweeps past, per second,
## at the given RPM. The operator's own framing, translated directly: "how
## many times per second those areas are sliding along each other" (rotor
## knife count × rev/s) times "the [stator] surface area that can be cut"
## (the 5 m of total stator edge). A pure geometric rate — m of edge per
## second — not yet a mass rate; see implied_chip_depth_m() for why.
static func swept_edge_rate_m_s(rpm: float = KNIFE_ROTOR_RPM_MIN) -> float:
	return KNIFE_STATOR_EDGE_M * float(KNIFE_ROTOR_COUNT) * (rpm / 60.0)

## Cross-check, NOT a replacement for RATED_COARSE. Turning a swept EDGE
## LENGTH into a mass rate needs one more number geometry alone can't supply:
## how much material THICKNESS actually gets sheared off per pass (a "chip
## load", in machining terms) — the operator didn't give one, and guessing it
## would plant an unsourced number right next to RATED_COARSE, which IS
## doc-grounded (whole-plant mass-balance figures, this file's header). So
## this asks the question the other way round: what chip depth would have to
## be true for the knife geometry to reproduce the EXISTING 4500 kg/h figure?
## Answer, at 30 rpm: ~0.038 mm. Thin, but physically sane for shredding
## loosely-packed FILM rather than solid chunks — BaleDefs.BULK_DENSITY
## (175 kg/m^3) is mostly trapped air, so a thin solid-equivalent "bite" per
## pass corresponds to a much thicker slice of the actual loose material
## being pulled through the shear zone. Reported as a sanity check on the
## operator's knife estimate, not fed back into rated_kg_h.
static func implied_chip_depth_m(rated_kg_h_val: float = RATED_COARSE,
		rpm: float = KNIFE_ROTOR_RPM_MIN,
		bulk_density_kg_m3: float = BaleDefs.BULK_DENSITY) -> float:
	var edge_rate : float = swept_edge_rate_m_s(rpm)
	if edge_rate <= 0.0 or bulk_density_kg_m3 <= 0.0:
		return 0.0
	return (rated_kg_h_val / 3600.0) / (edge_rate * bulk_density_kg_m3)
const LOAD_TAU     : float = 0.5                 # motor-load ramp time constant

# ── Relay / operating state ──────────────────────────────────────────────────
var key_position  : int  = Key.AUTO
var running        : bool = false
var e_stop_latched : bool = false
var is_tripped     : bool = false                # motor overload latch
var is_open        : bool = false                # housing open (maintenance)
var rotor_locked   : bool = false                # SWI-033 rotor block bar fitted

# ── Live sim ─────────────────────────────────────────────────────────────────
var feed_kg_h        : float = 0.0               # commanded infeed (set by upstream)
var throughput_kg_h  : float = 0.0               # actual shredded rate out
var motor_load_pct   : float = 0.0
var buffer_kg        : float = 0.0               # material backed up in the throat/bunker
var overflow_kg      : float = 0.0               # cumulative spill (housekeeping / SCADA)
var _overload_t      : float = 0.0
var _rotors          : Array = []
var _rotors_found    : bool  = false
## 0..1 — how close the rotor(s) are to running speed. Ramped at the same
## time-constant as the rotor's own spin-up (RotatingMechanism.spin_up_s),
## but tracked locally rather than read live off the rotor node: the rotor
## ramps in `_process()` (render-rate), this sim runs in `_physics_process()`,
## and coupling throughput to a value that only advances on render frames
## would make it silently depend on whether the engine is drawing a frame —
## exactly the kind of hidden coupling Q10 (measure, don't assert) exists to
## catch. Same physical parameter (spin_up_s), same physics tick, no
## cross-callback timing dependency.
var _spin_frac       : float = 0.0

## Emitted whenever a state the relay panel / HMI cares about changes.
signal state_changed()

# =============================================================================
func _ready() -> void:
	add_to_group("shredder")
	add_to_group("placed_object")
	var pid : String = String(get_meta("placeable_id")) if has_meta("placeable_id") else "shredder_1"
	if pid == "shredder_2":
		kind = Kind.FINE
		rated_kg_h = RATED_FINE
	else:
		kind = Kind.COARSE
		rated_kg_h = RATED_COARSE

# The rotors are built as children AFTER this node is created, so find them lazily.
func _ensure_rotors() -> void:
	if _rotors_found:
		return
	_rotors_found = true
	for n in find_children("*", "", true, false):
		if n.has_meta("comp") and String(n.get_meta("comp")) == "rotor":
			_rotors.append(n)

func _is_operational() -> bool:
	return running and not e_stop_latched and not is_tripped and not is_open and not rotor_locked

func _apply_rotor_state(spinning: bool) -> void:
	for r in _rotors:
		if is_instance_valid(r) and r.has_method("set_running"):
			r.call("set_running", spinning)

## Spin-up/down time constant, sourced from the actual rotor node so a tuned
## spin_up_s there is honored here too. Falls back to RotatingMechanism's own
## default (1.2s) if no rotor was found yet (e.g. bench test before _ready).
func _rotor_spin_up_s() -> float:
	for r in _rotors:
		if is_instance_valid(r) and ("spin_up_s" in r):
			return maxf(float(r.get("spin_up_s")), 0.01)
	return 1.2

# =============================================================================
func _physics_process(delta: float) -> void:
	_ensure_rotors()
	var operational : bool = _is_operational()
	_apply_rotor_state(operational)

	# Rotor speed fraction (0 stopped, 1 up to speed) — exponential approach,
	# tau ≈ spin_up_s/3 so ~95% of the step lands at t = spin_up_s, matching
	# RotatingMechanism's own ramp shape (#C3, measured 2026-08-26: previously
	# throughput_kg_h snapped to full rate the instant `operational` went true,
	# with zero regard for whether the rotor had actually spun up).
	var spin_target : float = 1.0 if operational else 0.0
	var spin_tau : float = maxf(_rotor_spin_up_s() / 3.0, 0.01)
	_spin_frac = spin_target + (_spin_frac - spin_target) * exp(-delta / spin_tau)

	var feed_dt : float = feed_kg_h / 3600.0 * delta        # kg arriving this tick
	if operational:
		var avail : float = buffer_kg + feed_dt
		var cap_dt : float = rated_kg_h * _spin_frac / 3600.0 * delta
		var processed : float = minf(avail, cap_dt)
		buffer_kg = maxf(0.0, avail - processed)
		throughput_kg_h = (processed / delta * 3600.0) if delta > 0.0 else 0.0
		# Motor load rises with commanded feed vs rated (>100% when overfed).
		var target_load : float = clampf(feed_kg_h / rated_kg_h * 100.0, 0.0, 160.0)
		motor_load_pct = lerpf(motor_load_pct, target_load, clampf(delta / LOAD_TAU, 0.0, 1.0))
		# Sustained overload → trip the motor protection.
		if motor_load_pct >= TRIP_PCT:
			_overload_t += delta
			if _overload_t >= TRIP_TIME_S:
				_trip()
		else:
			_overload_t = maxf(0.0, _overload_t - delta)
	else:
		# Stopped/faulted: infeed backs up in the throat/bunker.
		buffer_kg += feed_dt
		throughput_kg_h = 0.0
		motor_load_pct = lerpf(motor_load_pct, 0.0, clampf(delta / LOAD_TAU, 0.0, 1.0))
		_overload_t = 0.0

	# Buffer past the bunker cap spills as overflow (housekeeping bait / SCADA).
	if buffer_kg > OVERFLOW_KG:
		overflow_kg += buffer_kg - OVERFLOW_KG
		buffer_kg = OVERFLOW_KG

# =============================================================================
# PUBLIC API (relay panel + LineFlow + tests drive these)
# =============================================================================
## Commanded infeed, kg/h — set by the upstream feed (LineFlow / feeder belt).
func set_feed_throughput(kg_h: float) -> void:
	feed_kg_h = maxf(0.0, kg_h)

## Shredded output the downstream can pull, in kg/s (LineFlow transport rate).
func throughput_kg_s() -> float:
	return throughput_kg_h / 3600.0

func start() -> void:
	# Auto-arm only in AUTO (I) or HAND (II); never while e-stopped / tripped /
	# open / rotor-locked (safety interlocks).
	if e_stop_latched or is_tripped or is_open or rotor_locked:
		return
	if key_position == Key.ONDERHOUD:
		return
	if not running:
		running = true
		state_changed.emit()

func stop() -> void:
	if running:
		running = false
		state_changed.emit()

func set_key_position(pos: int) -> void:
	pos = clampi(pos, Key.AUTO, Key.ONDERHOUD)
	if pos == key_position:
		return
	key_position = pos
	if pos == Key.ONDERHOUD:      # maintenance detent forces a stop
		running = false
	state_changed.emit()

func emergency_stop() -> void:
	e_stop_latched = true
	running = false
	state_changed.emit()

func release_estop() -> void:   # quarter-turn reset
	e_stop_latched = false
	state_changed.emit()

func _trip() -> void:
	is_tripped = true
	running = false
	_overload_t = 0.0
	state_changed.emit()

func reset_trip() -> void:
	if is_tripped:
		is_tripped = false
		state_changed.emit()

func open_housing() -> void:    # SWI-027 / SWI-040 — only sane in Onderhoud + stopped
	is_open = true
	running = false
	state_changed.emit()

func close_housing() -> void:
	is_open = false
	state_changed.emit()

func lock_rotor(v: bool) -> void:   # SWI-033 rotor block bar (LOTO for cleaning)
	rotor_locked = v
	if v:
		running = false
	state_changed.emit()

func is_running() -> bool:
	return _is_operational()

# =============================================================================
# CROSSHAIR INTERACTION (E) — the working "buttons/mechanics"
# =============================================================================
func crosshair_prompt(_p: Node3D) -> String:
	var nm : String = "Shredder 1" if kind == Kind.COARSE else "Shredder 2"
	if e_stop_latched:
		return "%s — NOODSTOP actief · reset (kwartslag) [E]" % nm
	if is_tripped:
		return "%s — motorbeveiliging GETRIPT (overbelasting) · reset [E]" % nm
	if is_open:
		return "%s — behuizing open · sluiten [E]" % nm
	if rotor_locked:
		return "%s — rotor geblokkeerd (SWI-033) · deblokkeren [E]" % nm
	if key_position == Key.ONDERHOUD:
		return "%s — ONDERHOUD · behuizing openen [E]" % nm
	if _is_operational():
		return "%s — DRAAIT · %.0f%% belasting · %.0f kg/h [E stop]" % [nm, motor_load_pct, throughput_kg_h]
	return "%s — gestopt · starten [E]" % nm

func crosshair_interact(_p: Node3D) -> void:
	if e_stop_latched:
		release_estop()
	elif is_tripped:
		reset_trip()
	elif is_open:
		close_housing()
	elif rotor_locked:
		lock_rotor(false)
	elif key_position == Key.ONDERHOUD:
		open_housing()
	elif _is_operational():
		stop()
	else:
		start()
