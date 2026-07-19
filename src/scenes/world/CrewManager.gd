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
var _worst_jam_cache : Dictionary = {}   # #223 — worst jam this frame; needs_worker() reads it so the per-NPC autonomy poll doesn't re-scan LineFlow
var _break_until: Dictionary = {}   # NPC -> seconds of break remaining
var _break_timer: float      = BREAK_INTERVAL
var _break_rotation_idx: int = 0    # round-robin cursor so breaks ROTATE across crew
var _pinned     : Dictionary = {}   # NPC -> station_id the OPERATOR pinned by hand (overrides auto-post)
# #124 — for `pos:` (HIER) pins ONLY, store the full Vector3 position + facing
# radians the operator picked. _pinned holds the string id used for the panel
# dropdown ("pos:X,Y,Z"), _pin_meta holds the actual transform data needed for
# saving, rebuilding the world marker, and re-applying after off-duty toggles.
# Keyed by NPC node (same as _pinned) at runtime; (re)keyed by npc_name for the
# save dict so the pin survives a save/load round-trip.
var _pin_meta   : Dictionary = {}   # NPC -> {pos: Vector3, facing: float}
var _pin_marker : Dictionary = {}   # NPC -> Node3D (visible flag in the world)
# #173 feeder-brain — one autonomous FeederWorker per section the operator has
# pinned a feeder to. Keyed by section_key ("feed_3a", …) so re-assigning the same
# section reuses (and re-homes) the existing feeder instead of spawning duplicates.
var _section_feeders : Dictionary = {}   # section_key -> FeederWorker
var _feeder_owner    : Dictionary = {}   # #233 section_key -> the REAL crew NPC driving that feeder

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
	add_to_group("crew_manager")   # #223 — NPC._autonomy_tick finds us here to yield production-first
	workers.clear()
	for k in npc_dict:
		var n = npc_dict[k]
		if n is NPC:
			workers.append(n)
	line_flow      = lf
	shift_clock    = sc
	break_room_pos = break_pos
	assign_posts()
	_hook_walkie()
	# Subscribe to ShiftClock.time_set so an operator rewinding the wall clock
	# to a pre-shift instant despawns the at-post crew and hands them back to
	# PreShiftSequence (which spawns them in arriving cars / dressing room /
	# canteen per their per-NPC arrives_at_s). Without this CrewManager keeps
	# every NPC pinned at their machine even when the clock reads 06:35 —
	# exactly the operator's complaint.
	if shift_clock != null and shift_clock.has_signal("time_set") \
			and not shift_clock.time_set.is_connected(_on_time_set):
		shift_clock.time_set.connect(_on_time_set)

## ShiftClock.time_set handler. Cooperates with PreShiftSequence + MainWorld:
##   - PreShiftSequence.recompute_for() (triggered by the time_jumped signal
##     emitted from inside set_time_and_date) places NPCs at arrival /
##     dressing / canteen / smoke for the scheduled crew.
##   - MainWorld._on_time_jumped repositions parked NPC CARS along the
##     De Asselen Kuil polyline so they arrive at their bay at arrives_at_s.
##   - WE OWN the worker-state reset on a backward jump. The pre-shift branch
##     used to be a no-op trusting PreShiftSequence to flip off-duty for us,
##     but PSS isn't guaranteed to exist (resumed-past-bell save) and even
##     when it does, scheduled NPCs whose node can't be resolved leave the
##     stale AT_POST flag stuck. Owning the despawn here makes the operator's
##     "set time to 06:35" deterministic regardless of PSS state.
##   - At-or-after the bell we re-run assign_posts() so workers PSS had set
##     off-duty (or whose at-post pos got teleported) are brought back on duty.
func _on_time_set(_prev_day: int, _prev_secs: int, _new_day: int, new_secs: int) -> void:
	if shift_clock == null:
		return
	var bell_secs : int = int(shift_clock.shift_start_seconds_of_day()) \
			if shift_clock.has_method("shift_start_seconds_of_day") else 7 * 3600
	# Treat the time-of-day comparison as a "wall clock is before the bell"
	# check. A rewind from 09:00 → 06:35 lands new_secs < bell_secs.
	if new_secs < bell_secs:
		# Pre-shift: drop our in-flight dispatch + break state so we don't try
		# to dispatch a worker PreShiftSequence has hidden, and so the break
		# rotation re-starts fresh once the bell fires.
		_handling.clear()
		_break_until.clear()
		_break_timer = BREAK_INTERVAL
		# Explicitly despawn the at-post crew. clear_post() sets the worker
		# off-duty AND wipes assigned_station_id so current_task() returns
		# "vrij (rust)" instead of a stale "post: …". PreShiftSequence (when
		# it exists) will then teleport each scheduled NPC to arrival /
		# dressing / canteen on its recompute_for pass. Non-scheduled NPCs
		# (Mohammed if PSS lacked them, floaters) stay off-duty until the
		# bell — symmetric to a fresh pre-shift bootstrap.
		for w in workers:
			if not (w is NPC):
				continue
			# Don't touch pinned workers — the operator wants them locked
			# even across a time rewind (#124).
			if _pinned.has(w):
				continue
			if w.has_method("clear_post"):
				w.clear_post()
			elif w.has_method("set_off_duty"):
				w.set_off_duty(true)
	else:
		# Past the bell: re-run posting so any worker PreShiftSequence had set
		# off-duty (or whose at-post-position got teleported by recompute_for)
		# is brought on-duty + sent back to their machine. _handling is cleared
		# so the next tick re-evaluates jams against the now-canonical state.
		_handling.clear()
		for w in workers:
			if not (w is NPC):
				continue
			if w.has_method("is_off_duty") and w.has_method("set_off_duty") \
					and w.is_off_duty():
				w.set_off_duty(false)
		assign_posts()

