extends StaticBody3D
class_name LeafBlower

## A holdable LEAF BLOWER for housekeeping loose film scraps that drift around
## the wash line / shredder discharge / extruder shed. Same pickup-and-hold UX
## as the ShovelTool: walk up, E to pick up, LMB-HOLD to blow.
##
## While held, the blower projects a cone of wind from the operator's camera
## forward — every RigidBody3D in the group "film_scrap" inside the cone receives
## a force directed AWAY from the muzzle, attenuated by inverse-square distance
## and gated by a single-ray occlusion check (so walls/machines block the wind).
##
## The motor SPOOLS UP over `spool_time_seconds` while LMB is held, and spools
## DOWN once released — so it doesn't snap from 0 to full throttle (and bodies
## don't get teleport-flung).
##
## Originally a Jules-PR Node3D with turn_on()/turn_off() but never wired up;
## refitted into the same held-tool pattern as ShovelTool / WireCutter so it
## composes with the Inventory + crosshair-prompt + build-menu flow.

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "leafblower"

const PICKUP_RANGE   : float = 1.6
@export var max_force          : float = 50.0    # N at the muzzle (before attenuation)
@export var max_range          : float = 10.0    # m — bodies past this are ignored
@export var spool_time_seconds : float = 1.0     # full-throttle ramp time
@export var cone_radius        : float = 2.0     # half-radius of the wind cone at its tip

# ── Fuel (#leafblower-fuel) ─────────────────────────────────────────────────
## A full tank gives RUN_SECONDS_FULL seconds of continuous full-throttle
## operation; half-throttle burns at half-rate (proportional to _spool), so
## holding the trigger lightly stretches the tank linearly. Burn rate is
## computed from these two numbers so changing either still works out.
@export var fuel_capacity_l : float = 0.5
const RUN_SECONDS_FULL : float = 30.0 * 60.0    # 30 real minutes on a full tank
var fuel_l : float = 0.5

# Below STUTTER_THRESHOLD of capacity the engine can't make full power — even
# at full-trigger it sputters between idle and (a bit above) idle. Real
# behaviour: the carb keeps gulping the last sips and can't sustain WOT.
const STUTTER_THRESHOLD : float = 0.05
const IDLE_SPOOL : float = 0.20

# Primer bulb (the soft fuel-filled dome). Real two-stroke leaf blowers won't
# start until you've pushed fuel into the carb with the primer; tank dry → air
# in the line → needs priming again after refuel. Each press counts as one
# "squeeze" of the bulb; PRIME_PUMPS_REQUIRED clears the prime requirement.
const PRIME_PUMPS_REQUIRED : int = 3
var _needs_prime : bool = true       # fresh-built blower or a tank that ran dry
var _primer_pumps : int  = 0
var _primer_pulse_t : float = 0.0    # visual squish countdown after a pump

enum State { OFF, SPOOLING_UP, FULL_THROTTLE, SPOOLING_DOWN }
var _state : int = State.OFF
var _spool : float = 0.0

# Fuel LED on the housing — colour changes with the remaining fuel fraction so
# the operator can see at a glance whether the tank is full or low. Updated
# each frame; emission energy nudged so it reads under work-lights too.
var _fuel_led_mat : StandardMaterial3D = null

# Primer bulb on the housing — translucent yellow dome the operator pumps with
# RMB. Squishes briefly on each pump so the player sees the pump landed.
var _primer_dome : MeshInstance3D = null

var _held_by     : Node3D = null
var _player_near : bool   = false
var _player_node : Node   = null

# Wind sensor + occlusion ray (built procedurally in _build_wind_volume).
var _wind_area : Area3D = null
var _wind_cs   : CollisionShape3D = null
var _ray       : RayCast3D = null
var _active_bodies : Array[RigidBody3D] = []

# =============================================================================
func _ready() -> void:
	add_to_group("leaf_blower")
	fuel_l = fuel_capacity_l   # ships with a full tank
	_build_visual()
	_build_pickup_trigger()
	_build_wind_volume()
	_refresh_fuel_led()

