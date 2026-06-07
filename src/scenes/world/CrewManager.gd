extends Node
class_name CrewManager

## Turns the named crew into a working shift team (Wave 4).
##
## Each on-duty NPC is posted at the machine its role covers. Every tick the
## manager reads LineFlow's live buffer telemetry; when a machine jams (its input
## backs up past JAM_KG — the same threshold the HMI raises BUF-300 at) it sends
## the nearest AVAILABLE worker whose zone covers that machine to walk over and
## clear it. Servicing relieves the backlog (RELIEF_KG moved input→output, which
## is ledger-neutral for LineFlow) so the alarm clears — the crew literally keep
## the line alive.
##
## Breaks create the tension the sim is about: one postable worker at a time
## rotates off to the canteen (MAX_ON_BREAK). While their post is empty, a jam
## there has no owner and festers until they return or a floater (shift leader,
## all-rounder) covers — "team survival, not optimisation".
##
## The brain is advanced through tick(delta) (called from _physics_process in the
## game, and directly from the headless test), and it drives each NPC through
## NPC.step_brain(), so none of the coordination logic depends on the physics
## server actually stepping — it is fully deterministic and testable headless.

# ── Tunables ──────────────────────────────────────────────────────────────────
const JAM_KG         : float = 120.0   # buffer backlog that counts as a jam (== HMI BUF-300)
const RELIEF_KG      : float = 95.0     # backlog a single service clears (drops below JAM_KG)
const SERVICE_SECS   : float = 4.0      # dwell at the machine to clear it
const BREAK_INTERVAL : float = 150.0    # gap between sending crew on break
const BREAK_DURATION : float = 30.0     # how long a break lasts (counted once at the canteen)
const MAX_ON_BREAK   : int   = 1        # only ever one post unmanned at a time

# Which machines each role is responsible for (matched as id substrings).
const ZONES : Dictionary = {
	"extruder_op":      ["extruder", "mengsilo", "compactor", "mas_bak"],
	"permanent_feeder": ["bunker", "shredder", "inclined_belt", "feed_hopper",
						  "sga", "metal_belt", "ballistic", "wind_sifter", "titech"],
	"feeder":           ["bunker", "shredder", "inclined_belt", "feed_hopper"],
	"all_rounder":      ["prewash", "friction", "intensive", "flotation", "rotation",
						  "kufferath", "rafter", "dewater", "mech_dryer", "centrifuge"],
	"transitional":     ["feed_hopper", "prewash", "mengsilo"],
}
# Roles that roam centrally and may respond ANYWHERE as cover (no fixed post).
const FLOATERS : Array[String] = ["shift_leader", "asst_shift_leader",
								  "production_manager", "all_rounder"]

# ── Injected dependencies ─────────────────────────────────────────────────────
var workers       : Array   = []          # Array[NPC]
var line_flow     : Node    = null         # LineFlow (read _nodes telemetry)
var shift_clock   : Node    = null         # ShiftClock (calendar context)
var break_room_pos: Vector3 = Vector3.ZERO
var enabled       : bool    = true

# ── Runtime state ─────────────────────────────────────────────────────────────
var _handling   : Dictionary = {}   # station_id -> NPC currently clearing it
var _break_until: Dictionary = {}   # NPC -> seconds of break remaining
var _break_timer: float      = BREAK_INTERVAL
var _break_rotation_idx: int = 0    # round-robin cursor so breaks ROTATE across crew
var _pinned     : Dictionary = {}   # NPC -> station_id the OPERATOR pinned by hand (overrides auto-post)

# EventBus is an autoload at runtime, but autoloads aren't registered as global
# identifiers when this script is compiled inside the headless harness. Resolve it
# dynamically (in-game → /root/EventBus; headless → stays null) so the coordination
# logic compiles and runs either way, and event broadcasts are simply best-effort.
var _bus         : Node = null
var _bus_resolved: bool = false

# =============================================================================
func _physics_process(delta: float) -> void:
	if enabled:
		tick(delta)

## Wire the crew up and post everyone. `npc_dict` is MainWorld.npcs (id -> NPC).
func setup(npc_dict: Dictionary, lf: Node, sc: Node, break_pos: Vector3) -> void:
	workers.clear()
	for k in npc_dict:
		var n = npc_dict[k]
		if n is NPC:
			workers.append(n)
	line_flow      = lf
	shift_clock    = sc
	break_room_pos = break_pos
	assign_posts()