## Subscribe to Walkie.transmit_sent so the crew brain reacts to the operator's
## keyed-up canned lines (skeletal — currently only "Need a hand here" picks the
## closest feeder NPC, sends them to the operator, and has them echo "On my way"
## on arrival). Best-effort: silently does nothing in the headless harness where
## the autoload isn't present.
func _hook_walkie() -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var walkie := (ml as SceneTree).root.get_node_or_null("Walkie")
	if walkie == null or not walkie.has_signal("transmit_sent"):
		return
	# Avoid double-connecting if setup() is called more than once (e.g. on reload).
	if not walkie.is_connected("transmit_sent", Callable(self, "_on_walkie_transmit")):
		walkie.connect("transmit_sent", Callable(self, "_on_walkie_transmit"))

## Operator keyed up a canned line over the walkie. Skeletal listener: only
## "Need a hand here" triggers a response right now — pick the closest available
## feeder NPC and dispatch them to walk to the operator. On arrival they echo
## "On my way" back over the radio (handled by _on_helper_arrived, queued via the
## NPC's existing dispatch_to callback path).
func _on_walkie_transmit(text: String, heard: bool) -> void:
	if not heard:
		return                     # battery flat — colleagues didn't hear it
	if text == null:
		return
	var t := String(text).strip_edges().to_lower()
	if t.begins_with("need a hand"):
		_dispatch_helper_to_operator()

