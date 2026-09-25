class_name SiloLevelSensor
extends StaticBody3D

# =============================================================================
# Silo level sensor (#A3 — operator-anecdote mechanic)
#
# Sits between the final wash stage and the compactor feed silo. Reports the
# fill level of the silo it's wired to; when the level climbs above
# HIGH_LEVEL_PCT, the sensor commands the UPSTREAM feed to throttle so the
# silo doesn't overflow into the conveyor head pulley. That throttle is the
# "governor" the elite-run operator (per the transcript) bypassed by
# bridging the wire so the silo NEVER signalled "full" — unthrottled feed,
# higher throughput, at the cost of catastrophic blockage if you over-feed.
#
# The bypass is the WHOLE mechanic. Without the option to bridge, this is
# just a passive level reading. WITH it, the operator gets a tunable risk
# knob the manual explicitly disallows.
#
# Interaction (E on the sensor):
#   * Normal mode → bridge it (with an obvious safety prompt).
#   * Bridged mode → un-bridge it (restore the governor).
#
# UPSTREAM WIRING (LineFlow consumes this per-tick):
#   `effective_feed_multiplier()` returns a scalar the upstream feed multiplies
#   into the parcel it would otherwise inject into THIS silo's input. Three
#   regimes:
#     * 0.0  → governor active (level above HIGH_LEVEL_PCT, not bridged). The
#              upstream feed parks its parcel in its own out-batch this tick;
#              material is NOT destroyed — it backs up at the source, exactly
#              like the real PLC interlock that closes the metering damper.
#     * 1.0  → normal cruise. Upstream feeds the silo at its rated rate.
#     * 1.5  → BRIDGED + still below LEVEL_OVERFLOW_PCT. Upstream is permitted
#              to push 1.5× rated rate into the silo, the "remove the governor"
#              anecdote (a bridged sensor never says full, so the wash-line PLC
#              keeps the metering damper wide open and the head conveyor floods
#              the silo). Capped at 1.5× because the upstream wash line itself
#              has a hard mechanical max; bridging removes the SOFT throttle,
#              not the physics of the conveyors above.
#   Once bridged AND past LEVEL_OVERFLOW_PCT the multiplier drops back to 1.0:
#   the silo has overflowed, surge gained nothing more, downstream consequences
#   take over (silo_overflow signal + the silo placeable's own spill code).
#
# Upstream feed scripts call `wants_throttle()` to know whether to clamp
# their output. A bridged sensor always returns false — the silo can climb
# to LEVEL_OVERFLOW_PCT, at which point a separate overflow event fires
# (handled here, but the visual + downstream consequences live in the
# silo placeable's existing code).
# =============================================================================

# ── Tunables ─────────────────────────────────────────────────────────────────
const HIGH_LEVEL_PCT       : float = 0.85      # throttle upstream above this
const RESUME_LEVEL_PCT     : float = 0.70      # hysteresis: un-throttle below this
const LEVEL_OVERFLOW_PCT   : float = 1.02      # 2 % over-rated = overflow event
const BRIDGE_HOLD_HINT_S   : float = 0.6       # how long the bridge prompt waits
# Bridged surge ceiling — operator anecdote ("the wire was the governor; we
# took it out and ran the line wide open"). NOT infinite: the upstream wash
# line, the head conveyor and the metering damper still have their own
# mechanical maxes, so the effective surge tops out at this multiple of rated.
const SURGE_MULTIPLIER     : float = 1.5

signal level_throttle_changed(throttling: bool)
signal silo_overflow(silo_path: NodePath)
signal sensor_bridged_changed(bridged: bool)

# ── Live state ───────────────────────────────────────────────────────────────
@export var silo_path : NodePath                # the silo whose level we read
@export var sensor_label : String = "VW1.LT01"  # cosmetic — shown in the HMI

var bridged              : bool  = false
var _throttling          : bool  = false       # current throttle state (hysteresis)
var _silo                : Node3D = null
var _last_level          : float = 0.0
var _last_overflow_at_s  : float = -1.0

# =============================================================================
func _ready() -> void:
	add_to_group("silo_level_sensor")
	if silo_path:
		_silo = get_node_or_null(silo_path) as Node3D