# =============================================================================
# POSTING
# =============================================================================
func assign_posts() -> void:
	var machines := _machine_list()
	var centre   := _avg_pos(machines)
	for w in workers:
		if _pinned.has(w):
			continue   # operator assigned this one by hand — leave their post alone
		var best : Dictionary = _nearest_in_zone(w.npc_role, w.global_position, machines)
		var sid  : String  = ""
		var pos  : Vector3 = w.global_position
		if best.is_empty():
			# No machine in this role's zone — floaters roam the line centre,
			# everyone else just holds their spawn spot.
			if _is_floater(w) and not machines.is_empty():
				pos = centre
				sid = "(rondgang)"
		else:
			sid = String(best["id"])
			pos = best["pos"]
		pos.y = w.global_position.y      # keep them on the floor
		w.assign_post(sid, pos)

# =============================================================================
# MAIN LOOP
# =============================================================================
func tick(delta: float) -> void:
	if workers.is_empty():
		return

	# 1) Advance every worker's brain. When one finishes servicing a jam, apply
	#    the world effect (relieve the backlog) and clear the alarm.
	for w in workers:
		var done : String = w.step_brain(delta)
		if done != "":
			_relieve(_node_by_id(done))
			_handling.erase(done)
			_emit("npc_finished_helping", [String(w.npc_name), "", done, true])
			_emit("machine_alarm_cleared", [done, "BUF-300"])

	# 2) Dispatch the nearest available responder to the worst un-handled jam.
	var jam := _worst_jam()
	if not jam.is_empty() and not _handling.has(jam["id"]):
		var sid : String  = String(jam["id"])
		var pos : Vector3 = _node_pos(jam["node"])
		var resp : NPC = _pick_responder(sid, pos)
		if resp != null:
			resp.dispatch_to(pos, sid, SERVICE_SECS)
			_handling[sid] = resp
			_emit("npc_called_for_help", ["crew", String(resp.npc_name), sid])
			_emit("npc_started_helping", [String(resp.npc_name), "", sid])
			_emit("machine_alarm_raised", [sid, "BUF-300", 2])
		# else: nobody free — the jam festers (the break-time tension).

	# 2b) Dispatch on FULL WASTE BIN — a skip/bay over its safe_fill is just as
	#     urgent as a machine jam (the chute backs up, the line stalls). We use
	#     the same _handling dict so a bin isn't double-claimed.
	_dispatch_for_full_bin()

	# 3) Rotate breaks — at most one post unmanned at a time.
	_update_breaks(delta)

func _update_breaks(delta: float) -> void:
	# Count down workers who have actually reached the canteen; send them back.
	for w in _break_until.keys():
		if not is_instance_valid(w):
			_break_until.erase(w)
			continue
		if w.is_on_break():
			_break_until[w] = float(_break_until[w]) - delta
			if float(_break_until[w]) <= 0.0:
				w.return_to_post()
				_break_until.erase(w)

	# Schedule a new break when due and capacity allows.
	_break_timer -= delta
	if _break_timer <= 0.0 and _break_until.size() < MAX_ON_BREAK:
		var cand := _break_candidate()
		if cand != null:
			cand.go_on_break(break_room_pos)
			_break_until[cand] = BREAK_DURATION
			_break_timer = BREAK_INTERVAL
			# Radio it in — the crew keys up the walkie when they step off post.
			_radio_break_call(cand)
		else:
			_break_timer = 5.0          # nobody free right now — try again soon

## Find the most-overfull WasteContainer (skip / bay / etc.) and dispatch a free
## worker to it. The "service" here is conceptual — the worker walks over and
## stands by; later the forklift step would do the actual empty(). The dispatch
## is mass-action-style: we treat any over-safe-fill bin as needing attention,
## prioritising the one furthest past its threshold.
func _dispatch_for_full_bin() -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var worst : Node = null
	var worst_frac := 0.85   # only act past safe-fill
	for c in (ml as SceneTree).get_nodes_in_group("waste_container"):
		if c == null or not c.has_method("fill_fraction"):
			continue
		var f : float = c.call("fill_fraction")
		if f <= worst_frac:
			continue
		var bin_key := "bin_%d" % (c as Object).get_instance_id()
		if _handling.has(bin_key):
			continue          # already being attended to this round
		worst_frac = f
		worst = c
	if worst == null:
		return
	var pos := (worst as Node3D).global_position
	var resp : NPC = _pick_responder("waste_bin", pos)
	if resp == null:
		return     # nobody free — the bin festers (will be retried next tick)
	resp.dispatch_to(pos, "waste_bin", SERVICE_SECS)
	var key := "bin_%d" % (worst as Object).get_instance_id()
	_handling[key] = resp
	_emit("npc_called_for_help", ["crew", String(resp.npc_name), "waste_bin"])
	_emit("npc_started_helping", [String(resp.npc_name), "", "waste_bin"])