## Find the closest available feeder NPC, walk them to the player's position,
## and arrange for them to echo "On my way" via the walkie once they arrive.
## No-op when the player isn't in the scene yet, or when no feeder is free.
func _dispatch_helper_to_operator() -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var scene := (ml as SceneTree).current_scene
	if scene == null:
		return
	# Resolve the operator's position. The player node is conventionally named
	# "Player" under MainWorld; fall back to the group lookup if a future scene
	# moves it.
	var player_node : Node3D = scene.find_child("Player", true, false) as Node3D
	if player_node == null:
		for n in (ml as SceneTree).get_nodes_in_group("player"):
			if n is Node3D:
				player_node = n
				break
	if player_node == null:
		return
	var op_pos := player_node.global_position
	# Pick the nearest available feeder. permanent_feeder and feeder both count;
	# transitional is a feeder→extruder swing role so we include it too.
	var helper : NPC = null
	var best_d := INF
	for w in workers:
		if not (w is NPC):
			continue
		if not w.is_available():
			continue
		var role := String(w.npc_role)
		if role != "feeder" and role != "permanent_feeder" and role != "transitional":
			continue
		var d : float = w.global_position.distance_to(op_pos)
		if d < best_d:
			best_d = d
			helper = w
	if helper == null:
		return                     # no feeder free right now — operator's on their own
	# Re-use the standard dispatch path so the helper walks via the navmesh and
	# the brain transitions back to AT_POST when done. SERVICE_SECS gives a brief
	# "stood by" dwell at the operator's spot before they head back.
	helper.dispatch_to(op_pos, "operator_help", SERVICE_SECS)
	_handling["operator_help"] = helper
	_emit("npc_called_for_help", ["operator", String(helper.npc_name), "operator_help"])
	_emit("npc_started_helping", [String(helper.npc_name), "", "operator_help"])
	# Echo "On my way" via the walkie. Skeletal: we send it on dispatch (the
	# real arrival callback lives in step_brain → service-complete, which already
	# emits npc_finished_helping; a fuller implementation would defer the radio
	# call until arrival, but the operator hearing it immediately is acceptable
	# for the first cut — the helper IS on their way as of this tick).
	var walkie := (ml as SceneTree).root.get_node_or_null("Walkie")
	if walkie != null and walkie.has_method("receive_call"):
		walkie.receive_call(String(helper.npc_name), "On my way.")

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
	_worst_jam_cache = jam   # #223 — publish for needs_worker() (production-first gate)
	if not jam.is_empty() and not _handling.has(jam["id"]):
		var sid : String  = String(jam["id"])
		var pos : Vector3 = _node_pos(jam["node"])
		var resp : NPC = _pick_responder(sid, pos)
		if resp != null:
			# #155 / #147 — if the jam target is too high to reach from the floor
			# (e.g. a stop button at the head of a 6-m conveyor), route via the
			# operate-task planner instead of the legacy SERVICE state. The
			# planner walks the responder to the nearest free mast lift, boards
			# it (Phase 4), raises to the target, performs the dwell, returns.
			# Falls back to the straight-line dispatch when reachable from foot.
			if not resp.can_reach(pos):
				var sid_capture : String = sid
				resp.dispatch_to_operate(pos, func(_reason): _emit("npc_finished_helping", [String(resp.npc_name), "", sid_capture]), SERVICE_SECS)
			else:
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

## #223 PRODUCTION-FIRST arbiter — read by NPC._autonomy_tick every frame. Returns
## true when the crew brain has a claim on this worker, so autonomy housekeeping
## (leaf blow / hose / shovel / lump cart) must yield: the worker is off-post /
## servicing / on break / off duty, is already dispatched to a station or bin this
## round, OR there's an un-handled jam inside this worker's coverage they should
## answer. Keeps "keep the line running" strictly above cleaning.
## (docs/plant/npc_rol_taak_prioriteit.md — Tier 1 > Tier 4.)
func needs_worker(w) -> bool:
	if w == null or not is_instance_valid(w):
		return false
	# Not standing free at post → a crew action / break / off-duty already owns them.
	if not w.is_available():
		return true
	# Already claimed to service a jam or an over-full bin this round.
	for handler in _handling.values():
		if handler == w:
			return true
	# An un-handled jam this worker's zone covers → production wants them now, so an
	# idle-LOOKING posted operator drops the leaf blower rather than wander off.
	if not _worst_jam_cache.is_empty():
		var jid := String(_worst_jam_cache.get("id", ""))
		if jid != "" and not _handling.has(jid) and _covers(w, jid):
			return true
	return false

func _break_candidate() -> NPC:
	# Round-robin: start scanning from the rotation cursor so the SAME worker
	# isn't picked every time (the "Romero is always on break" bug). The first
	# available, non-floater, NON-PINNED worker from the cursor onward goes
	# (#124 — operator pins lock the worker to their spot, breaks rotate around
	# them), and the cursor advances past them for next time.
	var n := workers.size()
	for k in n:
		var w : NPC = workers[(_break_rotation_idx + k) % n]
		if w.is_available() and not _is_floater(w) and not _pinned.has(w):
			_break_rotation_idx = (_break_rotation_idx + k + 1) % n
			return w
	return null

# =============================================================================
# HELPERS
# =============================================================================
func _covers(w: NPC, station_id: String) -> bool:
	# #173 — section-pinned workers cover their section first; otherwise fall
	# back to the role-based zone match. A worker pinned to "section:wash_3a"
	# answers wash_3a jams even if their role is something else.
	var pin := String(_pinned.get(w, ""))
	if pin.begins_with("section:"):
		for tk in _zone_for_section(pin.substr(8)):
			if station_id.find(String(tk)) != -1:
				return true
		return false
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

