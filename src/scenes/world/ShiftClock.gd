extends Node

class_name ShiftClock

## Real-time 1:1 shift clock, 07:00 – 15:00 (8 hours).
##
## MainWorld is the single authority for calling start_shift() or
## load_shift_state() + resume_shift().  ShiftClock._ready() intentionally
## does NOT touch GameState to avoid the sibling-ordering race condition
## (ShiftClock is child[0], GameState is child[1] — GameState._ready() hasn't
## run yet when ShiftClock._ready() fires).

const SHIFT_START_HOUR  : int = 7
const SHIFT_START_MINUTE: int = 0
const SHIFT_END_HOUR    : int = 15
const SHIFT_END_MINUTE  : int = 0

var shift_elapsed_seconds: float = 0.0
var shift_total_seconds  : float = (SHIFT_END_HOUR - SHIFT_START_HOUR) * 3600.0
var shift_active         : bool  = false

# Time COMPRESSION. The clock used to run 1:1 with real time — an 8-hour shift
# took 8 REAL hours, so the display barely crept off 07:00 (and a save left at
# the end reloaded frozen at 15:00, which is the bug the operator hit). With a
# scale of 24, the 8 h window plays out in ~20 real minutes. Tunable per taste.
@export var time_scale   : float = 24.0
# When the shift reaches 15:00, auto-advance to the next WORKING day's shift
# instead of freezing. The operator asked for "proceed to the next shift / day"
# to be worked out — this is it. Set false to hold at the end (e.g. for a
# between-shift summary screen later).
@export var auto_advance : bool = false

# ── 2-2-2-4 calendar context ─────────────────────────────────────────────────
# The clock above still runs the single playable 07:00–15:00 window; these two
# fields place that window in the wider rota so the HUD/CrewManager know which
# dienst it is, which ploeg is on, and who is resting. day_index 0 / team_index 0
# (Ploeg A) lands on a Vroege dienst — coherent with the 07:00 start.
var day_index : int = 0      # absolute calendar day, 0-based
var team_index: int = 0      # the player's ploeg (0 = A … 4 = E)

# GameState reference — resolved lazily when needed for save/load.
var _game_state: GameState

signal shift_started
signal shift_ended
signal shift_rolled_over(new_day_index: int)   # auto-advanced to a new working day
signal time_updated(time_string: String)

# =============================================================================
func _ready() -> void:
	# MainWorld._start_or_resume_shift() drives the shift itself; here we only wire
	# the operator-set time-compression preference (#166) and seed the display.
	_apply_time_scale_setting()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("settings_applied"):
		sm.settings_applied.connect(_apply_time_scale_setting)
	emit_signal("time_updated", get_time_string())

## Pull the time-compression rate from the gameplay settings (#166), so the
## operator picks the shift pace. Falls back to the @export default when the
## SettingsManager autoload isn't present (e.g. a bare headless harness).
func _apply_time_scale_setting() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("gameplay"):
		time_scale = clampf(float(sm.gameplay().get("shift_time_scale", time_scale)), 1.0, 240.0)

func _physics_process(delta: float) -> void:
	if not shift_active:
		return

	# Compressed time — `time_scale` game-seconds per real second.
	shift_elapsed_seconds += delta * time_scale

	if shift_elapsed_seconds >= shift_total_seconds:
		shift_elapsed_seconds = shift_total_seconds
		emit_signal("shift_ended")
		if auto_advance:
			_roll_to_next_shift()      # → next working day, fresh 07:00 window
		else:
			shift_active = false       # hold at 15:00 (for a summary screen, etc.)

	emit_signal("time_updated", get_time_string())

## End of shift → advance the 2-2-2-4 calendar to the player ploeg's next
## WORKING day (skipping the 4-day rest block) and begin a fresh 07:00 window.
## Keeps the clock progressing day after day instead of freezing at 15:00.
func _roll_to_next_shift() -> void:
	advance_day(1)
	var guard := 0
	while is_resting_today() and guard < 14:
		advance_day(1)
		guard += 1
	shift_elapsed_seconds = 0.0
	shift_active = true
	emit_signal("shift_rolled_over", day_index)
	emit_signal("shift_started")