## A colleague announces their break over the two-way radio. Routed through the
## Walkie autoload, which decides if the player actually HEARS it (battery alive,
## headset/speaker, volume). Best-effort: silently does nothing in the headless
## harness where the autoload isn't present.
func _radio_break_call(worker) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var walkie := (ml as SceneTree).root.get_node_or_null("Walkie")
	if walkie == null or not walkie.has_method("receive_call"):
		return
	var nm := String(worker.npc_name)
	walkie.receive_call(nm, "%s hier — ik ga even pauzeren." % nm)

## Resolve the EventBus autoload lazily (cached). Returns null when it isn't present
## (e.g. the headless harness), in which case event broadcasts are skipped.
func _event_bus() -> Node:
	if not _bus_resolved:
		_bus_resolved = true
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			_bus = (ml as SceneTree).root.get_node_or_null("EventBus")
	return _bus

## Best-effort signal broadcast: emits on EventBus when it exists, no-op otherwise.
func _emit(sig: String, args: Array) -> void:
	var bus := _event_bus()
	if bus != null and bus.has_signal(sig):
		bus.callv("emit_signal", [sig] + args)

# =============================================================================
# JAM HANDLING
# =============================================================================
## The single worst jammed machine (buffer past JAM_KG), or {} if the line is clear.
func _worst_jam() -> Dictionary:
	if not _has_nodes():
		return {}
	var worst := JAM_KG
	var found : Dictionary = {}
	for nd in line_flow._nodes:
		var buf := float(nd.get("buffer", 0.0))
		if buf > worst:
			worst = buf
			found = nd
	if found.is_empty():
		return {}
	return {"id": String(found.get("id", "")), "node": found, "buffer": worst}

## Clear a backlog: move RELIEF_KG from the machine's input to its output. This is
## ledger-neutral for LineFlow (in-transit total is unchanged) — it just represents
## the operator unchoking the machine so material flows on again.
func _relieve(nd: Dictionary) -> void:
	if nd.is_empty():
		return
	var bin  = nd.get("in", null)
	var bout = nd.get("out", null)
	if bin == null or bout == null:
		return
	var take := minf(RELIEF_KG, float(bin.mass_kg))
	if take <= 0.0:
		return
	var moved = bin.split_mass(take)
	bout.add(moved)
	nd["buffer"] = bin.mass_kg

## Prefer a free worker whose zone owns the machine; then a free floater; then
## simply the nearest free worker. Returns null when the whole crew is busy/away.
func _pick_responder(station_id: String, pos: Vector3) -> NPC:
	# Tier 1 — a free worker whose zone owns this machine.
	var best : NPC = null
	var best_d := INF
	for w in workers:
		if w.is_available() and _covers(w, station_id):
			var d: float = w.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = w
	if best != null:
		return best
	# Tier 2 — a free floater (shift leader / all-rounder) covering the gap.
	best_d = INF
	for w in workers:
		if w.is_available() and _is_floater(w):
			var d: float = w.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = w
	if best != null:
		return best
	# Tier 3 — any free hand at all.
	best_d = INF
	for w in workers:
		if w.is_available():
			var d: float = w.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = w
	return best

func _break_candidate() -> NPC:
	# Round-robin: start scanning from the rotation cursor so the SAME worker
	# isn't picked every time (the "Romero is always on break" bug). The first
	# available, non-floater worker from the cursor onward goes, and the cursor
	# advances past them for next time.
	var n := workers.size()
	for k in n:
		var w : NPC = workers[(_break_rotation_idx + k) % n]
		if w.is_available() and not _is_floater(w):
			_break_rotation_idx = (_break_rotation_idx + k + 1) % n
			return w
	return null

# =============================================================================
# HELPERS
# =============================================================================
func _covers(w: NPC, station_id: String) -> bool:
	for tk in _zone_for(w.npc_role):
		if station_id.find(String(tk)) != -1:
			return true
	return false

func _zone_for(role: String) -> Array:
	return ZONES.get(role, [])

func _is_floater(w: NPC) -> bool:
	return w.npc_role in FLOATERS

func _has_nodes() -> bool:
	return line_flow != null and "_nodes" in line_flow

func _machine_list() -> Array:
	var out : Array = []
	if _has_nodes():
		for nd in line_flow._nodes:
			out.append({"id": String(nd.get("id", "")), "pos": _node_pos(nd)})
	return out