## #173 — section-level assignment. The operator can pin a worker to a NAMED
## section of a specific line (e.g. "Line 3A · Feed area") instead of a single
## machine or a coord. SECTION_ZONES maps each section id to the substrings
## that match its machine ids — same matching style as ZONES uses for roles.
## A section-pinned worker (a) is auto-posted to the NEAREST machine in that
## section, (b) covers any machine in the section for incident response, and
## (c) the FeederWorker reads "section:feed_*" pins to choose which feed belt
## to deliver bales to.
const SECTION_POSTS := [
	{"id": "section:feed_3a",     "label": "Line 3A · Feed area"},
	{"id": "section:feed_3b",     "label": "Line 3B · Feed area"},
	{"id": "section:feed_1",      "label": "Line 1 · Feed area"},
	{"id": "section:feed_3c",     "label": "Line 3C · Feed area"},
	{"id": "section:feed_6",      "label": "Line 6 · Feed area"},
	{"id": "section:intake_3a3b", "label": "Line 3A/3B · Intake conveyors"},
	{"id": "section:sort_3a3b",   "label": "Line 3A/3B · Sorting (TOMRA / TITECH)"},
	{"id": "section:wash_3a",     "label": "Line 3A · Wash"},
	{"id": "section:wash_3b",     "label": "Line 3B · Wash"},
	{"id": "section:wash_1",      "label": "Line 1 · Wash"},
	{"id": "section:extruder_3a", "label": "Line 3A · Extruder"},
	{"id": "section:extruder_3b", "label": "Line 3B · Extruder"},
	{"id": "section:extruder_1",  "label": "Line 1 · Extruder"},
	{"id": "section:extruder_3c", "label": "Line 3C · Extruder"},
	{"id": "section:extruder_6",  "label": "Line 6 · Extruder"},
]
const SECTION_ZONES : Dictionary = {
	"feed_3a":     ["bunker_3a", "shredder_1", "opzetband_3a3b"],
	"feed_3b":     ["bunker_3b", "shredder_1", "opzetband_3a3b"],
	"feed_1":      ["bunker_1",  "opzetband_1", "westa_band_1"],
	"feed_3c":     ["bunker_3c", "opzetband_3c6"],
	"feed_6":      ["bunker_6",  "opzetband_3c6"],
	"intake_3a3b": ["transportband_", "switch_belt", "vss_silo", "u_bay"],
	"sort_3a3b":   ["titech", "tomra", "ballistic", "trilzeef", "metal_belt", "wind_sifter"],
	"wash_3a":     ["prewash_3a", "friction_3a", "intensive_3a", "flotation_3a",
					"rotation_3a", "kufferath_3a", "dewater_3a", "mech_dryer_3a", "centrifuge_3a"],
	"wash_3b":     ["prewash_3b", "friction_3b", "intensive_3b", "flotation_3b",
					"rotation_3b", "kufferath_3b", "dewater_3b", "mech_dryer_3b", "centrifuge_3b"],
	"wash_1":      ["prewash_1", "friction_1", "intensive_1", "flotation_1",
					"rotation_1", "kufferath_1", "dewater_1", "mech_dryer_1", "centrifuge_1"],
	"extruder_3a": ["extruder_3a", "mengsilo_3a", "compactor_3a", "mas_bak_3a"],
	"extruder_3b": ["extruder_3b", "mengsilo_3b", "compactor_3b", "mas_bak_3b"],
	"extruder_1":  ["extruder_1",  "mengsilo_1",  "compactor_1",  "mas_bak_1"],
	"extruder_3c": ["extruder_3c", "mengsilo_3c", "compactor_3c", "mas_bak_3c", "plasmaq", "laser_filter", "melt_pump"],
	"extruder_6":  ["extruder_6",  "mengsilo_6",  "compactor_6",  "mas_bak_6"],
}

static func role_posts() -> Array:
	return ROLE_POSTS

static func section_posts() -> Array:
	return SECTION_POSTS

func _zone_for_section(section_key: String) -> Array:
	return SECTION_ZONES.get(section_key, [])

## Like _nearest_in_zone but uses SECTION_ZONES instead of role zones.
func _nearest_in_section(section_key: String, from: Vector3, machines: Array) -> Dictionary:
	var tokens := _zone_for_section(section_key)
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

