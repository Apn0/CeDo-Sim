extends CharacterBody3D
class_name FeederWorker

## Autonomous feed-line worker (Abdullah, Mohammed, …). Runs the bale-feeding
## loop the operator described:
##
##   SEEK     → find the nearest unclaimed, un-fed bale in the lot
##   TO_BALE  → walk to it, claim it
##   PROCESS  → "clamp + lower + hop out + cut the 3 wires + scan the yellow
##              label" — modelled as a short timed sequence that flips the
##              bale's wires_cut + scanned meta. (Scan is required for the belt
##              to accept it later — the #152 gate.)
##   CARRY    → pick the bale up onto the carry point, walk to the feed belt
##   LOAD     → place it on the belt (belt.accept_bale honours the scan gate)
##   then back to SEEK.
##
## TWO MODES:
##   • DRIVE (when a vehicle is assigned, the normal case): the worker boards its
##     vehicle and pilots it via the vehicle's NPC autopilot — drive to the bale,
##     clamp it onto the carry point, drive to the belt, cut+scan, place it. The
##     operator stays in the cab the whole shift (bar breaks).
##   • ON-FOOT (fallback, no vehicle): walks and carries the bale by hand. Kept
##     for headless tests + the degenerate "no machine free" case.
##
## CLAMP-CORRECTNESS: when the worker sets a bale on the belt it orients it so
## the film SHEETS lie horizontal (sheets stacked vertically), which is the
## "clamp across the sheets, not along them" outcome — a bale set this way falls
## open on the belt instead of staying shut or tearing.

@export var worker_name   : String = "Feeder"
@export var body_color    : Color  = Color(0.95, 0.55, 0.10)   # hi-vis; set to the assigned crew member's colour (#233)
@export var assigned_line : String = ""              # "Line 1", "Line 3A/3B", …
# #173 — section pin the operator picked ("feed_3a", "feed_1", …). When set, the
# worker feeds THAT section's opzetband (matched by belt placeable_id) instead of
# just the nearest belt. Empty = legacy nearest-belt behaviour.
@export var assigned_section : String = ""
@export var section_belt_id  : String = ""           # opzetband placeable_id to feed (derived from the section)
@export var walk_speed    : float = 3.2
@export var arrive_dist   : float = 1.1
@export var lot_center    : Vector3 = Vector3.ZERO   # where the feedstock bales sit
@export var lot_radius    : float = 14.0             # how far out to look for bales
@export var process_secs  : float = 3.0              # cut-wires + scan time per bale
# #6 — SUPPLIER mode: instead of feeding a belt, this worker ferries bales from
# its lot to `supplier_target` (the staging spot at the FEEDER's lot) and drops
# them there as a ready supply. Used to repurpose Abdullah (idle Line 1) into a
# bale-runner for Mohammed.
@export var is_supplier   : bool = false
var supplier_target       : Vector3 = Vector3.ZERO

# Personal kit (handed over by MainWorld): the worker's own vehicle (NOT the
# player's), plus a personal scissors + scanner stowed on a holster. They keep
# these for the whole shift.
var vehicle           : Node3D = null
var personal_scissors : Node3D = null
var personal_scanner  : Node3D = null
var _holster          : Node3D = null
var _hand             : Node3D = null   # front-of-chest anchor a tool is pulled to while in use

enum State { SEEK, TO_BALE, GRAB, LIFT, PROCESS, CARRY, LOAD, WAIT, TO_BELT,
	SET_DOWN, DISMOUNT, CUT, SCAN, FEED, REMOUNT }
var _state       : int = State.SEEK
var _dismounted  : bool = false        # true while the worker is out of the cab on foot
var _restocks    : int  = 0            # how many times we've refilled an empty lot
var _target_pos  : Vector3 = Vector3.ZERO
var _bale        : Node3D = null         # the bale currently being handled
var _belt        : Node = null           # the ShredderFeedBelt we feed
var _carry_point : Node3D = null
var _timer       : float = 0.0
var _gravity     : float = 9.8
var _riding      : bool = false          # true once boarded into the assigned vehicle
var _boarding_walk : bool = false        # #233 walking on foot to the parked clamp before boarding
var _leg_timer   : float = 0.0           # time spent on the current drive leg
var _log_timer   : float = 0.0           # throttles the diagnostic print
var _last_good_xf : Transform3D = Transform3D.IDENTITY   # NaN-transform watchdog
var _xf_warned   : bool = false
# #173 — state-transition diagnostic so the operator can pinpoint where the feed
# loop stalls. Logged from _physics_process by comparing _state to _state_log.
# Also fires a stuck-state warning if the same state runs for >30 s without a
# transition (a watchdog for the "feeders don't feed" report).
var _state_log         : int   = -1
var _state_held_secs   : float = 0.0
var _state_next_warn_s : float = 0.0     # de-spam: the old `int(held) % 10 == 0`
										 # test was true for EVERY frame inside
										 # that second (~60 warnings per hit).
