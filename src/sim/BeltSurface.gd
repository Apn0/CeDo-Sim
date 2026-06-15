class_name BeltSurface
extends StaticBody3D

## #conveyorphysics — Hooks Godot's built-in StaticBody3D.constant_linear_velocity
## into the belt body so any RigidBody3D resting on the deck gets dragged along
## the surface via contact friction. The belt's local +Z is the conveying axis;
## we refresh constant_linear_velocity each physics tick from the live transform
## so rotating the placed belt (Y-axis yaw via the build-mode jog) just works —
## the world-space drag direction follows.
##
## CharacterBody3D is NOT pushed by constant_linear_velocity (Godot's character
## controller doesn't read surface friction the way RigidBody3D does), so the
## player is still carried by the manual hack in PlayerController._apply_belt_carry.
## Everything else — bales, the lump_cart, dropped tools, any RB body the
## operator parks on the belt — is now physicalized.

## Speed along the belt's FORWARD direction (line march direction) in m/s.
## CANONICAL CONVENTION: downstream = body LOCAL +Z. This is consistent with:
##   • BeltBuilder.build_chute() puts the discharge chute at local +Z (size.z * 0.50).
##   • ShredderFeedBelt deck/incline geometry extends along local +Z.
##   • belt_scroll.gdshader with positive scroll_speed scrolls texture toward +Z.
##   • BuildMode._build_full_line marches ghost along ghost-local -Z, but adds
##     `rot_y + PI` to each placed node so the placed body's local +Z = world
##     march direction (i.e. downstream).
##   • Gauntlet station 210 placard expects the test cube to travel toward +Z
##     (away from the sign side) — and the chute on the gauntlet's no-rotation
##     placement is at local +Z.
## So carry must drive along +basis.z. (Was flipped to -basis.z this session
## from a mis-read of the macro; restored here.)
var belt_speed_mps : float = 0.0

# ── Audit item 6 — belt-to-belt projectile receiver zones ────────────────────
# Calibrated belt-to-belt aim lands material inside a SAFE_ZONE of ±0.15 m
# along the receiver's local Z (no jitter — this models the operator-calibrated
# belt geometry where the upstream chute is aimed precisely at the centre of
# the downstream belt). Around that, a SPREAD_ZONE of ±0.30 m allows realistic
# scatter sampled from a normal distribution (clamped to ±0.45 m so the rare
# tail can never throw a flake off the deck). BeltBuilder.apply_tagging writes
# the default values onto every belt as meta("safe_zone_m"/"spread_zone_m");
# this script just exposes them as typed fields and provides the ballistic
# helper compute_belt_to_belt_landing() that LineFlow / MachineFlow use when
# they animate a discharge → receiver hand-off.
var safe_zone_m   : float = 0.15
var spread_zone_m : float = 0.30

func _ready() -> void:
	# Refresh the typed fields from meta so a belt whose meta was overridden in
	# the spec (e.g. switch belt with wider spread) ends up with the right values.
	if has_meta("safe_zone_m"):
		safe_zone_m = float(get_meta("safe_zone_m"))
	if has_meta("spread_zone_m"):
		spread_zone_m = float(get_meta("spread_zone_m"))

func _physics_process(_delta: float) -> void:
	constant_linear_velocity = global_transform.basis.z.normalized() * belt_speed_mps