# =============================================================================
# #173 — AUTONOMOUS FEEDER ENGAGEMENT
# =============================================================================
## Spawn (or re-home) a FeederWorker bound to a section's opzetband, so pinning a
## feeder to a Feed section actually feeds the line. `key` is the section id
## ("feed_3a") for a section pin, or "role:feeder" for the rota role (no belt
## binding → nearest belt). One feeder per `key`; re-assigning re-homes it.
## `driver` (was `owner`): the parameter shadowed Node.owner.
func _ensure_section_feeder(key: String, near_pos: Vector3 = Vector3.ZERO, driver: Node = null) -> void:
	var world := _feeder_world()
	if world == null:
		return   # headless / no world to parent into — nothing to spawn
	# Resolve the target feed belt for this key. Section pins bind a specific
	# opzetband by placeable_id; the rota role feeds the nearest belt.
	var belt_id : String = ""
	var belt : Node3D = null
	if key.begins_with("feed_"):
		belt_id = _opzetband_id_for_section(key)
		belt = _feed_belt_by_id(belt_id)
	if belt == null:
		belt = _nearest_feed_belt(near_pos)
		if belt != null:
			belt_id = String(belt.get_meta("placeable_id", ""))
	if belt == null:
		# No feed belt exists in this world yet — can't bind a feeder. Bail quietly;
		# the operator can re-pin once the opzetband is built.
		return
	# #233 — a section feeder is DRIVEN BY the real crew member the operator picked.
	# If a DIFFERENT worker drove this section before, hand them back to normal duty.
	var prev_owner = _feeder_owner.get(key, null)
	if prev_owner != null and prev_owner != driver and is_instance_valid(prev_owner):
		_restore_worker(prev_owner)
	# Reuse an existing feeder for this key if still alive; otherwise spawn one.
	var feeder : FeederWorker = _section_feeders.get(key, null)
	if feeder != null and not is_instance_valid(feeder):
		feeder = null
		_section_feeders.erase(key)
	var lot : Vector3 = (belt as Node3D).global_position
	if feeder == null:
		feeder = preload("res://src/scenes/world/FeederWorker.gd").new()
		# #233 — the feeder IS the assigned crew member: adopt their name + colour so
		# there's no generic "Feeder 3A" ghost, only the person the operator picked.
		if driver != null and is_instance_valid(driver) and "npc_name" in driver:
			feeder.worker_name = String(driver.get("npc_name"))
		else:
			feeder.worker_name = "Feeder %s" % key.replace("feed_", "").replace("role:", "").to_upper()
		if driver != null and is_instance_valid(driver):
			for cprop in ["npc_color", "body_color", "color", "suit_color"]:
				if cprop in driver:
					feeder.body_color = driver.get(cprop)
					break
		world.add_child(feeder)
		# Spawn AT the assigned worker's spot so they visibly WALK from their post to
		# the parked clamp; the clamp waits at the feed area beside the belt.
		if driver != null and is_instance_valid(driver) and driver is Node3D:
			feeder.global_position = (driver as Node3D).global_position
		else:
			feeder.global_position = lot + Vector3(3.0, 1.0, 2.0)
		# Personal BaleClamp so it DRIVES the loop (the normal case) rather than the
		# on-foot fallback. Parked at the feed area; assign_vehicle tags it NPC-owned
		# and the feeder walks over to board it.
		var vscene := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
		if vscene != null:
			var v := vscene.instantiate() as Node3D
			world.add_child(v)
			v.global_position = lot + Vector3(2.0, 0.5, -3.0)
			feeder.assign_vehicle(v)
		# Kit every section feeder with its OWN scanner + wire-cutter (operator
		# 2026-07-16: feeders scanned/cut with nothing in hand). Only the legacy
		# LegacyPropsSpawner feeder got tools before; section/rota feeders had none.
		if feeder.personal_scissors == null:
			var sc := WireCutter.new()
			world.add_child(sc)
			sc.global_position = feeder.global_position
			feeder.stow_personal_tool(sc, -1.0)
			feeder.personal_scissors = sc
		if feeder.personal_scanner == null:
			var scan_scr = load("res://src/scenes/world/BarcodeScanner.gd")
			if scan_scr != null:
				var scn : Node3D = scan_scr.new()
				world.add_child(scn)
				scn.global_position = feeder.global_position
				feeder.stow_personal_tool(scn, 1.0)
				feeder.personal_scanner = scn
		_section_feeders[key] = feeder
		var drv : String = String(driver.get("npc_name")) if (driver != null and "npc_name" in driver) else "auto"
		print("[CrewManager] Feeder engaged for %s → belt %s (driver=%s)" % [key, belt_id, drv])
	# #233 — retire the assigned worker's STANDING npc (hide + off-duty) so there's no
	# idle duplicate; the FeederWorker now represents them on the floor. Re-applied
	# every assignment (idempotent) so a re-pin keeps them retired.
	if driver != null and is_instance_valid(driver):
		_feeder_owner[key] = driver
		if driver is Node3D:
			(driver as Node3D).visible = false
		if driver.has_method("set_off_duty"):
			driver.set_off_duty(true)
	# (Re)bind the belt + lot every assignment so re-pinning updates the target.
	feeder.assigned_section = key
	feeder.section_belt_id = belt_id
	feeder.lot_center = lot
	feeder.lot_radius = 20.0
	feeder._belt = null   # force _resolve_belt to re-pick the (possibly new) belt