func _physics_process(_delta: float) -> void:
	if _silo == null or not is_instance_valid(_silo):
		# Silo might spawn after us — try to resolve from path lazily.
		if silo_path:
			_silo = get_node_or_null(silo_path) as Node3D
		if _silo == null:
			return
	# Read the silo level. Convention: silo exposes `level_pct` (0..1) as a
	# property or method. Falls back to 0 if neither is present.
	var lvl : float = 0.0
	if "level_pct" in _silo:
		lvl = float(_silo.get("level_pct"))
	elif _silo.has_method("level_pct"):
		lvl = float(_silo.call("level_pct"))
	_last_level = clampf(lvl, 0.0, 2.0)
	# Bridged sensor → silently always-not-throttling, regardless of level.
	# Real silo can climb past 100 % and overflow; that's the mechanic.
	if bridged:
		if _throttling:
			_throttling = false
			level_throttle_changed.emit(false)
		if _last_level >= LEVEL_OVERFLOW_PCT:
			silo_overflow.emit(silo_path)
		return
	# Normal mode with hysteresis.
	if not _throttling and _last_level >= HIGH_LEVEL_PCT:
		_throttling = true
		level_throttle_changed.emit(true)
	elif _throttling and _last_level <= RESUME_LEVEL_PCT:
		_throttling = false
		level_throttle_changed.emit(false)

# =============================================================================
# PUBLIC API — upstream feed scripts read this each tick
# =============================================================================
func wants_throttle() -> bool:
	# Bridged sensor never signals throttle. Otherwise track the level state.
	return _throttling and not bridged

func current_level_pct() -> float:
	return _last_level

## Surge ceiling cap a sensor exposes when bridged. Read by upstream wiring
## so the surge value lives with the sensor's tunables (one knob, one site).
func surge_ceiling() -> float:
	return SURGE_MULTIPLIER

## The scalar the upstream feed multiplies into the parcel it would otherwise
## inject into THIS silo this tick. See the top-of-file UPSTREAM WIRING block
## for the full regime table; in short:
##   * Throttle active (governor live + level high) → 0.0   (feed parks at source)
##   * Bridged + below overflow                     → SURGE_MULTIPLIER (1.5× rated)
##   * Bridged + at/past overflow                   → 1.0   (cap; spill takes over)
##   * Normal cruise (no throttle, not bridged)     → 1.0
## Called by LineFlow per tick on the destination side of each edge whose
## downstream is the silo this sensor reports for.
func effective_feed_multiplier() -> float:
	if wants_throttle():
		return 0.0          # governor live — close the damper
	if bridged and _last_level < LEVEL_OVERFLOW_PCT:
		return SURGE_MULTIPLIER
	return 1.0

## Resolve the silo Node3D this sensor reports for. LineFlow uses this to
## build the per-rebuild lookup (target node → sensor) without each silo
## having to know its sensor — the SENSOR knows its silo (silo_path).
func target_silo() -> Node3D:
	if _silo != null and is_instance_valid(_silo):
		return _silo
	if silo_path:
		_silo = get_node_or_null(silo_path) as Node3D
	return _silo

# =============================================================================
# CROSSHAIR INTERACTION  (operator E)
# =============================================================================
func crosshair_prompt(_p: Node3D) -> String:
	if bridged:
		return "%s — gebrugd · niveau %.0f %% [E ontbruggen]" % \
			[sensor_label, _last_level * 100.0]
	return "%s — niveau %.0f %% [E overbruggen — WAARSCHUWING]" % \
		[sensor_label, _last_level * 100.0]

## Resume on load (operator 2026-09-25, rulings file §R1-§R3;
## src/sim/PlantResume.gd): a bridged sensor stays bridged (the operator's
## own act), and the throttle holds its hysteresis side.
func save_run_state() -> Dictionary:
	if not bridged and not _throttling:
		return {}
	return {"bridged": bridged, "_throttling": _throttling}

func restore_run_state(d: Dictionary) -> void:
	bridged = bool(d.get("bridged", false))
	_throttling = bool(d.get("_throttling", false))

func crosshair_interact(_p: Node3D) -> void:
	bridged = not bridged
	sensor_bridged_changed.emit(bridged)
	# Bridging mid-throttle: drop the throttle signal immediately so upstream
	# unclamps on the next tick.
	if bridged and _throttling:
		_throttling = false
		level_throttle_changed.emit(false)
