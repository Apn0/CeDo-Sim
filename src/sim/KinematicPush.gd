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
# Call AFTER move_and_slide(), passing the body, its real mass (kg), the
# accel time-constant, and the physics delta. `body` must expose `velocity`
# (CharacterBody3D) and the get_slide_collision* API.
static func apply(body: CharacterBody3D, body_mass_kg: float, accel_tau_s: float, delta: float) -> void:
	if body == null or body_mass_kg <= 0.0:
		return
	for i in body.get_slide_collision_count():
		var col := body.get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null or rb.freeze:
			continue
		# Skip a cart currently under grab control (its own controller sets forces).
		if "_grabbed_by" in rb and rb.get("_grabbed_by") != null:
			continue
		# Push direction: horizontal component of "into the contact".
		var push_dir : Vector3 = -col.get_normal()
		push_dir.y = 0.0
		if push_dir.length_squared() < 0.0001:
			continue   # standing on top — no lateral shove
		push_dir = push_dir.normalized()
		var v_into : float = body.velocity.dot(push_dir)
		if v_into <= 0.01:
			continue
		var ratio : float = body_mass_kg / (body_mass_kg + rb.mass)
		var impulse : Vector3 = push_dir * (v_into * ratio) * rb.mass * (delta / accel_tau_s)
		rb.apply_impulse(impulse, col.get_position() - rb.global_position)
		body.velocity -= push_dir * v_into * (1.0 - ratio)