## #233 — hand a worker who was driving a section feeder back to normal duty: show
## their standing NPC again + clear the off-duty parking the feeder engagement set.
func _restore_worker(worker) -> void:
	if worker == null or not is_instance_valid(worker):
		return
	if worker is Node3D:
		(worker as Node3D).visible = true
	if worker.has_method("set_off_duty"):
		worker.set_off_duty(false)

## #233 — if `worker` currently drives a section feeder, tear that feeder (+ its
## clamp) down and restore the worker. Called before any re-assignment so switching
## a feeder to another post cleanly ends their feeding shift (no orphan ghost).
func _release_owner(worker) -> void:
	if worker == null:
		return
	var found_key := ""
	for k in _feeder_owner.keys():
		if _feeder_owner[k] == worker:
			found_key = String(k)
			break
	if found_key == "":
		return
	var feeder = _section_feeders.get(found_key, null)
	if feeder != null and is_instance_valid(feeder):
		if "vehicle" in feeder:
			var v = feeder.get("vehicle")
			if v != null and is_instance_valid(v):
				v.queue_free()
		feeder.queue_free()
	_section_feeders.erase(found_key)
	_feeder_owner.erase(found_key)
	_restore_worker(worker)

## The world node the feeders parent into — MainWorld (LineFlow's parent).
func _feeder_world() -> Node:
	if line_flow != null and is_instance_valid(line_flow):
		var p := line_flow.get_parent()
		if p != null:
			return p
	var tree := get_tree()
	return tree.current_scene if tree != null else null

## opzetband placeable_id that a Feed section feeds. Reads SECTION_ZONES tokens and
## returns the first "opzetband*" / "westa_band*" token (the physical feed belt).
func _opzetband_id_for_section(section_key: String) -> String:
	for tk in _zone_for_section(section_key):
		var t := String(tk)
		if t.begins_with("opzetband") or t.begins_with("westa_band"):
			return t
	return ""

## Feed belt (ShredderFeedBelt / opzetband) whose placeable_id matches `id`, or null.
func _feed_belt_by_id(id: String) -> Node3D:
	if id == "":
		return null
	for b in get_tree().get_nodes_in_group("shredder_feed_belt"):
		var bn := b as Node3D
		if bn != null and is_instance_valid(bn) and String(bn.get_meta("placeable_id", "")) == id:
			return bn
	return null

## Nearest feed belt to `from` (fallback when no section belt id resolves).
func _nearest_feed_belt(from: Vector3) -> Node3D:
	var best : Node3D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("shredder_feed_belt"):
		var bn := b as Node3D
		if bn == null or not is_instance_valid(bn):
			continue
		var d : float = from.distance_to(bn.global_position)
		if d < best_d:
			best_d = d
			best = bn
	return best