## Orange housing + dark grip + dark nozzle. Sized so a held pose reads cleanly.
func _build_visual() -> void:
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.96, 0.42, 0.10); orange.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12); dark.roughness = 0.85
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.65, 0.65, 0.68); steel.metallic = 0.7; steel.roughness = 0.35
	# Main motor housing
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.22, 0.22, 0.34)
	body.mesh = bm; body.material_override = orange
	body.position = Vector3(0, 0.06, 0.0)
	add_child(body)
	# Nozzle tube extending forward (-Z = blow direction)
	var nozzle := MeshInstance3D.new()
	var nm := CylinderMesh.new(); nm.top_radius = 0.06; nm.bottom_radius = 0.08
	nm.height = 0.55; nm.radial_segments = 16
	nozzle.mesh = nm
	nozzle.material_override = dark
	nozzle.position = Vector3(0, 0.06, -0.42)
	nozzle.rotation.x = deg_to_rad(90.0)
	add_child(nozzle)
	# Nozzle cone tip
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new(); tm.top_radius = 0.05; tm.bottom_radius = 0.075
	tm.height = 0.08; tm.radial_segments = 16
	tip.mesh = tm
	tip.material_override = steel
	tip.position = Vector3(0, 0.06, -0.72)
	tip.rotation.x = deg_to_rad(90.0)
	add_child(tip)
	# Grip handle on top
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new(); gm.size = Vector3(0.06, 0.14, 0.10)
	grip.mesh = gm; grip.material_override = dark
	grip.position = Vector3(0, 0.24, 0.0)
	add_child(grip)
	# Intake vent on the back (cosmetic dark cap)
	var vent := MeshInstance3D.new()
	var vm := BoxMesh.new(); vm.size = Vector3(0.18, 0.18, 0.04)
	vent.mesh = vm; vent.material_override = dark
	vent.position = Vector3(0, 0.06, 0.19)
	add_child(vent)
	# Fuel-level LED on the side of the housing — green=full, amber=low, red=empty.
	# Mat ref stored so _refresh_fuel_led can recolor it as fuel burns down.
	_fuel_led_mat = StandardMaterial3D.new()
	_fuel_led_mat.albedo_color = Color(0.27, 0.78, 0.32)
	_fuel_led_mat.emission_enabled = true
	_fuel_led_mat.emission = Color(0.27, 0.78, 0.32)
	_fuel_led_mat.emission_energy_multiplier = 1.8
	var led := MeshInstance3D.new()
	led.name = "FuelLED"
	var lm := SphereMesh.new(); lm.radius = 0.018; lm.height = 0.036
	led.mesh = lm
	led.material_override = _fuel_led_mat
	led.position = Vector3(0.12, 0.13, 0.05)
	add_child(led)
	# Primer bulb — the soft yellow dome the operator pumps with RMB to push fuel
	# into the carb before starting. Sits on top of the engine housing near the
	# front (a typical spot on real two-stroke leaf blowers). Translucent so the
	# operator sees the fuel sloshing inside.
	var primer_mat := StandardMaterial3D.new()
	primer_mat.albedo_color = Color(0.96, 0.86, 0.20, 0.60)
	primer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	primer_mat.roughness = 0.25
	_primer_dome = MeshInstance3D.new()
	var pdm := SphereMesh.new()
	pdm.radius = 0.026
	pdm.height = 0.042
	pdm.radial_segments = 14
	pdm.rings = 7
	_primer_dome.mesh = pdm
	_primer_dome.material_override = primer_mat
	_primer_dome.position = Vector3(0.0, 0.18, -0.06)
	_primer_dome.name = "PrimerBulb"
	add_child(_primer_dome)
	# Bounding collision so it rests on the floor when dropped.
	var col := CollisionShape3D.new()
	var cb := BoxShape3D.new(); cb.size = Vector3(0.24, 0.30, 0.85)
	col.shape = cb
	col.position = Vector3(0, 0.12, -0.20)
	add_child(col)

func _build_pickup_trigger() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = PICKUP_RANGE
	cs.shape = sp
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

## A cylindrical sensor in front of the nozzle that tracks every film_scrap in
## reach. The cylinder's local +Z (its length axis after the 90° tilt) points
## along the blow direction — _physics_process repositions it each frame to sit
## in front of the camera when held.
func _build_wind_volume() -> void:
	_wind_area = Area3D.new()
	_wind_area.name = "WindArea"
	_wind_area.monitorable = false   # we only sense, we don't trigger others
	_wind_area.collision_layer = 0
	_wind_area.collision_mask = 1
	_wind_cs = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = max_range
	cyl.radius = cone_radius
	_wind_cs.shape = cyl
	# Tilt the cylinder so its length axis is local +Z (the muzzle direction).
	_wind_cs.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	_wind_area.add_child(_wind_cs)
	add_child(_wind_area)
	_wind_area.body_entered.connect(_on_wind_body_entered)
	_wind_area.body_exited.connect(_on_wind_body_exited)
	_ray = RayCast3D.new()
	_ray.enabled = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = 1
	add_child(_ray)

