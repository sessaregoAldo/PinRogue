@tool
class_name Ball
extends RigidBody2D
## The pinball.
## Every outside change to position or velocity is queued and applied inside
## _integrate_forces, so it never fights the physics server.

const LAYER_TABLE := 1 # physics layer 1: playfield
const LAYER_BALL := 2 # physics layer 2: ball on the playfield
const LAYER_BALL_RAISED := 4 # physics layer 3: ball riding a tunnel

@export var radius: float = 10.0
@export var max_speed: float = 2200.0
@export var bounce: float = 0.2 # added to the surface's bounce on contact
## Bounce of a typical wall, used to scale the combined bounce (Bouncy Ball).
const TYPICAL_SURFACE_BOUNCE := 0.25
@export var friction: float = 0.15
@export var color: Color = Color(0.85, 0.87, 0.92)

## True while the ball is on the table (false while drained / waiting to respawn).
var in_play: bool = false
## The tunnel the ball is currently riding, or null when it's on the playfield.
var ramp: Tunnel = null

## How quickly the ball fades to an outline when it goes under an overpass.
@export var behind_fade_speed: float = 14.0
@export var outline_color: Color = Color(1, 1, 1, 0.95)

var _ramp_bits: int = 0
## Physics frames left with collisions disabled after a teleport. Without this,
## the solver treats the jump as motion through walls and shoves the ball out
## the wrong side (e.g. out of the shooter lane on restart).
## -1 = a teleport is requested but not applied yet; the 2-frame count only
## starts once the physics step has actually moved the ball.
var _collision_hold: int = 0
## 0 = fully visible, 1 = hidden under an overpass (only the outline shows).
var _behind: float = 0.0
var _outline: Node2D

var _pending_position: Variant = null
var _pending_velocity: Variant = null
var _pending_impulse: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("ball")
	collision_layer = LAYER_BALL
	collision_mask = LAYER_TABLE | LAYER_BALL
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	can_sleep = false
	mass = 1.0
	angular_damp = 1.0
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	var mat := PhysicsMaterial.new()
	mat.bounce = bounce
	mat.friction = friction
	physics_material_override = mat
	if not Engine.is_editor_hint():
		set_bounce_mult(GameManager.ball_bounce_mult)

	var shape := CircleShape2D.new()
	shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	# Contact reporting drives the bounce sound.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	# The outline lives on its own top-level draw layer so it shows through
	# anything the ball passes under.
	_outline = Node2D.new()
	_outline.z_as_relative = false
	_outline.z_index = 50
	_outline.draw.connect(_draw_outline)
	add_child(_outline)

	in_play = visible and not freeze


## Wall/post hits click, louder when faster. Bumpers, slingshots and flippers
## play their own sounds.
func _on_body_entered(body: Node) -> void:
	if not in_play or body is Bumper or body is Slingshot or body is Flipper or body is TargetButton:
		return
	var speed := linear_velocity.length()
	if speed < 150.0:
		return
	Sfx.play("bounce", linear_to_db(clampf(speed / 1500.0, 0.15, 1.0)), 1.0, 40)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _pending_position != null:
		state.transform = Transform2D(0.0, _pending_position)
		if _collision_hold != 0:
			_collision_hold = 2 # count from the moment the ball is really there
		_pending_position = null
	if _pending_velocity != null:
		state.linear_velocity = _pending_velocity
		state.angular_velocity = 0.0
		_pending_velocity = null
	if _pending_impulse != Vector2.ZERO:
		state.linear_velocity += _pending_impulse
		_pending_impulse = Vector2.ZERO
	if state.linear_velocity.length() > max_speed:
		state.linear_velocity = state.linear_velocity.limit_length(max_speed)


func _physics_process(_delta: float) -> void:
	if _collision_hold > 0:
		_collision_hold -= 1
		if _collision_hold == 0:
			_apply_layers()


func _process(delta: float) -> void:
	var target := 1.0 if _is_behind_overpass() else 0.0
	_behind = lerpf(_behind, target, 1.0 - exp(-behind_fade_speed * delta))
	queue_redraw() # keep the highlight fixed while the body rotates
	_outline.queue_redraw()


