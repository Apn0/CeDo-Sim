extends RefCounted
class_name PelletizerModel

## Tracks 4 knives on a pelletizer cutter disc.
## NEW → FOUTIEF → BESCHADIGD with stochastic decay.
## Throughput multiplier: 1.0 - 0.05 × count_worn_knives.
## Replace requires a Maat-7 socket wrench in inventory.

enum KnifeState { NEW, FOUTIEF, BESCHADIGD }

const KNIFE_DECAY_HOURS_NEW_TO_FOUTIEF   := 80.0
const KNIFE_DECAY_HOURS_FOUTIEF_TO_BESCHADIGD := 24.0
const THROUGHPUT_PENALTY_PER_WORN := 0.05

var knife_states : Array = [KnifeState.NEW, KnifeState.NEW, KnifeState.NEW, KnifeState.NEW]
var _accum_h : Array = [0.0, 0.0, 0.0, 0.0]
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func tick(delta_s : float, running : bool) -> void:
	if not running: return
	var dh := delta_s / 3600.0
	for i in 4:
		var jitter : float = _rng.randf_range(0.85, 1.15)
		_accum_h[i] += dh * jitter
		match knife_states[i]:
			KnifeState.NEW:
				if _accum_h[i] >= KNIFE_DECAY_HOURS_NEW_TO_FOUTIEF:
					knife_states[i] = KnifeState.FOUTIEF
					_accum_h[i] = 0.0
			KnifeState.FOUTIEF:
				if _accum_h[i] >= KNIFE_DECAY_HOURS_FOUTIEF_TO_BESCHADIGD:
					knife_states[i] = KnifeState.BESCHADIGD
					_accum_h[i] = 0.0

func count_worn_knives() -> int:
	var n := 0
	for s in knife_states:
		if s != KnifeState.NEW: n += 1
	return n

func get_throughput_multiplier() -> float:
	return max(0.5, 1.0 - THROUGHPUT_PENALTY_PER_WORN * count_worn_knives())

func replace_knife(idx : int) -> bool:
	if idx < 0 or idx >= knife_states.size(): return false
	knife_states[idx] = KnifeState.NEW
	_accum_h[idx] = 0.0
	return true

func replace_all_knives() -> void:
	for i in 4:
		replace_knife(i)
