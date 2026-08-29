extends RefCounted
class_name MotorOverload

## The "pack-up" cascade: paddle/rotor load → motor amp spike → overload TRIP.
##
## A reusable, self-contained motor-protection model that a shredder, compactor,
## paddle washer, or any driven rotor COMPOSES (has-a, not is-a). It is a plain
## RefCounted with a manually-driven tick(delta), so it carries no scene-tree or
## frame-rate dependency and a headless test can step it with a FIXED delta — the
## same deterministic pattern LineFlow.tick() / CrewManager.tick() use.
##
## ── THE PHYSICS IT MODELS ──────────────────────────────────────────────────────
## When the downstream can't take material, it piles up on the paddle/rotor:
## `accumulated_kg` climbs. A real induction motor answers a rising mechanical
## load by drawing more current — gently at first, then steeply as the rotor
## starts to bind and slip toward stall, where it pulls its LOCKED-ROTOR current
## (multiples of nominal). We reproduce that curve:
##
##   load_ratio = accumulated_kg / load_capacity_kg           (0 = empty)
##   • 0 .. 1    amps ramp idle_floor → nominal_amps          (normal duty band)
##   • 1 .. 2    amps ramp nominal_amps → locked_rotor_amps   (binding → stall)
##
## A motor-overload relay does NOT trip on a momentary spike — it trips when the
## current stays over the trip_threshold for a SUSTAINED time (thermal inertia).
## So we run an overload TIMER: it accrues delta while amps > trip_threshold and
## RESETS the instant they fall back under it. When it reaches trip_delay → TRIP:
## the motor stops (is_tripped() == true, amps → 0). It stays latched until a
## human reset()s it, exactly like a real thermal-overload / motor-protection trip.
##
## ── COMPOSITION CONTRACT (see REGISTRATION in the task report) ──────────────────
## The owning machine each tick:
##   1. add_load(backlog_kg)   — material it could NOT pass downstream this tick
##   2. relieve(moved_kg)      — material that DID flow on (downstream took it)
##   3. tick(delta)            — advances amps + the overload timer, may TRIP
##   4. on trip: stop conveying (read is_tripped()); the `tripped` signal /
##      EventBus "MOTOR-OVERLOAD" alarm fire once on the leading edge.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
## Full-load running current of a healthy motor at its rated throughput (A).
var nominal_amps      : float = 90.0
## Stall / locked-rotor current (A) — what the motor pulls when the rotor binds
## solid. Real induction motors: ~5–8× full-load; we keep it tunable per drive.
var locked_rotor_amps : float = 480.0
## Current (A) above which the overload relay starts its trip clock. Sits above
## nominal (normal running must not trip) and below locked-rotor.
var trip_threshold    : float = 180.0
## Seconds the current must stay over trip_threshold, CONTINUOUSLY, before the
## relay trips. Models the thermal inertia of a real overload element.
var trip_delay        : float = 3.0
## accumulated_kg at which the rotor is considered fully bound (load_ratio = 1.0,
## amps = nominal). Beyond 2× this the load curve saturates at locked_rotor_amps.
var load_capacity_kg  : float = 120.0
## Fraction of nominal_amps a spinning-but-unloaded motor still draws (magnetising
## + friction + windage). Mirrors ProcessModel.MOTOR_IDLE_FRAC for consistency.
var idle_frac         : float = 0.35
## Identifier reported on the `tripped` signal + EventBus alarm (set by the owner
## so the HMI knows WHICH drive packed up, e.g. "shredder_3a").
var machine_id        : String = "motor"

# ── LIVE STATE (read-only to callers) ─────────────────────────────────────────
## Material currently piled on the paddle/rotor (kg). Never negative.
var accumulated_kg : float = 0.0
## Live motor current (A), recomputed every tick from load + run state.
var current_amps   : float = 0.0
## True while the motor is powered (spinning). A trip forces this false; reset()
## restores it. The owner may also set it directly via set_running() (E-stop, PLC).
var running        : bool  = true

var _tripped         : bool  = false
## Accrued seconds the current has been continuously over trip_threshold.
var _overload_timer  : float = 0.0