# =============================================================================
# PICKUP / DROP (E)  — same contract as ShovelTool / WireCutter
# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if _held_by != null or body.name != "Player":
		return
	_player_near = true
	_player_node = body

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		if _player_near and event.is_action_pressed("interact"):
			_pick_up(_player_node)
			get_viewport().set_input_as_handled()
		return
	# Only react when WE are the active inventory slot.
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	# RIGHT MOUSE BUTTON — primer pump. Squeezes the soft yellow dome to push
	# fuel into the carb so the engine will catch. One press = one pump;
	# PRIME_PUMPS_REQUIRED clears the needs_prime flag.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_pump_primer()
			get_viewport().set_input_as_handled()
			return
	# Continuous fire — _physics_process reads Input.is_action_pressed("tool_use")
	# directly so a HELD LMB ramps up the spool; release ramps it back down.

func crosshair_prompt(_player: Node3D) -> String:
	return "Take leaf blower" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# tool ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it on the floor and prompt the player.
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
		return
	_held_by = player
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	# Held pose: clipped under the camera, nozzle pointed forward (-Z).
	transform = Transform3D(Basis(), Vector3(0.22, -0.22, -0.55))
	collision_layer = 0
	collision_mask  = 0
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _drop() -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.6, -0.8)
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask  = 1
	_held_by = null
	_state = State.OFF
	_spool = 0.0
	_active_bodies.clear()

# =============================================================================
# WIND SIM — runs every physics step while held
# =============================================================================
func _on_wind_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("film_scrap"):
		if not _active_bodies.has(body):
			_active_bodies.append(body as RigidBody3D)

func _on_wind_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_active_bodies.erase(body as RigidBody3D)

## Direction the operator is aiming (camera forward when held, else our own -Z).
func _aim_direction() -> Vector3:
	if _held_by != null:
		var cam := _held_by.get_node_or_null("Head/Camera3D") as Camera3D
		if cam != null:
			return -cam.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func _muzzle_origin() -> Vector3:
	# Tip of the nozzle (the 'tip' mesh sits ~0.72 m forward of our origin).
	return global_transform * Vector3(0.0, 0.06, -0.72)

