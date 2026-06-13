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

## Speed along the belt's local +Z in metres per second.
var belt_speed_mps : float = 0.0

func _physics_process(_delta: float) -> void:
	constant_linear_velocity = global_transform.basis.z.normalized() * belt_speed_mps
