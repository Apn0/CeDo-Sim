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

func _physics_process(_delta: float) -> void:
	constant_linear_velocity = global_transform.basis.z.normalized() * belt_speed_mps
