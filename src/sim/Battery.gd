extends RefCounted
class_name Battery

## A single walkie-talkie battery pack.
##
## A real pack lasts the crew about four-and-a-half full working days. One playable
## shift is 8 h = 28 800 s, so a full pack holds ~4.5 × 28 800 = 129 600 "shift-
## seconds" of talk-time. Charging is much faster than draining — empty → full in
## about four hours of shift time (one charger, see BatteryStation) — which is what
## makes the single charger a shared resource worth managing.
##
## charge is normalised 0.0 (flat) … 1.0 (full). All progression happens in
## shift-seconds so it only advances while the shift clock is running (pausing the
## shift pauses the drain — you're not on the clock).

## Full-pack life, in shift-seconds (~4.5 eight-hour shifts).
const LIFE_SECONDS   : float = 129_600.0
## Empty → full on the charger, in shift-seconds (~4 hours).
const CHARGE_SECONDS : float = 14_400.0

var id     : String = ""
var charge : float  = 1.0      # 0..1

func _init(start_charge: float = 1.0, pack_id: String = "") -> void:
	charge = clampf(start_charge, 0.0, 1.0)
	id = pack_id

## Drain while in use. `secs` is elapsed shift-seconds. Returns true if the pack
## JUST went flat on this call (so the caller can fire a "battery dead" event once).
func drain(secs: float) -> bool:
	if charge <= 0.0:
		return false
	var before := charge
	charge = maxf(0.0, charge - secs / LIFE_SECONDS)
	return before > 0.0 and charge <= 0.0

## Charge while sitting in the charger. `secs` is elapsed shift-seconds. Returns
## true if the pack JUST reached full on this call.
func top_up(secs: float) -> bool:
	if charge >= 1.0:
		return false
	var before := charge
	charge = minf(1.0, charge + secs / CHARGE_SECONDS)
	return before < 1.0 and charge >= 1.0

func is_flat() -> bool:
	return charge <= 0.001

func is_full() -> bool:
	return charge >= 0.999

func percent() -> int:
	return int(round(charge * 100.0))

## Estimated remaining talk-time in whole shift-hours, for the HUD tooltip.
func hours_left() -> float:
	return charge * LIFE_SECONDS / 3600.0