# ── Projectile arc helper ────────────────────────────────────────────────────
## Compute where a piece of material discharged at `exit_world` with horizontal
## launch velocity `belt_velocity_world` will land on the receiver belt's TOP
## surface. Returns a Dictionary:
##   { "land_world": Vector3, "land_local_z": float, "flight_time_s": float }
## Uses constant gravity (-9.8 m/s² along Y). The receiver belt's top-surface
## height is read from receiver.get_meta("belt_top_y_world") when present;
## otherwise it falls back to the belt's own global_position.y (good enough
## for flat decks, off by half-thickness for sloped decks — callers that care
## can override via meta).
##
## After the arc finishes, the caller samples a SPREAD offset along the
## receiver's local Z via apply_belt_spread() so material lands inside the
## SPREAD_ZONE band centred on the SAFE_ZONE aim point.
static func compute_belt_to_belt_landing(exit_world: Vector3,
		belt_velocity_world: Vector3, receiver: Node3D) -> Dictionary:
	var out := {
		"land_world":     exit_world,
		"land_local_z":   0.0,
		"flight_time_s":  0.0,
	}
	if receiver == null or not is_instance_valid(receiver):
		return out
	# Receiver belt top surface — meta override wins for sloped / elevated decks.
	var receiver_top_y : float = receiver.global_position.y
	if receiver.has_meta("belt_top_y_world"):
		receiver_top_y = float(receiver.get_meta("belt_top_y_world"))
	# Ballistic free-fall from exit_world to receiver_top_y under gravity g.
	# y(t) = y0 + vy*t - 0.5*g*t^2  ⇒  solve for the positive t at y=receiver_top_y.
	var g : float = 9.8
	var dy : float = exit_world.y - receiver_top_y
	# Vertical launch speed defaults to zero (belt discharges horizontally), but
	# callers may pass a non-zero Y component if the source deck is tilted.
	var vy0 : float = belt_velocity_world.y
	var disc : float = vy0 * vy0 + 2.0 * g * dy
	if disc < 0.0:
		# Receiver is ABOVE the exit point — can't land via free-fall. Fall
		# back to a straight-line hand-off (model "material is gently nudged
		# across a tiny gap" rather than throw a flying error).
		out["flight_time_s"] = 0.0
		out["land_world"]    = Vector3(receiver.global_position.x,
			receiver_top_y, receiver.global_position.z)
	else:
		var t : float = (vy0 + sqrt(disc)) / g     # quadratic positive root
		var land := Vector3(
			exit_world.x + belt_velocity_world.x * t,
			receiver_top_y,
			exit_world.z + belt_velocity_world.z * t)
		out["flight_time_s"] = t
		out["land_world"]    = land
	# Decompose the landing point into the receiver belt's local frame so the
	# Z-coordinate is comparable to safe_zone_m / spread_zone_m (which are
	# defined along local +Z, the conveying axis).
	var local : Vector3 = receiver.to_local(out["land_world"])
	out["land_local_z"] = local.z
	return out

## Sample a SPREAD offset along the receiver's local Z. Returns a world-space
## Vector3 to ADD to the land_world coordinate returned by
## compute_belt_to_belt_landing(). The offset is drawn from a normal
## distribution with std-dev = spread_zone_m and clamped to ±(safe_zone_m +
## spread_zone_m * 1.5), so the worst-case rare tail still lands on the deck.
## Inside the SAFE_ZONE (±safe_zone_m) the spread is suppressed (the belt is
## calibrated to land material there); outside, the normal distribution lets a
## flake scatter naturally onto the deck.
func apply_belt_spread(rng: RandomNumberGenerator) -> Vector3:
	# Sample a normal-dist offset, clamped to a finite band so we never miss
	# the deck. The SAFE_ZONE is modelled by REJECTING samples whose magnitude
	# falls inside ±safe_zone_m — operator-calibrated belt aim means flakes
	# are NOT scattered there. After two rejections we accept anyway so the
	# distribution can't deadlock on a degenerate seed.
	var sample : float = 0.0
	for _i in 3:
		sample = rng.randfn(0.0, spread_zone_m)
		if absf(sample) >= safe_zone_m:
			break
	var clamp_m : float = safe_zone_m + spread_zone_m * 1.5
	sample = clampf(sample, -clamp_m, clamp_m)
	# Project the local-Z offset back into world space using the belt's
	# current basis (so a yawed belt still scatters along its conveying axis).
	return global_transform.basis.z.normalized() * sample
