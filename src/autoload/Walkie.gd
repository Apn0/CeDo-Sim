extends Node

## The player's two-way radio (portagofoon).
##
## Holds ONE battery, which drains only while the shift clock is running. When the
## battery goes flat the player stops hearing crew comms — the whole point of the
## charger gameplay (swap a fresh pack in at the shift-leader office, leave your
## empty to charge for whoever comes next).
##
## Audio routing models the real unit:
##   - HEADSET attached (earpiece on a cable to the right ear): comms play QUIET
##     and private — a small, close sound only the operator hears.
##   - SPEAKER (no headset): comms play LOUD out of the unit's speaker.
## A VOLUME knob (0..1) scales either route, so you can dial it so you neither get
## blasted nor miss a call.
##
## Register as autoload "Walkie". No class_name (autoload-name collision rule).
##
## This node owns only STATE + routing decisions; the actual radio blips are
## synthesised by AudioManager.play_radio_call() on the Voices bus. Keeping the
## two apart means the model is fully testable headless (no audio server needed).

## Battery is a global class (class_name Battery), but under the headless
## `--script` harness the global class registry isn't built, so we preload the
## type explicitly. In-game this resolves to the same class.
const BatteryT := preload("res://src/sim/Battery.gd")

signal battery_changed(percent: int)        # emitted when charge % (rounded) changes
signal battery_went_flat                      # emitted once when the pack dies
signal battery_swapped(old_charge: float)     # player swapped the pack at the station
signal headset_changed(attached: bool)
signal volume_changed(level: float)
signal call_received(from_name: String, text: String, heard: bool)
## Player keyed up — their own TX. `text` is the canned line that went out so
## the HUD can echo it back ("you: 'On my way'"). NPCs are not yet listeners;
## this currently exists for the audio chirp + HUD self-echo, with the canned
## message loop ready for the crew AI to subscribe to.
signal transmit_sent(text: String, heard: bool)

# ── State ─────────────────────────────────────────────────────────────────────
var battery        : BatteryT = null
var headset_on     : bool    = true     # earpiece attached by default
var volume         : float   = 0.6      # 0..1 knob position
const VOLUME_STEP  : float   = 0.1

var _shift_clock   : Node = null
var _last_percent  : int  = -1

# =============================================================================
func _ready() -> void:
	# Start with a fresh pack in the unit.
	battery = BatteryT.new(1.0, "pack_player_start")
	_last_percent = battery.percent()

## Resolve the ShiftClock lazily — it lives under MainWorld, which doesn't exist
## yet when this autoload's _ready() runs.
func _shift() -> Node:
	if _shift_clock == null or not is_instance_valid(_shift_clock):
		var scene := get_tree().current_scene
		if scene != null:
			_shift_clock = scene.find_child("ShiftClock", true, false)
	return _shift_clock

func _process(delta: float) -> void:
	# Drain only while the shift is actually running.
	var sc := _shift()
	var running := sc != null and bool(sc.get("shift_active"))
	if running and battery != null and not battery.is_flat():
		if battery.drain(delta):
			emit_signal("battery_went_flat")
		var p := battery.percent()
		if p != _last_percent:
			_last_percent = p
			emit_signal("battery_changed", p)

# =============================================================================
# BATTERY ACCESS (used by the HUD + BatteryStation)
# =============================================================================
func battery_percent() -> int:
	return battery.percent() if battery != null else 0

func battery_alive() -> bool:
	return battery != null and not battery.is_flat()

## Swap the pack currently in the walkie for `new_pack`, returning the one removed
## (which the player then carries / shelves / drops in the charger). Either may be
## null (e.g. taking the pack out to hold it).
func swap_battery(new_pack: BatteryT) -> BatteryT:
	var old := battery
	battery = new_pack
	_last_percent = battery.percent() if battery != null else -1
	emit_signal("battery_swapped", old.charge if old != null else 0.0)
	emit_signal("battery_changed", battery_percent())
	return old

# =============================================================================
# HEADSET + VOLUME (player controls)
# =============================================================================
func toggle_headset() -> void:
	headset_on = not headset_on
	emit_signal("headset_changed", headset_on)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	emit_signal("volume_changed", volume)

func volume_up() -> void:
	set_volume(volume + VOLUME_STEP)

func volume_down() -> void:
	set_volume(volume - VOLUME_STEP)

## The effective loudness (0..1) a call will play at, given the current routing.
## Headset is intimate/quiet (caps lower) but always audible; speaker is louder.
## Returns 0 when the battery is dead — nothing comes through.
func effective_loudness() -> float:
	if not battery_alive():
		return 0.0
	var route_cap := 0.55 if headset_on else 1.0
	return volume * route_cap

# =============================================================================
# INCOMING CALLS (driven by crew events — e.g. someone goes on break)
# =============================================================================
## A colleague keys up. If the battery is alive the call is HEARD (routed to
## AudioManager at the effective loudness); if dead, it's missed. Either way we
## emit call_received so the HUD can log it (and show "missed" when not heard).
func receive_call(from_name: String, text: String) -> void:
	var loud := effective_loudness()
	var heard := battery_alive()
	if heard:
		var am := get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("play_radio_call"):
			am.play_radio_call(text, loud, headset_on)   # text drives the formant voice (#163)
	emit_signal("call_received", from_name, text, heard)

# =============================================================================
# OUTGOING PTT — operator keys up to talk back to the crew
# =============================================================================
## Canned response lines, cycled by repeated PTT presses (real walkies don't
## type — the simulator picks from a short repertoire).
const PTT_LINES : Array[String] = [
	"Copy that.",
	"On my way.",
	"Need a hand here.",
	"Tank swap, give me five.",
	"Standby.",
]
var _ptt_idx : int = 0

## Operator presses PTT. Plays the uplink chirp + emits transmit_sent so the
## HUD can show "you: <line>" and any future NPC subscribers (crew AI) can
## react. Returns false if the radio is dead — your colleagues won't hear you
## either, same as in real life.
func transmit() -> bool:
	var heard := battery_alive()
	var line := PTT_LINES[_ptt_idx]
	_ptt_idx = (_ptt_idx + 1) % PTT_LINES.size()
	if heard:
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_radio_uplink"):
			am.call("play_radio_uplink", line, headset_on)   # the keyed-up line drives the voice (#163)
	emit_signal("transmit_sent", line, heard)
	return heard