const _STATE_STUCK_S   : float = 30.0
const _STATE_WARN_EVERY_S : float = 10.0
# #233 boarding walk is straight-line steering with no navmesh — a machine or wall
# between the worker and the parked clamp blocks it forever. While blocked
# _physics_process returns BEFORE the state machine ticks, so _state freezes at
# whatever it was (usually SEEK) and the stuck watchdog misreports the phase.
var _board_walk_secs   : float = 0.0
var _board_walk_best_d : float = INF     # closest we've ever gotten to the clamp
var _board_walk_warned : bool  = false
const BOARD_WALK_STUCK_S : float = 20.0  # no net progress for this long == blocked
const BOARD_WALK_PROGRESS_M : float = 0.5   # counts as progress toward the clamp
const _STATE_NAMES : Array[String] = ["SEEK","TO_BALE","GRAB","LIFT","PROCESS",
	"CARRY","LOAD","WAIT","TO_BELT","SET_DOWN","DISMOUNT","CUT","SCAN","FEED","REMOUNT"]
var _grab_tries  : int = 0               # real-grab attempts this approach (no teleport fallback)
const STUCK_LIMIT : float = 14.0         # s before force-completing a stuck drive leg
const GRAB_TRIES_MAX : int   = 5         # re-approaches before giving up on a bale
const LIFT_CARRY_M   : float = 1.4       # carriage height while carrying a bale
const CLAMP_SQUEEZE  : float = 1.0       # full clamp force for the NPC's grip (== holding B to max)

# Stats (for HUD / debugging / tests)
var bales_fed       : int = 0
var bales_processed : int = 0

# =============================================================================
func _ready() -> void:
	add_to_group("feeder_worker")
	_build_body()
	_carry_point = Node3D.new()
	_carry_point.name = "CarryPoint"
	# CANONICAL: "in front" = local -Z (matches the Humanoid face plane and the
	# look_at-driven yaw at line 700). Bale rides in front of the worker's chest.
	_carry_point.position = Vector3(0.0, 1.7, -0.6)
	add_child(_carry_point)
	# Holster behind the worker where their personal scissors + scanner ride.
	# CANONICAL: "behind" = local +Z (back side of the canonical-front face).
	_holster = Node3D.new()
	_holster.name = "Holster"
	_holster.position = Vector3(0.0, 1.0, 0.35)
	add_child(_holster)
	# In-use anchor: front of the chest (canonical front = local -Z), hand height.
	# SCAN pulls the scanner here, CUT pulls the scissors here, so the worker is
	# visibly USING the tool instead of scanning/cutting with empty hands (operator
	# 2026-07-16). Between steps the tool returns to the back holster.
	_hand = Node3D.new()
	_hand.name = "Hand"
	_hand.position = Vector3(0.28, 1.15, -0.30)
	add_child(_hand)

# =============================================================================
# PERSONAL KIT (assigned by MainWorld)
# =============================================================================
## Hand this worker their own vehicle. Tags it NPC-owned so the player can't
## board it ("not one of mine").
func assign_vehicle(v: Node3D) -> void:
	vehicle = v
	if v == null:
		return
	if "npc_owned" in v:
		v.set("npc_owned", true)
	if "npc_owner_name" in v:
		v.set("npc_owner_name", worker_name)
	# #233 — the assigned worker WALKS to the parked clamp on foot and climbs in,
	# rather than teleporting into the cab. _physics_process drives the approach.
	_boarding_walk = true
	_board_walk_secs = 0.0
	_board_walk_best_d = INF
	_board_walk_warned = false

## Climb into the assigned vehicle: re-parent under it (so we ride along), park
## at the cab, and disable our own capsule collision + on-foot locomotion. From
## here the brain pilots the vehicle via its NPC autopilot. The operator stays
## in it the whole shift (bar breaks).
func _board_vehicle() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if get_parent():
		get_parent().remove_child(self)
	vehicle.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.0, 1.3, -0.2))   # seated in the cab
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	# Start the drive loop fresh — discard any state the on-foot brain may have
	# set in the frame before boarding.
	_state = State.SEEK
	_bale = null
	_riding = true

## #233 — walk on foot to the parked assigned vehicle. Returns true once we're
## close enough to climb in (the caller then boards). Same on-foot locomotion as
## the no-vehicle fallback; the capsule is still enabled at this point (boarding
## disables it), so move_and_slide + is_on_floor work.
func _walk_to_vehicle(delta: float) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		_boarding_walk = false
		return true
	var vp : Vector3 = (vehicle as Node3D).global_position
	var d : float = _horiz_dist(vp)
	if d <= 2.4:
		_boarding_walk = false
		return true
	# Blocked-walk watchdog. Straight-line steering has no way around an obstacle,
	# and the caller returns while we're walking — so without this the worker
	# presses into a wall for the whole shift and the feed loop never runs.
	# Progress = getting meaningfully closer than our best-ever distance.
	if d < _board_walk_best_d - BOARD_WALK_PROGRESS_M:
		_board_walk_best_d = d
		_board_walk_secs = 0.0
	else:
		_board_walk_secs += delta
		if _board_walk_secs > BOARD_WALK_STUCK_S:
			if not _board_walk_warned:
				_board_walk_warned = true
				push_warning(("[Feeder %s] boarding walk BLOCKED %.1f m from the clamp "
					+ "for %.0fs — boarding directly so the feed loop can run")
					% [worker_name, d, _board_walk_secs])
			# Last resort only: #233 says the worker must normally WALK to the
			# clamp, not appear in the cab. A permanently frozen feeder is worse.
			_boarding_walk = false
			return true
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var dir : Vector3 = vp - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	return false

