class_name KinematicPush
extends RefCounted

# =============================================================================
# #223 audit — mass-based push for CharacterBody3D vs RigidBody3D.
# =============================================================================
# A kinematic body (player, NPC) displaces RigidBodies it walks into with
# INFINITE effective mass in Godot's default solver, so a 140 kg loaded cart
# moved exactly like an empty one and a walking worker could bulldoze a 600 kg
# bale. This restores momentum exchange, ONE law for every human:
#   * the rigid body gets a contact-point impulse (accelerates over ~tau),
#   * the pusher loses the blocked velocity component scaled by (1 - massratio),
#     so a light operator is genuinely stopped by a heavy machine.
# The mass split is the physically-correct m/(m+M), not a clamp — an 88 kg
# operator vs a 100 kg full cart keeps ~47% of speed; vs a 2,690 kg mast lift
# he is walled. Grabbed carts (their handle controller owns them) and frozen
# bodies are skipped.
#
# phys-08 — move_and_slide can report the SAME RigidBody several times in one
# tick (multiple slide iterations against a corner, or several shapes of the
# cart's 13-shape compound collider). The old per-collision loop applied the
# impulse AND the pusher brake once per report, so a corner hit shoved the cart
# at 2-3x the mass-ratio impulse and over-braked the pusher the same number of
# times. Contacts are now merged per unique body first: ONE impulse + ONE
# velocity reduction per body per tick (single-contact behavior unchanged).
#
# phys-01 — bodies exposing notify_body_push() (LumpCart) are poked before the
# impulse lands so they can drop to rolling friction. The parked friction 0.9
# caps a per-tick friction impulse of mu*g*dt = 0.147 m/s — more than the push
# delivers at walk (0.046) or sprint (0.101), so without the poke the promised
# "shove it by walking into it" was a bolted-down wall.
#
# Call AFTER move_and_slide(), passing the body, its real mass (kg), the
# accel time-constant, and the physics delta. `body` must expose `velocity`
# (CharacterBody3D) and the get_slide_collision* API.
static func apply(body: CharacterBody3D, body_mass_kg: float, accel_tau_s: float, delta: float) -> void:
	if body == null or body_mass_kg <= 0.0:
		return
	var contacts : Array = []
	for i in body.get_slide_collision_count():
		var col := body.get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null:
			continue
		contacts.append({"rb": rb, "normal": col.get_normal(), "point": col.get_position()})
	apply_contacts(body, body_mass_kg, accel_tau_s, delta, contacts)

## Core push law, split from the slide-collision harvest so a headless test can
## feed synthetic contact lists (test_cart_push.gd proves the phys-08 dedup by
## handing 3 duplicate contacts on one cart). Each entry:
## {rb: RigidBody3D, normal: Vector3, point: Vector3} in world space, normal
## pointing from the rigid body toward the pusher (slide-collision convention).
static func apply_contacts(body: CharacterBody3D, body_mass_kg: float, accel_tau_s: float, delta: float, contacts: Array) -> void:
	if body == null or body_mass_kg <= 0.0:
		return
	# phys-08 — merge per unique body: sum the normals (direction average after
	# normalize) and keep the first contact point.
	var merged : Dictionary = {}   # instance_id -> {rb, normal_sum, point}
	for c in contacts:
		var rb : RigidBody3D = c["rb"] as RigidBody3D
		if rb == null or rb.freeze:
			continue
		# Skip a cart currently under grab control (its own controller sets forces).
		if "_grabbed_by" in rb and rb.get("_grabbed_by") != null:
			continue
		var key : int = rb.get_instance_id()
		if merged.has(key):
			merged[key]["normal_sum"] = (merged[key]["normal_sum"] as Vector3) + (c["normal"] as Vector3)
		else:
			merged[key] = {"rb": rb, "normal_sum": c["normal"] as Vector3, "point": c["point"] as Vector3}
	for key in merged:
		var hit : Dictionary = merged[key]
		var rb2 : RigidBody3D = hit["rb"] as RigidBody3D
		# Push direction: horizontal component of "into the contact".
		var push_dir : Vector3 = -(hit["normal_sum"] as Vector3)
		push_dir.y = 0.0
		if push_dir.length_squared() < 0.0001:
			continue   # standing on top — no lateral shove
		push_dir = push_dir.normalized()
		var v_into : float = body.velocity.dot(push_dir)
		if v_into <= 0.01:
			continue
		# phys-01 — let the body enter its rolling-friction state before the
		# impulse so the shove isn't cancelled by parked friction (LumpCart).
		if rb2.has_method("notify_body_push"):
			rb2.call("notify_body_push")
		var ratio : float = body_mass_kg / (body_mass_kg + rb2.mass)
		var impulse : Vector3 = push_dir * (v_into * ratio) * rb2.mass * (delta / accel_tau_s)
		rb2.apply_impulse(impulse, (hit["point"] as Vector3) - rb2.global_position)
		body.velocity -= push_dir * v_into * (1.0 - ratio)