## Hand-assign `worker` to a post. Special ids: "__auto__" reverts to role-based
## auto-posting, "__off__" takes them off duty. "role:X" sets the worker's npc_role
## to X and auto-posts them as that role (the proper plant rota slots: shift leader,
## extruder op, feeder, …). Anything else is a station id — the worker walks over
## and mans that specific machine, and stays pinned (#36 role-based posts).
func manual_assign(worker, station_id: String) -> void:
	if worker == null:
		return
	# #233 — if this worker was driving a section feeder, end that feeding shift
	# (tear down the feeder + clamp, restore them) before applying the new post.
	_release_owner(worker)
	if station_id == "__off__":
		# #124 — DON'T erase the pin. Off-duty is a temporary state; the operator
		# probably wants the pin preserved so flipping back to "Auto" later isn't
		# the only way to recover from off-duty. (Old behaviour silently wiped
		# the pin every off-duty press, surprising the operator.) Clear-pin is
		# only done by unpin() or "__auto__" or a different post selection.
		if worker.has_method("set_off_duty"):
			worker.set_off_duty(true)
		return
	if worker.has_method("set_off_duty") and worker.has_method("is_off_duty") and worker.is_off_duty():
		worker.set_off_duty(false)   # bring them back on duty before re-posting
	if station_id == "__auto__":
		_pinned.erase(worker)
		_pin_meta.erase(worker)
		_clear_pin_marker(worker)
		if "home_facing_rad" in worker:
			worker.home_facing_rad = NAN
		var best : Dictionary = _nearest_in_zone(worker.npc_role, worker.global_position, _machine_list())
		if not best.is_empty():
			var apos : Vector3 = best["pos"]; apos.y = worker.global_position.y
			worker.assign_post(String(best["id"]), apos)
		return
	# #173 — Section-based post: pin the worker to a NAMED zone of a line (Feed,
	# Wash, Extruder, Sort area for that specific line). Auto-posts to the
	# nearest machine in that section's token list. Coverage (_covers) treats
	# any matching machine as in-scope so jam responses stay sectional.
	if station_id.begins_with("section:"):
		var section_key := station_id.substr(8)
		_pinned.erase(worker)
		_pin_meta.erase(worker)
		_clear_pin_marker(worker)
		if "home_facing_rad" in worker:
			worker.home_facing_rad = NAN
		var best_sec : Dictionary = _nearest_in_section(section_key, worker.global_position, _machine_list())
		if not best_sec.is_empty():
			var spos : Vector3 = best_sec["pos"]; spos.y = worker.global_position.y
			worker.assign_post(String(best_sec["id"]), spos)
		_pinned[worker] = station_id
		# #173 — a FEED section pin actually engages feeding behaviour: spawn (or
		# re-home) an autonomous FeederWorker bound to that section's opzetband, so
		# the line is fed for real instead of a generic NPC just standing there.
		if section_key.begins_with("feed_"):
			_ensure_section_feeder(section_key, Vector3.ZERO, worker)
		_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
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
		# #173 — the FEEDER rota role engages an autonomous feeder too. No section is
		# bound, so it feeds the NEAREST belt (FeederWorker._resolve_belt fallback).
		# Keyed by the role so a second feeder-role NPC doesn't spawn a duplicate.
		if new_role == "feeder" or new_role == "permanent_feeder":
			_ensure_section_feeder("role:" + new_role, worker.global_position, worker)
		_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
		return
	# Operator posting someone onto a leaf blower means "go clean with it" — route
	# it to the autonomy board's real blow-leaves task instead of a dead AT_POST
	# stand-around (operator 2026-07-16: Mohammed just stood still).
	if station_id == "tool_leafblower":
		var board := get_node_or_null("/root/NpcAutonomyBoard")
		if board != null and board.has_method("force_task"):
			if bool(board.call("force_task", worker, "blow_leaves")):
				_pinned[worker] = station_id
				_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
				return
	for m in _machine_list():
		if String(m["id"]) == station_id:
			var pos : Vector3 = m["pos"]; pos.y = worker.global_position.y
			worker.assign_post(station_id, pos)
			_pinned[worker] = station_id
			_emit("npc_called_for_help", ["operator", String(worker.npc_name), station_id])
			return

## #124 — pin `worker` to a raw WORLD POSITION (not a machine, not a role).
## The worker walks to the exact spot, holds it, and faces `facing_rad`. The
## full Vector3 is kept (Y too, so mezzanines work) and stored in _pin_meta so
## the panel + marker + save can read it back. Pin id is the coordinate to 1 cm
## precision (5 cm dedupes too aggressively for a real factory floor).
func assign_to_position(worker, pos: Vector3, facing_rad: float = NAN) -> void:
	if worker == null:
		return
	if worker.has_method("is_off_duty") and worker.is_off_duty() \
			and worker.has_method("set_off_duty"):
		worker.set_off_duty(false)
	var pin_id := "pos:%.2f,%.2f,%.2f" % [pos.x, pos.y, pos.z]
	worker.assign_post(pin_id, pos)
	if "home_facing_rad" in worker:
		worker.home_facing_rad = facing_rad
	_pinned[worker] = pin_id
	_pin_meta[worker] = {"pos": pos, "facing": facing_rad}
	_rebuild_pin_marker(worker)
	_emit("npc_called_for_help", ["operator", String(worker.npc_name), pin_id])

