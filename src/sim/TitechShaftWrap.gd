extends RefCounted
class_name TitechShaftWrap

## Tracks fibrous wrap accumulation on a TITECH/TOMRA shaft.
## Wrap grows with fiber throughput; trip threshold causes throughput penalty.
## Wire cutter or knife interaction removes wrap.

const WRAP_GROWTH_G_PER_KG := 0.018
const TRIP_WRAP_G := 350.0
const FULL_WRAP_G := 800.0

var wrap_g : float = 0.0

func tick(delta_s : float, throughput_kg_s : float) -> void:
	wrap_g += WRAP_GROWTH_G_PER_KG * throughput_kg_s * delta_s

func is_tripping() -> bool:
	return wrap_g >= TRIP_WRAP_G

func throughput_multiplier() -> float:
	if wrap_g < TRIP_WRAP_G: return 1.0
	var x : float = clampf((wrap_g - TRIP_WRAP_G) / (FULL_WRAP_G - TRIP_WRAP_G), 0.0, 1.0)
	return clampf(1.0 - 0.5 * x, 0.5, 1.0)

func cut_wrap(reduce_g : float = 250.0) -> float:
	var removed : float = minf(wrap_g, reduce_g)
	wrap_g -= removed
	return removed

func reset() -> void:
	wrap_g = 0.0