func _nearest_in_zone(role: String, from: Vector3, machines: Array) -> Dictionary:
	var tokens := _zone_for(role)
	if tokens.is_empty():
		return {}
	var best : Dictionary = {}
	var best_d := INF
	for m in machines:
		var id := String(m["id"])
		var hit := false
		for tk in tokens:
			if id.find(String(tk)) != -1:
				hit = true
				break
		if not hit:
			continue
		var d : float = from.distance_to(m["pos"])
		if d < best_d:
			best_d = d
			best = m
	return best

func _node_pos(nd: Dictionary) -> Vector3:
	var n = nd.get("node", null)
	if n != null and is_instance_valid(n):
		return (n as Node3D).global_position
	return nd.get("win", Vector3.ZERO)

func _node_by_id(id: String) -> Dictionary:
	if _has_nodes():
		for nd in line_flow._nodes:
			if String(nd.get("id", "")) == id:
				return nd
	return {}

func _avg_pos(machines: Array) -> Vector3:
	if machines.is_empty():
		return Vector3.ZERO
	var s := Vector3.ZERO
	for m in machines:
		s += m["pos"] as Vector3
	return s / float(machines.size())

# ── Status for the HUD ────────────────────────────────────────────────────────
func count_on_break() -> int:
	return _break_until.size()

func active_faults() -> int:
	return _handling.size()

func roster_lines() -> Array[String]:
	var out: Array[String] = []
	for w in workers:
		out.append("%-11s %s" % [String(w.npc_name), w.current_task()])
	return out

# ── Manual crew assignment (the operator's crew panel) ─────────────────────────
## All assignable posts (machine stations) on the line, as [{id, pos}].
func station_list() -> Array:
	return _machine_list()

## The station_id the operator pinned this worker to, or "" if auto.
func pinned_station(worker) -> String:
	return String(_pinned.get(worker, ""))

## The role-based posts a worker can be assigned to from the crew panel — the proper
## plant rota positions (shift leader, extruder op, feeder, …) rather than raw machine
## ids. Order matters: the panel lists them in this order.
const ROLE_POSTS := [
	{"id": "role:shift_leader",       "label": "Shiftleader"},
	{"id": "role:asst_shift_leader",  "label": "Asst. shiftleader"},
	{"id": "role:extruder_op",        "label": "Extruder operator"},
	{"id": "role:permanent_feeder",   "label": "Permanent feeder"},
	{"id": "role:feeder",             "label": "Feeder"},
	{"id": "role:transitional",       "label": "Transitional (feeder → extruder)"},
	{"id": "role:all_rounder",        "label": "All-rounder"},
	{"id": "role:production_manager", "label": "Production manager"},
]

static func role_posts() -> Array:
	return ROLE_POSTS

## Hand-assign `worker` to a post. Special ids: "__auto__" reverts to role-based
## auto-posting, "__off__" takes them off duty. "role:X" sets the worker's npc_role
## to X and auto-posts them as that role (the proper plant rota slots: shift leader,
## extruder op, feeder, …). Anything else is a station id — the worker walks over
## and mans that specific machine, and stays pinned (#36 role-based posts).
func manual_assign(worker, station_id: String) -> void:
	if worker == null:
		return
	if station_id == "__off__":
		_pinned.erase(worker)
		if worker.has_method("set_off_duty"):
			worker.set_off_duty(true)
		return
	if worker.has_method("set_off_duty") and worker.has_method("is_off_duty") and worker.is_off_duty():
		worker.set_off_duty(false)   # bring them back on duty before re-posting
	if station_id == "__auto__":
		_pinned.erase(worker)
		var best : Dictionary = _nearest_in_zone(worker.npc_role, worker.global_position, _machine_list())
		if not best.is_empty():
			var apos : Vector3 = best["pos"]; apos.y = worker.global_position.y
			worker.assign_post(String(best["id"]), apos)
		return
	# Role-based post: switch the worker's RotA role, then auto-post by that role's zone.
	if station_id.begins_with("role:"):
		var new_role := station_id.substr(5)
		worker.npc_role = new_role
		_pinned.erase(worker)
		var best_role : Dictionary = _nearest_in_zone(new_role, worker.global_position, _machine_list())
		if not best_role.is_empty():
			var rpos : Vector3 = best_role["pos"]; rpos.y = worker.global_position.y
			worker.assign_post(String(best_role["id"]), rpos)
		_pinned[worker] = station_id   # remember the rota pin (the role, not a machine)
		_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
		return
	for m in _machine_list():
		if String(m["id"]) == station_id:
			var pos : Vector3 = m["pos"]; pos.y = worker.global_position.y
			worker.assign_post(station_id, pos)
			_pinned[worker] = station_id
			_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
			return