## #124 — clear ANY pin (station, role, or coord) and revert this worker to
## auto-posting. Off-duty workers stay off-duty.
func unpin(worker) -> void:
	if worker == null:
		return
	_release_owner(worker)   # #233 — end any feeding shift + restore the worker
	_pinned.erase(worker)
	_pin_meta.erase(worker)
	_clear_pin_marker(worker)
	if "home_facing_rad" in worker:
		worker.home_facing_rad = NAN
	if worker.has_method("is_off_duty") and not worker.is_off_duty():
		var best : Dictionary = _nearest_in_zone(worker.npc_role,
			worker.global_position, _machine_list())
		if not best.is_empty():
			var apos : Vector3 = best["pos"]; apos.y = worker.global_position.y
			worker.assign_post(String(best["id"]), apos)

## #124 — read-only access to the position pin (or {} if none). The panel uses
## this to decide whether to show "📍 PIN: X,Z" in the dropdown.
func position_pin_for(worker) -> Dictionary:
	return _pin_meta.get(worker, {}).duplicate()

## #124 — Serialize ALL pins (station, role, AND coord) to a JSON-safe dict
## keyed by `npc_name`. Called from MainWorld.save_game.
func save_pins_dict() -> Dictionary:
	var out : Dictionary = {}
	for w in _pinned.keys():
		if not is_instance_valid(w):
			continue
		var entry : Dictionary = {"pin_id": String(_pinned[w])}
		if _pin_meta.has(w):
			var m : Dictionary = _pin_meta[w]
			var p : Vector3 = m.get("pos", Vector3.ZERO)
			entry["pos"] = {"x": p.x, "y": p.y, "z": p.z}
			entry["facing"] = float(m.get("facing", NAN))
		out[String(w.npc_name)] = entry
	return out

## #124 — Restore pins saved by `save_pins_dict`. Called from MainWorld after
## CrewManager.setup so every worker exists. Workers without a saved pin keep
## their auto-assigned post.
func restore_pins_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for w in workers:
		var key := String(w.npc_name)
		if not d.has(key):
			continue
		var entry : Dictionary = d[key]
		var pin_id := String(entry.get("pin_id", ""))
		if pin_id.begins_with("pos:") and entry.has("pos"):
			var p : Dictionary = entry["pos"]
			var pos := Vector3(float(p.get("x", 0.0)),
				float(p.get("y", 0.0)), float(p.get("z", 0.0)))
			var face := float(entry.get("facing", NAN))
			assign_to_position(w, pos, face)
		elif pin_id != "":
			# Re-route through manual_assign so role/station pins go through
			# their normal validation path.
			manual_assign(w, pin_id)

# ── Pin marker (visible flag in the world) ───────────────────────────────────
func _rebuild_pin_marker(worker) -> void:
	_clear_pin_marker(worker)
	if not _pin_meta.has(worker):
		return
	var pos : Vector3 = (_pin_meta[worker] as Dictionary).get("pos", Vector3.ZERO)
	var marker := Node3D.new()
	marker.name = "PinMarker_%s" % String(worker.npc_name)
	add_child(marker)
	marker.global_position = pos + Vector3(0.0, 0.05, 0.0)
	# Vertical pole — the operator can see it from across the line.
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.02; pm.bottom_radius = 0.02; pm.height = 2.0
	pole.mesh = pm
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.95, 0.78, 0.18)   # CeDo safety yellow
	pole_mat.emission_enabled = true
	pole_mat.emission = Color(0.95, 0.78, 0.18)
	pole_mat.emission_energy_multiplier = 0.6
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, 1.0, 0.0)
	marker.add_child(pole)
	# Worker name floats above the pole.
	var lbl := Label3D.new()
	lbl.text = "📍 %s" % String(worker.npc_name)
	lbl.font_size = 32; lbl.outline_size = 6
	lbl.position = Vector3(0.0, 2.25, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.004
	lbl.no_depth_test = true
	marker.add_child(lbl)
	_pin_marker[worker] = marker

func _clear_pin_marker(worker) -> void:
	var existing = _pin_marker.get(worker)
	if existing is Node3D and is_instance_valid(existing):
		existing.queue_free()
	_pin_marker.erase(worker)
