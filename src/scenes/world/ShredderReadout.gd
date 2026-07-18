extends Label3D
## Live readout for a ShredderMachine — floats above the gauntlet shredder test
## stage and prints the sim state each frame (state · feed → output · motor load ·
## buffer · overflow) so the operator can watch the throughput physics + trip
## behaviour without opening a debugger.
var target : Node = null

func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var state : String = "gestopt"
	if bool(target.get("e_stop_latched")):
		state = "NOODSTOP"
	elif bool(target.get("is_tripped")):
		state = "GETRIPT — overbelasting"
	elif bool(target.call("is_running")):
		state = "DRAAIT"
	text = "SHREDDER · %s\nfeed %.0f -> out %.0f kg/h · load %.0f%%\nbuffer %.0f kg · overflow %.0f kg" % [
		state,
		float(target.get("feed_kg_h")), float(target.get("throughput_kg_h")),
		float(target.get("motor_load_pct")), float(target.get("buffer_kg")),
		float(target.get("overflow_kg"))]