## True when a tunnel above the ball's current level covers it.
func _is_behind_overpass() -> bool:
	if not in_play:
		return false
	for node in get_tree().get_nodes_in_group("tunnels"):
		var tunnel := node as Tunnel
		if tunnel == null or tunnel == ramp:
			continue
		if ramp != null and ramp.z_index >= tunnel.z_index:
			continue # we're riding a tunnel that is above this one
		if tunnel.covers(global_position, radius):
			return true
	return false


func _visual_radius() -> float:
	return radius * 1.12 if ramp != null else radius


func _draw() -> void:
	var alpha := 1.0 - _behind
	if alpha <= 0.01:
		return
	draw_set_transform(Vector2.ZERO, -global_rotation)
	var r := _visual_radius()
	if ramp != null:
		# Raised: cast a shadow on the board below and look slightly bigger (closer).
		draw_circle(Vector2(8, 10), radius, Color(0, 0, 0, 0.35 * alpha))
	draw_circle(Vector2.ZERO, r, Color(color, alpha))
	draw_circle(Vector2(-r * 0.35, -r * 0.35), r * 0.35, Color(1, 1, 1, 0.8 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(0.4, 0.42, 0.5, alpha), 1.5, true)


## Drawn on top of everything; visible only while the ball is under an overpass.
func _draw_outline() -> void:
	if _behind <= 0.01 or not visible:
		return
	var c := Color(outline_color, outline_color.a * _behind)
	_outline.draw_arc(Vector2.ZERO, _visual_radius(), 0.0, TAU, 32, c, 2.0, true)


## Lift the ball onto a tunnel: it now only collides with that tunnel's rails
## (and other raised balls) and is drawn above it. Called by Tunnel.
func enter_ramp(tunnel: Tunnel, rail_bits: int, draw_z: int, damp: float) -> void:
	ramp = tunnel
	_ramp_bits = rail_bits
	z_index = draw_z
	linear_damp = damp
	_apply_layers()


## Drop the ball back onto the playfield.
func leave_ramp() -> void:
	ramp = null
	_ramp_bits = 0
	z_index = 0
	linear_damp = 0.0
	_apply_layers()


## Queue a position change for the next physics step.
func teleport(pos: Vector2) -> void:
	_pending_position = pos


## Queue a velocity change for the next physics step.
func set_velocity_safe(v: Vector2) -> void:
	_pending_velocity = v


## Add a velocity change (mass is 1, so impulse == delta-v).
func add_impulse(dv: Vector2) -> void:
	_pending_impulse += dv


## Push the ball away along `normal` at `speed`, keeping part of its sideways motion.
## Used by bumpers and slingshots.
func kick(normal: Vector2, speed: float, keep_tangent: float = 0.8) -> void:
	var n := normal.normalized()
	var v := linear_velocity
	var tangent := v - n * v.dot(n)
	set_velocity_safe(tangent * keep_tangent + n * speed)


## Take the ball off the table (drain). Safe to call from signal callbacks.
func remove_from_play() -> void:
	in_play = false
	visible = false
	call_deferred("_set_frozen", true)


## Put the ball on the table at `pos` with velocity `vel`. Safe to call from signal callbacks.
func place(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> void:
	call_deferred("_do_place", pos, vel)


func _do_place(pos: Vector2, vel: Vector2) -> void:
	_collision_hold = -1 # collisions stay off until the teleport has happened + 2 frames
	if freeze:
		global_position = pos
	leave_ramp()
	_set_frozen(false)
	teleport(pos)
	set_velocity_safe(vel)
	_pending_impulse = Vector2.ZERO
	visible = true
	in_play = true


func _set_frozen(frozen: bool) -> void:
	freeze = frozen
	_apply_layers()


func _apply_layers() -> void:
	if freeze or _collision_hold != 0:
		collision_layer = 0
		collision_mask = 0
	elif ramp != null:
		collision_layer = LAYER_BALL_RAISED
		collision_mask = _ramp_bits | LAYER_BALL_RAISED
	else:
		collision_layer = LAYER_BALL
		collision_mask = LAYER_TABLE | LAYER_BALL


## Bouncy Ball power-up: scale how hard the ball rebounds. Godot adds the ball's
## bounce to the surface's, so the ball's share is set to make a typical wall
## bounce `mult` times as much as normal.
func set_bounce_mult(mult: float) -> void:
	var mat := physics_material_override
	if mat == null:
		return
	mat.bounce = clampf((TYPICAL_SURFACE_BOUNCE + bounce) * mult - TYPICAL_SURFACE_BOUNCE, 0.0, 0.9)