## Emitted ONCE on the leading edge of a trip. (id, peak_amps_at_trip)
signal tripped(id: String, amps: float)
## Emitted ONCE when reset() clears a latched trip.
signal reset_done(id: String)

# =============================================================================
# CONSTRUCTION
# =============================================================================
## Optional ctor sugar so an owner can spin one up in a single line and still
## read clearly: MotorOverload.new("shredder_3a", 90.0, 480.0, 180.0, 3.0).
## All args have sensible defaults; pass only what differs from the field values.
func _init(id: String = "motor", nominal: float = 90.0, locked_rotor: float = 480.0,
		threshold: float = 180.0, delay: float = 3.0, capacity_kg: float = 120.0) -> void:
	machine_id        = id
	nominal_amps      = nominal
	locked_rotor_amps = locked_rotor
	trip_threshold    = threshold
	trip_delay        = delay
	load_capacity_kg  = capacity_kg
	current_amps      = 0.0

# =============================================================================
# LOAD ACCOUNTING  (owner drives these each tick)
# =============================================================================
## Pile `kg` of un-passed material onto the rotor (downstream couldn't take it).
## Negative / zero is ignored so callers can pass a raw backlog without guarding.
func add_load(kg: float) -> void:
	if kg <= 0.0:
		return
	accumulated_kg += kg

## Relieve `kg` of load — material that DID flow on, or that a human cleared by
## hand. Clamped at zero (you can't un-pile more than is there).
func relieve(kg: float) -> void:
	if kg <= 0.0:
		return
	accumulated_kg = maxf(0.0, accumulated_kg - kg)

## Set the pile directly to `kg` — for an owner that already tracks the STOCK
## itself (e.g. a MaterialBatch buffer) and just wants the motor model to
## mirror it, rather than emitting separate arrived/departed events.
##
## 2026-08-29 bug fix: LineFlow.gd used to call
## `add_load(_backlog_kg); relieve(_moved_kg)` every tick, where `_backlog_kg`
## is the node's CURRENT buffer level (a stock), not a one-off inflow event. A
## stock re-added on top of itself every tick — instead of replacing the
## previous tick's value — accumulates without bound even while the buffer
## sits perfectly steady: a machine comfortably keeping up with a small,
## stable queue (buffer near-constant, genuinely fine) still raced from idle
## to a full trip in ~10 s of sim time, because the same few kg got counted
## as "new load" again and again. Measured on line 1's mill: buffer stayed
## under 7 kg throughout, current_amps still hit the 450 A locked-rotor cap.
## `set_load` is the correct operation for a stock-tracking caller: it
## naturally settles to a steady load_ratio when inflow ≈ outflow, and only
## climbs when the buffer itself is genuinely growing — a real overload.
func set_load(kg: float) -> void:
	accumulated_kg = maxf(0.0, kg)

## Mechanical load as a fraction of the binding point (0 = empty, 1 = fully
## loaded/nominal, >1 = overloaded toward stall).
func load_ratio() -> float:
	if load_capacity_kg <= 0.0:
		return 0.0
	return accumulated_kg / load_capacity_kg

# =============================================================================
# TICK  (deterministic — inject delta manually)
# =============================================================================
## Advance the motor one step: recompute amps from the current load, then run the
## sustained-overload trip clock. Safe to call after a trip (amps stay 0, the clock
## stays parked) so the owner can keep ticking without special-casing the trip.
func tick(delta: float) -> void:
	delta = maxf(delta, 0.0)
	current_amps = _amps_for_load()
	if _tripped or not running:
		_overload_timer = 0.0
		return
	# Sustained-overload relay: accrue time only while over threshold; any dip
	# back under it resets the clock (a brief spike must NOT trip).
	if current_amps > trip_threshold:
		_overload_timer += delta
		if _overload_timer >= trip_delay:
			_do_trip()
	else:
		_overload_timer = 0.0