# =============================================================================
# CONTROL
# =============================================================================
func start_shift() -> void:
	shift_active          = true
	shift_elapsed_seconds = 0.0
	emit_signal("shift_started")

func pause_shift() -> void:
	shift_active = false

func resume_shift() -> void:
	shift_active = true

# =============================================================================
# QUERIES
# =============================================================================
func get_time_string() -> String:
	var total_s : int = int(shift_elapsed_seconds)
	# Start hour follows the DIENST (Vroege 07:00 / Late 15:00 / Nacht 23:00),
	# not a fixed 07:00 — so Day 3 (a Late dienst for Ploeg A) reads 15:00, and
	# the night shift wraps past midnight.
	var hours   : int = (shift_start_hour() + int(total_s / 3600.0)) % 24
	var minutes : int = int((total_s % 3600) / 60.0)
	return "%02d:%02d" % [hours, minutes]

## The clock start hour for the dienst this playable window represents.
func shift_start_hour() -> int:
	match current_shift():
		ShiftRota.Shift.EARLY: return 7
		ShiftRota.Shift.LATE:  return 15
		ShiftRota.Shift.NIGHT: return 23
		_:                     return 7   # rest days are skipped by the rollover

func get_elapsed_seconds() -> float:
	return shift_elapsed_seconds

func get_remaining_seconds() -> float:
	return maxf(0.0, shift_total_seconds - shift_elapsed_seconds)

func get_progress_percent() -> float:
	return shift_elapsed_seconds / shift_total_seconds

func is_in_shift() -> bool:
	return shift_active and shift_elapsed_seconds < shift_total_seconds

# =============================================================================
# CALENDAR (2-2-2-4 rota context for the played shift)
# =============================================================================
## The dienst this playable window represents, per the rota.
func current_shift() -> int:
	return ShiftRota.team_shift(team_index, day_index)

func current_shift_label() -> String:
	return ShiftRota.shift_label(current_shift())

func current_team_label() -> String:
	return ShiftRota.team_label(team_index)

## True when the player's own ploeg is on its 4-day rest block.
func is_resting_today() -> bool:
	return ShiftRota.is_resting(team_index, day_index)

## Advance the calendar (e.g. on shift_ended → next working day).
func advance_day(n: int = 1) -> void:
	day_index += maxi(0, n)

## "Dag 3 · Vroege dienst · Ploeg A" — one line for the HUD.
func calendar_string() -> String:
	return "Dag %d · %s · %s" % [day_index + 1, current_shift_label(), current_team_label()]

# =============================================================================
# SAVE / LOAD  (called by MainWorld, which already holds the GameState ref)
# =============================================================================
func save_shift_state() -> void:
	var gs := _get_game_state()
	if gs:
		gs.save_shift_state({
			"elapsed_seconds": shift_elapsed_seconds,
			"is_active":       shift_active,
			"day_index":       day_index,
			"team_index":      team_index,
		})

func load_shift_state() -> void:
	var gs := _get_game_state()
	if not gs:
		return
	var state := gs.load_shift_state()
	if state.is_empty():
		return
	shift_elapsed_seconds = state.get("elapsed_seconds", 0.0)
	day_index  = int(state.get("day_index", day_index))
	team_index = int(state.get("team_index", team_index))
	# If the saved shift had already run out, DON'T resume frozen at 15:00 (the
	# reported bug) — advance to the next working day and start fresh at 07:00.
	if shift_elapsed_seconds >= shift_total_seconds:
		advance_day(1)
		var guard := 0
		while is_resting_today() and guard < 14:
			advance_day(1)
			guard += 1
		shift_elapsed_seconds = 0.0
	# Don't restore shift_active from save — MainWorld calls resume_shift() after.

func _get_game_state() -> GameState:
	if not _game_state:
		# GameState is a sibling under MainWorld. Sibling path is timing-independent
		# (current_scene may still be null during MainWorld._ready(), when this runs).
		_game_state = get_node_or_null("../GameState") as GameState
	return _game_state