## Stow a personal tool (scissors / scanner) on the holster. Disables its
## world-pickup so the player can't walk off with the crew's kit.
func stow_personal_tool(tool: Node3D, side: float) -> void:
	if tool == null:
		return
	# Kill the tool's pickup trigger so it's not grabbable by the player.
	var area := tool.get_node_or_null("PickupArea") as Area3D
	if area:
		area.monitoring = false
		area.monitorable = false
	if tool is CollisionObject3D:
		(tool as CollisionObject3D).collision_layer = 0
		(tool as CollisionObject3D).collision_mask  = 0
	if tool.get_parent():
		tool.get_parent().remove_child(tool)
	_holster.add_child(tool)
	tool.transform = Transform3D(Basis(), Vector3(side * 0.18, 0.0, 0.0))

func _build_body() -> void:
	# Hi-vis blocky worker + a name billboard, so they read as crew on the lot.
	# Humanoid is centred on its origin (feet at -0.9); this body sits at y=0.9
	# so its feet land at the node origin, matching the capsule collider below.
	var humanoid_script := load("res://src/scenes/world/Humanoid.gd")
	var body : Node3D = humanoid_script.build(body_color, 1)
	body.position = Vector3(0, 0.9, 0)
	add_child(body)
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new(); cs.radius = 0.35; cs.height = 1.8
	col.shape = cs
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	# Minecraft-style floating name tag — billboard, drawn on top (no depth test) so
	# the driver is identifiable even behind a machine. Matches NPC._build_name_tag.
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = worker_name
	tag.position = Vector3(0, 2.1, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.006
	tag.font_size = 64
	tag.outline_size = 16
	tag.modulate = Color(1, 1, 1)
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.no_depth_test = true
	tag.render_priority = 2
	tag.fixed_size = false
	add_child(tag)

# =============================================================================
# MAIN LOOP
static var _cached_belts: Array[Node] = []
static var _last_belt_cache_frame: int = -1

static var _cached_bales: Array[Node] = []
static var _last_bale_cache_frame: int = -1

# =============================================================================
func _physics_process(delta: float) -> void:
	# #173 — state-transition diagnostic. Logs every change so when the operator
	# reports "feeders don't feed", the log shows the exact stuck state. Also
	# pings a warning when one state holds >30 s (e.g. SEEK forever = no bales
	# found; TO_BELT forever = pathing blocked).
	if _state != _state_log:
		var prev := _name_for_state(_state_log) if _state_log >= 0 else "<init>"
		var nxt  := _name_for_state(_state)
		print("[Feeder %s] %s → %s   (bales_fed=%d bale=%s)"
				% [worker_name, prev, nxt, bales_fed, str(_bale)])
		_state_log = _state
		_state_held_secs = 0.0
		_state_next_warn_s = _STATE_STUCK_S
	else:
		_state_held_secs += delta
		if _state_held_secs >= _state_next_warn_s:
			_state_next_warn_s = _state_held_secs + _STATE_WARN_EVERY_S
			# Name the phase that is ACTUALLY running. While _boarding_walk is set
			# the state machine never ticks (see the early return below), so
			# reporting _state here blamed SEEK for a blocked walk to the clamp.
			var phase := _name_for_state(_state)
			if _boarding_walk:
				phase = "BOARDING_WALK(state %s frozen)" % phase
			push_warning("[Feeder %s] stuck in %s for %.0fs"
					% [worker_name, phase, _state_held_secs])
	# NaN-transform watchdog (see BaseVehicle): a worker whose transform goes bad
	# would spam instance_set_transform via its capsule + name tag + held tools. Snap
	# back to the last good pose + report ONCE rather than flood the log.
	if global_transform.is_finite():
		_last_good_xf = global_transform
	else:
		if not _xf_warned:
			_xf_warned = true
			push_warning("[Feeder %s] caught + reset a NON-FINITE transform (state %d)" % [worker_name, _state])
		global_transform = _last_good_xf
		velocity = Vector3.ZERO
		return
	_resolve_belt()
	if vehicle != null and is_instance_valid(vehicle):
		# DRIVE mode.
		if not _riding:
			# #233 — the assigned worker walks on foot to the parked clamp, THEN
			# climbs in (the operator wants them to visibly go to the clamp + board,
			# not spawn in the cab). Once boarded the drive brain takes over.
			if _boarding_walk:
				if not _walk_to_vehicle(delta):
					return                 # still walking over to the clamp
			_board_vehicle()
		if _riding:
			_brain_drive(delta)
			_diag(delta)
	else:
		_brain(delta)                # on-foot fallback (no vehicle assigned)
		_locomote(delta)

## Throttled console diagnostic so we can see what the feeders are actually
## doing in a running game (the headless test can't show in-game stalls).
func _diag(delta: float) -> void:
	_log_timer -= delta
	if _log_timer > 0.0:
		return
	_log_timer = 5.0
	var st_names : Array = ["SEEK","TO_BALE","GRAB","LIFT","PROCESS","CARRY","LOAD","WAIT","TO_BELT",
		"SET_DOWN","DISMOUNT","CUT","SCAN","FEED","REMOUNT"]
	var stn : String = st_names[_state] if _state < st_names.size() else "?"
	print("[Feeder %s] %s  fed=%d  bale=%s  vpos=%s" % [
		worker_name, stn, bales_fed,
		("yes" if _bale != null and is_instance_valid(_bale) else "no"),
		str(vehicle.global_position.round())])

# =============================================================================
# DRIVE BRAIN — pilot the assigned vehicle through the loop
# =============================================================================
func _brain_drive(delta: float) -> void:
	match _state:
		State.SEEK:     _drive_state_seek()
		State.TO_BALE:  _drive_state_to_bale(delta)
		State.GRAB:     _drive_state_grab(delta)
		State.LIFT:     _drive_state_lift(delta)
		State.TO_BELT:  _drive_state_to_belt(delta)
		State.SET_DOWN: _drive_state_set_down(delta)
		State.DISMOUNT: _drive_state_dismount()
		State.CUT:      _drive_state_cut(delta)
		State.SCAN:     _drive_state_scan(delta)
		State.FEED:     _drive_state_feed()
		State.REMOUNT:  _drive_state_remount()
		State.WAIT:     _drive_state_wait(delta)

func _drive_state_seek() -> void:
	var b := _find_bale()
	if b == null:
		# Lot ran dry. Operator 2026-07-16 ("stationary bale / feeder does
		# nothing"): the #32 "no auto-restock" left the feeder parked FOREVER on an
		# empty lot. Re-enable a CAPPED restock so it keeps working without flooding
		# the plant — after MAX_RESTOCKS refills it parks as before.
		if _restocks < MAX_RESTOCKS:
			_restock_lot()
		vehicle.call("npc_stop")
		_state = State.WAIT
		_timer = 1.0
	else:
		_bale = b
		b.set_meta("feeder_claimed", true)
		vehicle.call("npc_set_target", (b as Node3D).global_position, true)   # carry-first: reverse the plates onto the bale
		_state = State.TO_BALE
		_leg_timer = 0.0

func _drive_state_to_bale(delta: float) -> void:
	if _bale == null or not is_instance_valid(_bale):
		_state = State.SEEK
	else:
		_leg_timer += delta
		if bool(vehicle.call("npc_arrived")) or _leg_timer > STUCK_LIMIT:
			# npc_arrived tolerates NPC_ARRIVE_TOL (2.2 m) to the waypoint, which
			# can park the CARRY POINT just outside GRAB_RANGE (2.5 m). Every
			# grab then fails, and re-targeting the same bale pos "arrives"
			# instantly without moving — an infinite TO_BALE→GRAB loop. If we
			# stopped short, aim PAST the bale so the clamp pulls its carry
			# point onto the load, and keep driving (STUCK_LIMIT still bounds it).
			if _leg_timer <= STUCK_LIMIT and vehicle.has_method("_carry_point"):
				var cp : Node3D = vehicle.call("_carry_point") as Node3D
				var bpos : Vector3 = (_bale as Node3D).global_position
				if cp != null and cp.global_position.distance_to(bpos) > 2.3:  # GRAB_RANGE − margin
					var dir : Vector3 = bpos - (vehicle as Node3D).global_position
					dir.y = 0.0
					dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
					vehicle.call("npc_set_target", bpos + dir * 1.5, true)
					return
			# Arrived: stop and LOWER THE CARRIAGE to the bale (real control —
			# drive lift_height_m down), then grab. No teleport.
			vehicle.call("npc_stop")
			if "lift_height_m" in vehicle and "lift_min_m" in vehicle:
				vehicle.set("lift_height_m", vehicle.get("lift_min_m"))
			_grab_tries = 0
			_timer = 0.7                 # let the carriage settle onto the bale
			_state = State.GRAB

func _drive_state_grab(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		# REAL grip: squeeze the plates (clamp_force is the SAME control the
		# player ramps with B) and fire the SAME _try_grab their release calls.
		# It latches whatever bale is within GRAB_RANGE of the carry point —
		# geometry + force gate, never a from-distance teleport.
		if "clamp_force" in vehicle:
			vehicle.set("clamp_force", CLAMP_SQUEEZE)
		vehicle.call("_try_grab")
		if _vehicle_holding():
			_timer = 0.6
			_state = State.LIFT
		else:
			_grab_tries += 1
			if _grab_tries >= GRAB_TRIES_MAX:
				if _bale != null and is_instance_valid(_bale):
					_bale.set_meta("feeder_claimed", false)
				_state = State.SEEK      # can't reach it — never deadlock
			else:
				# Re-approach and retry (real driving, not a teleport).
				if _bale != null and is_instance_valid(_bale):
					vehicle.call("npc_set_target", (_bale as Node3D).global_position, true)
				_leg_timer = 0.0
				_state = State.TO_BALE

func _drive_state_lift(delta: float) -> void:
	_timer -= delta
	if "lift_height_m" in vehicle:
		vehicle.set("lift_height_m", LIFT_CARRY_M)   # raise the load on the mast (real control)
	if _timer <= 0.0:
		if is_supplier and supplier_target != Vector3.ZERO:
			vehicle.call("npc_set_target", supplier_target, true)   # ferry to the feeder's staging, load leading
			_state = State.TO_BELT
			_leg_timer = 0.0
		elif _belt != null:
			vehicle.call("npc_set_target", _work_spot(), true)   # deliver with the load leading
			_state = State.TO_BELT
			_leg_timer = 0.0
		else:
			_state = State.WAIT
			_timer = 1.0

func _drive_state_to_belt(delta: float) -> void:
	_leg_timer += delta
	if bool(vehicle.call("npc_arrived")) or _leg_timer > STUCK_LIMIT:
		vehicle.call("npc_stop")
		# Lower the carriage to set the bale down beside the belt (real control).
		if "lift_height_m" in vehicle and "lift_min_m" in vehicle:
			vehicle.set("lift_height_m", vehicle.get("lift_min_m"))
		_timer = 0.7
		_state = State.SET_DOWN

func _drive_state_set_down(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		# Open the clamp + release (real controls) — the bale drops at the
		# lowered carry point on the ground beside the belt.
		if _set_bale_on_ground():
			if is_supplier:
				# Supplier STAGES the bale: clear the claim so the feeder (Mohammed)
				# can grab it, then fetch the next. No cut/scan from the supplier.
				if _bale != null and is_instance_valid(_bale):
					_bale.set_meta("feeder_claimed", false)
					_bale.set_meta("delivered", false)
				_bale = null
				bales_processed += 1
				_state = State.SEEK
			else:
				_state = State.DISMOUNT
		else:
			_state = State.SEEK

func _drive_state_dismount() -> void:
	# Hop OUT of the cab and stand at the still-CLAMPED bale. #233 — the operator's
	# real order is SCAN first (with the scanner), THEN cut the top wires, so the
	# on-foot work starts at SCAN.
	_dismount_worker()
	_state = State.SCAN
	_timer = maxf(process_secs * 0.5, 0.3)

func _drive_state_scan(delta: float) -> void:
	# On foot, bale still CLAMPED: actually scan the yellow label (the belt's #152
	# scan gate), then PEEL it off. #233 — scan comes BEFORE the wire-cut ("actually
	# scan it, no magic"). The scanner is pulled to the hand for the duration so the
	# worker is visibly scanning WITH the scanner (operator 2026-07-16).
	_equip_tool(personal_scanner)
	_timer -= delta
	if _timer <= 0.0:
		if _bale != null and is_instance_valid(_bale) and _bale.is_in_group("bale"):
			_bale.set_meta("scanned", true)
			_peel_label(_bale)
		stow_personal_tool(personal_scanner, 1.0)
		_state = State.CUT
		_timer = maxf(process_secs * 0.5, 0.3)

func _drive_state_cut(delta: float) -> void:
	# On foot, bale still CLAMPED CORRECTLY: cut + remove the 3 top wires (scissors).
	# #233 — cut happens AFTER the scan and while the clamp still holds the stack, so
	# it can't open until the clamp finally releases it on the belt (see #4). Then the
	# worker climbs back into the clamp to place it — cut → REMOUNT, not straight to feed.
	# The scissors are pulled to the hand so the worker visibly cuts WITH the cutter.
	_equip_tool(personal_scissors)
	_timer -= delta
	if _timer <= 0.0:
		if _bale != null and is_instance_valid(_bale):
			_bale.set_meta("wires_cut", true)
			_strip_wires(_bale)
		stow_personal_tool(personal_scissors, -1.0)
		bales_processed += 1
		_state = State.REMOUNT

## Pull a stowed personal tool from the back holster to the front-of-chest hand
## anchor so the worker is seen USING it. No-op if the tool is missing.
func _equip_tool(tool: Node3D) -> void:
	if tool == null or not is_instance_valid(tool) or _hand == null:
		return
	if tool.get_parent() != _hand:
		if tool.get_parent():
			tool.get_parent().remove_child(tool)
		_hand.add_child(tool)
	tool.transform = Transform3D(Basis(), Vector3.ZERO)

func _drive_state_remount() -> void:
	# #233 — climb back INTO the clamp, THEN place the (scanned + de-wired) bale on
	# the conveyor and release it. "Then and only then get back in the clamp…"
	_remount_worker()
	_state = State.FEED

func _drive_state_feed() -> void:
	# Back in the clamp: put the scanned, de-wired bale onto the conveyor + release —
	# but ONLY once the belt's loading end is clear, so bales never land inside one
	# another. Until then hold it in the clamp (re-checks each frame). #233
	if not _belt_has_room():
		return                      # hold: belt's load zone still occupied
	if _feed_ground_bale():
		_state = State.SEEK

func _drive_state_wait(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_state = State.SEEK


## Lower the clamped bale from the vehicle onto the GROUND at the work spot beside
## the belt (still bound — cut + scan happen on foot, next). False if nothing held.
## True while the clamp is physically holding a bale (real grab latched it).
func _vehicle_holding() -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	if "_carried_bale" in vehicle:
		return vehicle.get("_carried_bale") != null
	return false

## Orientation for a bale placed on / staged for the belt: its LENGTH (model X /
## sheet-stack axis) runs ALONG the belt's travel, so it feeds in end-first and the
## sheets peel off in sequence. (The operator confirmed from the in-game view that
## the earlier "across the belt" orientation was the wrong way round.) Falls back to
## a world-axis basis when this worker has no belt — all feed belts are world-aligned.
const BALE_FEED_YAW := -PI / 2.0   # turn the bale's length (model X) onto belt travel (local Z)
func _bale_feed_basis() -> Basis:
	var b := Basis()
	if _belt != null and is_instance_valid(_belt):
		b = (_belt as Node3D).global_transform.basis.orthonormalized()
	return b * Basis(Vector3.UP, BALE_FEED_YAW)

## Re-square a just-placed bale to the across-belt orientation, keeping its position.
## A bale released after a carry otherwise keeps whatever skewed angle the clamp held
## it at — that's the "put on sideways → therefore picked up sideways" bug. Freshly
## spawned lot bales are already across; this makes carried/staged ones match.
func _square_bale_to_belt(bale: Node3D) -> void:
	if bale == null or not is_instance_valid(bale):
		return
	bale.global_transform = Transform3D(_bale_feed_basis(), bale.global_transform.origin)

## True when the belt's loading end is clear enough to take another bale. Gates the
## FEED state so the worker holds its bale instead of dropping it onto one already there.
func _belt_has_room() -> bool:
	if _belt == null or not is_instance_valid(_belt):
		return true
	if _belt.has_method("can_accept"):
		return bool(_belt.call("can_accept"))
	return true

func _set_bale_on_ground() -> bool:
	# REAL release: open the clamp (clamp_force → 0) and call the SAME _release the
	# player's V triggers — the bale drops at the (lowered) carry point on the ground
	# beside the belt. No teleport / manual repositioning. Keep our _bale ref for the
	# on-foot cut/scan/feed that follows.
	var held : Node3D = null
	if "_carried_bale" in vehicle:
		held = vehicle.get("_carried_bale") as Node3D
	if not is_supplier:
		# FEEDER: do NOT release here — keep the bale CLAMPED through the wire-cut so the
		# stack can't open until the clamp finally lets go (at FEED). Capture the ref only.
		if held != null and is_instance_valid(held):
			_bale = held
		return _bale != null and is_instance_valid(_bale)
	# SUPPLIER: open the clamp + release so the bale drops at the carry point to be staged.
	if "clamp_force" in vehicle:
		vehicle.set("clamp_force", 0.0)
	vehicle.call("_release")
	if held != null and is_instance_valid(held):
		_bale = held
	if _bale == null or not is_instance_valid(_bale):
		return false
	if _bale is RigidBody3D:
		(_bale as RigidBody3D).freeze = true
	_square_bale_to_belt(_bale)   # orient length ACROSS the belt — no carry skew (#11 orientation)
	return true

## Climb OUT of the cab and stand beside the grounded bale (re-enable the capsule).
func _dismount_worker() -> void:
	var gt := global_transform
	# Capture the scene BEFORE detaching — once self leaves the tree, get_tree()
	# returns null, so this must be read first.
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	if get_parent() != null and get_parent() != scene:
		get_parent().remove_child(self)
		scene.add_child(self)
		global_transform = gt
	# Stand beside the grounded bale with feet ON the floor. Keep the capsule
	# collision DISABLED while on foot — re-enabling it next to the parked vehicle/bale
	# made the physics solver fling the worker ~8 m into the air (the teleport bug).
	# They only stand a couple of seconds to cut + scan, so no collision is needed.
	var spot := _work_spot()
	global_position = Vector3(spot.x + 1.2, spot.y, spot.z)
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	_dismounted = true

## Climb back into the cab (disable the capsule again) and resume driving.
func _remount_worker() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	if vehicle != null and is_instance_valid(vehicle):
		if get_parent():
			get_parent().remove_child(self)
		vehicle.add_child(self)
		transform = Transform3D(Basis(), Vector3(0.0, 1.3, -0.2))
	_dismounted = false

## Put the cut + scanned + opened bale onto the feed belt via belt.accept_bale
## (which honours the #152 scan gate and re-parents the bale onto the deck so the
## belt sim + LineFlow head actually consume it). Returns true once the bale is on
## the belt; false if there's nothing to feed or the belt refused it (scan gate /
## load-zone), so the caller can retry.
func _feed_ground_bale() -> bool:
	var b := _bale
	if b == null or not is_instance_valid(b):
		_bale = null
		return true
	# No belt to feed (headless / mis-config): drop the ref so we don't deadlock.
	if _belt == null or not is_instance_valid(_belt) or not _belt.has_method("accept_bale"):
		_bale = null
		return true
	# #233 — the feeder is stationed AT this belt: if it has latched a fault (a jam),
	# they clear it as part of loading so the feed loop can NEVER permanently deadlock
	# waiting on a belt nobody resets. (accept_bale refuses while faulted.)
	if _belt.has_method("is_faulted") and bool(_belt.call("is_faulted")):
		if _belt.has_method("reset_faults"):
			_belt.call("reset_faults")
	# Open the clamp NOW (real control) — the wires are already cut, so the instant the
	# clamp lets go nothing holds the stack.
	if vehicle != null and is_instance_valid(vehicle):
		if "clamp_force" in vehicle:
			vehicle.set("clamp_force", 0.0)
		vehicle.call("_release")
	# Detach from wherever the clamp/carry left it, then lay it on the belt infeed
	# in the feed orientation so accept_bale can re-parent it cleanly onto the deck.
	if b.get_parent():
		b.get_parent().remove_child(b)
	get_tree().current_scene.add_child(b)
	b.global_transform = Transform3D(_bale_feed_basis(), _belt_load_point())
	# #4 — on release the bale BURSTS into physical tumbling film pieces (nothing
	# clamps it anymore). burst_bale still rides the bale's MASS to the shredder
	# invisibly, so the line feeds as before. Fall back to accept_bale on older belts.
	var ok : bool
	if _belt.has_method("burst_bale"):
		ok = bool(_belt.call("burst_bale", b))
	else:
		ok = bool(_belt.call("accept_bale", b, 0))   # lane 0 = deck centre; honours scan gate
	if not ok:
		# Belt refused (unscanned / load zone busy). Keep the ref and try again next
		# tick — the FEED state re-enters and _belt_has_room() paces the retry.
		return false
	# The bale now rides the belt and is consumed by the belt→shredder→LineFlow
	# path. Clear any `delivered` flag the vehicle's _release set when it opened the
	# clamp at the belt, so LineFlow's _bale_at head-draw can't ALSO meter from this
	# same bale sitting on the deck (would double-feed the line).
	if is_instance_valid(b):
		b.set_meta("delivered", false)
	bales_fed += 1
	_bale = null
	return true

## Ground work-spot beside the belt's loading end where bales are set down + cut.
func _work_spot() -> Vector3:
	if _belt == null:
		return global_position
	var bn := _belt as Node3D
	return bn.to_global(Vector3(1.8, 0.0, 1.0))

## Cut + remove the wire wrapping so the bale doesn't ride the belt still bound. #176
func _strip_wires(bale: Node3D) -> void:
	if bale == null or not is_instance_valid(bale):
		return
	var wires := bale.find_child("Wires", true, false)
	if wires != null:
		wires.queue_free()

## Peel the yellow shipping label off a scanned bale (removes the "Label" sticker +
## any label_item nodes, so there's no label — or stack of them — left on it). #177
func _peel_label(bale: Node3D) -> void:
	if bale == null or not is_instance_valid(bale):
		return
	var lbl := bale.get_node_or_null("Label")
	if lbl != null:
		lbl.queue_free()
	for c in bale.get_children():
		if c.is_in_group("label_item"):
			c.queue_free()

## Refill an empty lot with a fresh side-by-side row of bales (the reserve), so the
## feeder keeps running instead of stopping dead when the lot empties. #178
const MAX_RESTOCKS : int = 4   # capped auto-refills before the feeder parks (anti-flood; _restocks declared above)

func _restock_lot() -> void:
	var n := 0
	var current_frame := Engine.get_physics_frames()
	if current_frame != _last_bale_cache_frame:
		_cached_bales = get_tree().get_nodes_in_group("bale")
		_last_bale_cache_frame = current_frame

	for b in _cached_bales:
		var bn := b as Node3D
		if bn == null or not is_instance_valid(bn):
			continue
		if bool(bn.get_meta("feeder_claimed", false)):
			continue
		if bn.get_parent() != null and bn.get_parent().is_in_group("shredder_feed_belt"):
			continue
		if bn.global_position.distance_to(lot_center) <= lot_radius:
			n += 1
	if n > 0:
		return   # stock still on hand
	var origins := BaleDefs.origins()
	if origins.is_empty():
		return
	for i in range(6):
		var o : Dictionary = origins[i % origins.size()]
		var bale := PlaceableCatalog.build_node(String(o["id"]), false) as Node3D
		if bale == null:
			continue
		get_tree().current_scene.add_child(bale)
		# #223 audit: was +0.6 m then frozen → bales hovered in mid-air forever.
		# Bale origin = bale bottom, so a floor-level Y rests it exactly on the slab.
		bale.global_position = lot_center + Vector3(float(i) * 1.7, 0.0, 0.0)
		bale.rotation.y = BALE_FEED_YAW   # length along the feed direction, like the belt (#orientation)
		if bale is RigidBody3D:
			(bale as RigidBody3D).freeze = true
	_restocks += 1

func _resolve_belt() -> void:
	if _belt != null and is_instance_valid(_belt):
		return
	var current_frame := Engine.get_physics_frames()
	if current_frame != _last_belt_cache_frame:
		_cached_belts = get_tree().get_nodes_in_group("shredder_feed_belt")
		_last_belt_cache_frame = current_frame

	# #173 — SECTION-PINNED: feed the specific opzetband the operator assigned this
	# worker to (matched by placeable_id). This is the "reads section pins to choose
	# which feed belt" behaviour the SECTION_ZONES comment advertises.
	if section_belt_id != "":
		for b in _cached_belts:
			if not is_instance_valid(b):
				continue
			var bn := b as Node3D
			if bn != null and String((bn as Node).get_meta("placeable_id", "")) == section_belt_id:
				_belt = b
				return
		# Named belt not (yet) in the scene — fall through to nearest so we still feed.

	# Legacy / fallback: nearest feed belt to this worker (a worker feeds the belt
	# by their lot — and it keeps multi-belt scenes / tests unambiguous).
	var best : Node = null
	var best_d := 1e9
	for b in _cached_belts:
		if not is_instance_valid(b):
			continue
		var bn := b as Node3D
		if bn == null:
			continue
		var d := bn.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = b
	_belt = best

func _brain(delta: float) -> void:
	match _state:
		State.SEEK:
			var b := _find_bale()
			if b == null:
				_state = State.WAIT
				_timer = 1.5
			else:
				_bale = b
				b.set_meta("feeder_claimed", true)
				_target_pos = (b as Node3D).global_position
				_state = State.TO_BALE
		State.TO_BALE:
			if _bale == null or not is_instance_valid(_bale):
				_state = State.SEEK
			elif _horiz_dist((_bale as Node3D).global_position) <= arrive_dist + 0.6:
				_state = State.PROCESS
				_timer = process_secs
		State.PROCESS:
			# Standing at the bale: cut the wires + scan the label. We flip the
			# meta progressively so the timeline reads cut → scan.
			_timer -= delta
			if _bale != null and is_instance_valid(_bale):
				if _timer <= process_secs * 0.5:
					_bale.set_meta("wires_cut", true)
				if _timer <= 0.0:
					if _bale.is_in_group("bale"):
						_bale.set_meta("scanned", true)
					bales_processed += 1
					_pick_up_bale()
					_state = State.CARRY
			else:
				_state = State.SEEK
		State.CARRY:
			if _belt == null:
				_state = State.WAIT; _timer = 1.0
			else:
				_target_pos = _belt_load_point()
				if _horiz_dist(_target_pos) <= arrive_dist + 0.8:
					_state = State.LOAD
		State.LOAD:
			_load_onto_belt()
			_state = State.SEEK
		State.WAIT:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.SEEK

func _locomote(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var want_move := _state in [State.TO_BALE, State.CARRY]
	if want_move and _horiz_dist(_target_pos) > arrive_dist:
		var dir := _target_pos - global_position
		dir.y = 0.0
		# Guard: horiz_dist may pass with a non-zero distance but `dir.y = 0.0`
		# can still leave a near-zero horizontal vector (target directly above /
		# below). normalize-of-zero returns NaN, propagating through velocity
		# and the look_at target.
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			velocity.x = dir.x * walk_speed
			velocity.z = dir.z * walk_speed
			# Face travel direction
			look_at(global_position + dir, Vector3.UP)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	KinematicPush.apply(self, 85.0, 0.5, get_physics_process_delta_time())   # #223: mass-based push

# =============================================================================
# BALE HANDLING
# =============================================================================
## Nearest bale within the lot that isn't already claimed, on a belt, or fed.
func _find_bale() -> Node3D:
	var best : Node3D = null
	var best_d := lot_radius

	var current_frame := Engine.get_physics_frames()
	if current_frame != _last_bale_cache_frame:
		_cached_bales = get_tree().get_nodes_in_group("bale")
		_last_bale_cache_frame = current_frame

	for b in _cached_bales:
		var bn := b as Node3D
		if bn == null or not is_instance_valid(bn):
			continue
		if bool(bn.get_meta("feeder_claimed", false)):
			continue
		# Skip bales already riding a belt (their parent is the belt).
		if bn.get_parent() != null and bn.get_parent().is_in_group("shredder_feed_belt"):
			continue
		var d := bn.global_position.distance_to(lot_center)
		if d > lot_radius:
			continue
		var dd := _horiz_dist(bn.global_position)
		if dd < best_d:
			best_d = dd
			best = bn
	return best

func _pick_up_bale() -> void:
	if _bale == null or not is_instance_valid(_bale):
		return
	if _bale is RigidBody3D:
		(_bale as RigidBody3D).freeze = true
	# Carried bales must not collide — otherwise the frozen body shoves the
	# worker capsule around (same class of bug as the held-tool fling).
	if _bale is CollisionObject3D:
		(_bale as CollisionObject3D).collision_layer = 0
		(_bale as CollisionObject3D).collision_mask  = 0
	if _bale.get_parent():
		_bale.get_parent().remove_child(_bale)
	_carry_point.add_child(_bale)
	(_bale as Node3D).transform = Transform3D.IDENTITY

func _load_onto_belt() -> void:
	if _bale == null or not is_instance_valid(_bale):
		_bale = null
		return
	if _belt == null or not _belt.has_method("accept_bale"):
		# No belt — drop it back on the ground at our feet and forget it.
		_drop_bale_here()
		return
	# Detach from the carry point first so accept_bale can re-parent cleanly.
	if _bale.get_parent():
		_bale.get_parent().remove_child(_bale)
	get_tree().current_scene.add_child(_bale)
	# Orient sheets horizontal so it falls open on the belt (clamp-across-sheets
	# outcome). Lay the bale flat.
	(_bale as Node3D).global_transform = Transform3D(Basis(), _belt_load_point())
	var ok : bool = _belt.call("accept_bale", _bale, 0)   # lane 0 = centre of the deck
	if ok:
		bales_fed += 1
	_bale.set_meta("feeder_claimed", false)
	_bale = null

func _drop_bale_here() -> void:
	if _bale == null:
		return
	if _bale.get_parent():
		_bale.get_parent().remove_child(_bale)
	get_tree().current_scene.add_child(_bale)
	(_bale as Node3D).global_position = global_position + Vector3(0, 0.5, 1.0)
	_bale.set_meta("feeder_claimed", false)
	_bale = null

func _belt_load_point() -> Vector3:
	if _belt == null:
		return global_position
	# CENTRED on the deck width (X=0), set down ON the deck TOP (not the belt base),
	# and well FORWARD onto the deck — not dumped at the near loading edge. Belt local
	# +Z is the travel direction.
	var bn := _belt as Node3D
	var dh : float = 0.7
	var dl : float = 5.0
	if "deck_height" in _belt: dh = float(_belt.get("deck_height"))
	if "deck_length" in _belt: dl = float(_belt.get("deck_length"))
	return bn.to_global(Vector3(0.0, dh + 0.6, dl * 0.45))

func _horiz_dist(p: Vector3) -> float:
	var a := global_position; a.y = 0.0
	var b := p;               b.y = 0.0
	return a.distance_to(b)

## Short status for a HUD roster line.
func status_line() -> String:
	var names : Array = ["seeking", "to bale", "cutting+scanning", "carrying", "loading", "waiting", "driving to belt",
		"setting down", "hopping out", "cutting wires", "scanning", "feeding belt", "climbing back in"]
	var st : String = names[_state] if _state < names.size() else "?"
	var line_tag := "" if assigned_line == "" else " [%s]" % assigned_line
	return "%s%s — %s  (fed %d)" % [worker_name, line_tag, st, bales_fed]

# #173 — pretty-print state ids for the transition log.
func _name_for_state(s: int) -> String:
	if s < 0 or s >= _STATE_NAMES.size():
		return "?"
	return _STATE_NAMES[s]