## The amp curve described in the header: idle → nominal over the normal band,
## then nominal → locked-rotor as the rotor binds past full load. Zero when the
## motor isn't turning (stopped / tripped draws no running current).
func _amps_for_load() -> float:
	if not running or _tripped:
		return 0.0
	var idle := nominal_amps * idle_frac
	var r := load_ratio()
	if r <= 1.0:
		# Normal duty: idle floor up to full-load nominal at the binding point.
		return idle + (nominal_amps - idle) * clampf(r, 0.0, 1.0)
	# Overloaded: ramp from nominal toward locked-rotor over the next 1.0 of ratio,
	# then saturate (a fully stalled rotor can't pull more than locked-rotor).
	return nominal_amps + (locked_rotor_amps - nominal_amps) * clampf(r - 1.0, 0.0, 1.0)

# =============================================================================
# TRIP / RESET
# =============================================================================
func is_tripped() -> bool:
	return _tripped

## Seconds remaining before a trip at the present draw, or -1.0 when the current
## is under threshold (no trip pending). Handy for an HMI "TRIP IN 1.2 s" warning.
func time_to_trip() -> float:
	if _tripped or current_amps <= trip_threshold:
		return -1.0
	return maxf(0.0, trip_delay - _overload_timer)

## Latch the trip: cut the motor, zero the current, fire the one-shot signal +
## an EventBus alarm (severity 3). Private — only the sustained-overload path or
## an explicit owner force_trip() reaches it.
func _do_trip() -> void:
	if _tripped:
		return
	var peak := current_amps
	_tripped = true
	running  = false
	current_amps = 0.0
	_overload_timer = 0.0
	tripped.emit(machine_id, peak)
	_emit_bus_alarm_raised(peak)

## Owner-facing manual trip (e.g. an interlock or a hand E-stop) — same latch as
## a sustained overload, so downstream wiring treats both identically.
func force_trip() -> void:
	_do_trip()

## Clear a latched trip and re-energise the motor. The load itself is NOT cleared
## here (the jam may still be physically present) — pass clear_load=true to also
## empty the rotor, e.g. after a human has dug the pack-up out by hand.
func reset(clear_load: bool = false) -> void:
	if clear_load:
		accumulated_kg = 0.0
	_overload_timer = 0.0
	if not _tripped:
		# Not tripped — just (re)energise + recompute, no clear alarm to send.
		running = true
		current_amps = _amps_for_load()
		return
	_tripped = false
	running  = true
	current_amps = _amps_for_load()
	reset_done.emit(machine_id)
	_emit_bus_alarm_cleared()

## Direct run/stop control for the owner (PLC power-down, line E-stop). A stopped
## motor draws no current and accrues no trip time; it does NOT clear a latch.
func set_running(v: bool) -> void:
	running = v
	if not v:
		_overload_timer = 0.0
		current_amps = 0.0
	else:
		current_amps = _amps_for_load()

# =============================================================================
# EVENTBUS BRIDGE
# Optional: if an EventBus autoload with the standard machine-alarm signals is
# present we mirror the trip onto it (so the HUD siren / alarm log react like
# they do for the extruder + the LineFlow E-stop). Fully guarded so the component
# still works headless / in a unit test with no autoload registered.
# =============================================================================
const ALARM_ID := "MOTOR-OVERLOAD"

func _event_bus() -> Node:
	# A RefCounted has no tree; reach the autoload through the main loop's root.
	var loop := Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("/root/EventBus")
	return null

func _emit_bus_alarm_raised(peak_amps: float) -> void:
	var bus := _event_bus()
	if bus != null and bus.has_signal("machine_alarm_raised"):
		bus.emit_signal("machine_alarm_raised", machine_id, ALARM_ID, 3)
	print("[MotorOverload] TRIP '%s' — overload held %.1fs, peak %.0f A (limit %.0f A). Motor stopped." \
		% [machine_id, trip_delay, peak_amps, trip_threshold])

func _emit_bus_alarm_cleared() -> void:
	var bus := _event_bus()
	if bus != null and bus.has_signal("machine_alarm_cleared"):
		bus.emit_signal("machine_alarm_cleared", machine_id, ALARM_ID)
	print("[MotorOverload] RESET '%s' — overload cleared, motor re-energised." % machine_id)