func _physics_process(delta: float) -> void:
	# Pose the WindArea every frame: in front of the muzzle, aligned with aim.
	# (Always — including when stowed in the inventory but inactive — so a held
	# tool that becomes active mid-frame already has its sensor in the right spot.)
	if _wind_area != null and is_inside_tree():
		# Renamed from `aim` — a later `var aim` further down the same
		# _physics_process triggered CONFUSABLE_LOCAL_DECLARATION.
		var wind_aim := _aim_direction()
		var origin := _muzzle_origin() + wind_aim * (max_range * 0.5)
		# Build a basis whose local +Z (length axis) points along wind_aim.
		var up := Vector3.UP
		if absf(wind_aim.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var right := up.cross(wind_aim).normalized()
		var nu := wind_aim.cross(right).normalized()
		_wind_area.global_transform = Transform3D(Basis(right, nu, wind_aim), origin)

	# Drive the spool state.
	if _held_by == null:
		_state = State.OFF
		_spool = 0.0
		return
	var inv := get_node_or_null("/root/Inventory")
	var is_active := (inv == null) or bool(inv.call("is_active", self))
	var pressed := is_active and Input.is_action_pressed("tool_use")
	var was_running : bool = _spool > 0.0001
	# Empty tank: engine just dies. No spool-up. If it was running, the next time
	# the tank gets fuel the operator still has to PRIME — running dry pulls air
	# into the carb line, exactly like a real two-stroke.
	if fuel_l <= 0.0:
		if was_running:
			_needs_prime = true
		if _state == State.SPOOLING_UP or _state == State.FULL_THROTTLE:
			_state = State.SPOOLING_DOWN
		pressed = false
	# Cold engine / dry-out — startup requires priming first. While not primed,
	# pulling the trigger does nothing (the carb has no fuel to ignite).
	if _needs_prime:
		if _state == State.SPOOLING_UP or _state == State.FULL_THROTTLE:
			_state = State.SPOOLING_DOWN
		pressed = false
	match _state:
		State.OFF:
			if pressed: _state = State.SPOOLING_UP
		State.SPOOLING_UP:
			_spool = minf(1.0, _spool + delta / maxf(spool_time_seconds, 0.001))
			if _spool >= 1.0: _state = State.FULL_THROTTLE
			if not pressed:   _state = State.SPOOLING_DOWN
		State.FULL_THROTTLE:
			if not pressed:   _state = State.SPOOLING_DOWN
		State.SPOOLING_DOWN:
			_spool = maxf(0.0, _spool - delta / maxf(spool_time_seconds, 0.001))
			if _spool <= 0.0: _state = State.OFF
			if pressed and fuel_l > 0.0 and not _needs_prime: _state = State.SPOOLING_UP
	# Stutter: below 5% the carb can't sustain WOT — full-throttle requests get
	# CAPPED at idle so the engine wheezes at low RPM until the operator refuels.
	# Real two-stroke behaviour, replaces the old warning banners with feedback
	# the operator can hear/feel.
	var f := fuel_pct()
	if f > 0.0 and f < STUTTER_THRESHOLD:
		_spool = minf(_spool, IDLE_SPOOL)
	# Burn fuel proportional to live spool — half-throttle uses half-rate.
	if _spool > 0.0001:
		var burn := (fuel_capacity_l / RUN_SECONDS_FULL) * _spool * delta
		fuel_l = maxf(0.0, fuel_l - burn)
		_refresh_fuel_led()
	# Animate the primer bulb squish from the last pump (visual feedback).
	if _primer_pulse_t > 0.0:
		_primer_pulse_t = maxf(0.0, _primer_pulse_t - delta)
		var k : float = _primer_pulse_t / 0.20      # 0..1
		if _primer_dome != null:
			_primer_dome.scale.y = 1.0 - 0.45 * k
	elif _primer_dome != null and _primer_dome.scale.y != 1.0:
		_primer_dome.scale.y = 1.0
	if _spool <= 0.0:
		return

	# Push every tracked scrap forward, with inverse-square attenuation and a
	# single occlusion ray (so a machine/wall blocks the wind).
	var force_mag := max_force * _spool
	var aim := _aim_direction()
	var muzzle := _muzzle_origin()
	for body in _active_bodies:
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var to_body := (body.global_position - muzzle)
		var dist := to_body.length()
		if dist > max_range:
			continue
		# Occlusion check: ray from muzzle to body. If something other than the
		# body itself sits between, the wind is blocked.
		if _ray != null:
			_ray.global_position = muzzle
			_ray.target_position = _ray.to_local(body.global_position)
			_ray.force_raycast_update()
			if _ray.is_colliding() and _ray.get_collider() != body:
				continue
		# Force direction = the operator's aim, NOT straight at the scrap — so the
		# scrap is pushed FORWARD (in the blow direction), the way a real blower works.
		var atten := 1.0 / (1.0 + dist * dist)
		body.apply_central_force(aim * force_mag * atten)

# =============================================================================
# FUEL — public API + UX
# =============================================================================
## 0..1 fraction of the tank remaining. HUD / jerry-can / banner read this.
func fuel_pct() -> float:
	if fuel_capacity_l <= 0.0:
		return 0.0
	return clampf(fuel_l / fuel_capacity_l, 0.0, 1.0)

## Pour `litres` of fuel in (or default: top all the way up). Caller-side check
## of capacity is unnecessary — overflow is clamped here. Refuelling does NOT
## clear _needs_prime — if the tank ran dry, the operator still has to prime
## the carb (right-mouse pump) before the engine will catch. The LED recolours
## immediately so the operator sees the refill landed; there's no banner.
func refuel(litres: float = -1.0) -> void:
	if litres < 0.0:
		fuel_l = fuel_capacity_l
	else:
		fuel_l = minf(fuel_capacity_l, fuel_l + litres)
	_refresh_fuel_led()

## Recolor the housing LED so the operator sees the tank state at a glance.
##   ≥50% green   ·   25–50% yellow   ·   10–25% orange   ·   <10% red   ·   0% off
func _refresh_fuel_led() -> void:
	if _fuel_led_mat == null:
		return
	var f := fuel_pct()
	var c : Color
	if f >= 0.50:    c = Color(0.27, 0.78, 0.32)
	elif f >= 0.25:  c = Color(0.95, 0.85, 0.20)
	elif f >= 0.10:  c = Color(0.96, 0.55, 0.15)
	elif f > 0.0:    c = Color(0.86, 0.22, 0.18)
	else:            c = Color(0.18, 0.18, 0.20)
	_fuel_led_mat.albedo_color = c
	_fuel_led_mat.emission = c
	_fuel_led_mat.emission_energy_multiplier = (1.8 if f > 0.0 else 0.0)

## Pump the primer bulb once. After PRIME_PUMPS_REQUIRED pumps the engine is
## ready to start; below that the trigger does nothing. Pumping with no fuel
## in the tank is a no-op — you can't push what isn't there.
func _pump_primer() -> void:
	if not _needs_prime:
		return
	if fuel_l <= 0.0:
		# Tank dry — pump does nothing. Operator needs to refuel at the can first.
		return
	_primer_pumps += 1
	_primer_pulse_t = 0.20    # visual squish for ~200 ms
	if _primer_pumps >= PRIME_PUMPS_REQUIRED:
		_needs_prime = false
		_primer_pumps = 0
