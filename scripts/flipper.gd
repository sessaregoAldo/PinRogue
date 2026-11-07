@tool
class_name Flipper
extends AnimatableBody2D
## Player-controlled flipper. The pivot is this node's origin; the flipper points
## along +X before rotation. The right flipper uses mirrored angles.
##
## The body is kinematic, so the physics server works out its real angular
## velocity from the rotation change each step and the ball gets launched by the
## contact. On top of that, a "hit assist" Area2D makes sure that a ball touching
## the swinging face leaves with at least the face's surface speed (ω × r). This
## keeps shots reliable even when the contact solver loses energy.

enum FlipperSide { LEFT, RIGHT }

@export var side: FlipperSide = FlipperSide.LEFT
@export var length: float = 70.0
@export var base_radius: float = 12.0
@export var tip_radius: float = 6.0
## Angles for the LEFT flipper (degrees, +ve = clockwise / down). Mirrored for RIGHT.
@export var rest_angle_deg: float = 30.0
@export var active_angle_deg: float = -30.0
@export var up_speed: float = 18.0 # rad/s while swinging up
@export var down_speed: float = 12.0 # rad/s while falling back
## 1.0 = ball leaves at the face's surface speed; 0 disables the assist.
@export var hit_assist: float = 1.0
@export var color: Color = Color(0.95, 0.35, 0.25)

## Current angular speed in rad/s (read-only for other scripts).
var angular_speed: float = 0.0

var _rest: float
var _active: float
var _action: StringName
var _area: Area2D
var _polygon: PackedVector2Array
var _hit_this_swing: Dictionary = {}
var _was_pressed: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_action = &"flipper_left" if side == FlipperSide.LEFT else &"flipper_right"
	if side == FlipperSide.LEFT:
		_rest = deg_to_rad(rest_angle_deg)
		_active = deg_to_rad(active_angle_deg)
	else:
		_rest = PI - deg_to_rad(rest_angle_deg)
		_active = PI - deg_to_rad(active_angle_deg)
	if not Engine.is_editor_hint():
		rotation = _rest

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.0
	mat.friction = 0.6
	physics_material_override = mat

	_polygon = _build_polygon(base_radius, tip_radius)
	var poly := CollisionPolygon2D.new()
	poly.polygon = _polygon
	add_child(poly)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var area_poly := CollisionPolygon2D.new()
	area_poly.polygon = _build_polygon(base_radius + 6.0, tip_radius + 6.0)
	_area.add_child(area_poly)
	add_child(_area)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var pressed := Input.is_action_pressed(_action) and not GameManager.tilted and not GameManager.is_game_over
	if pressed and not _was_pressed:
		Sfx.play("flipper_up", 0.0, 1.0 if side == FlipperSide.LEFT else 1.06, 0)
	elif _was_pressed and not pressed:
		Sfx.play("flipper_down", -6.0, 1.0, 0)
	_was_pressed = pressed
	var target := _active if pressed else _rest
	var speed := up_speed if pressed else down_speed
	var previous := rotation
	rotation = move_toward(rotation, target, speed * delta)
	angular_speed = (rotation - previous) / delta

	if pressed and absf(angular_speed) > 0.01:
		_apply_hit_assist()
	elif not pressed:
		_hit_this_swing.clear()


func _apply_hit_assist() -> void:
	if hit_assist <= 0.0:
		return
	var axis := Vector2.from_angle(rotation)
	for body in _area.get_overlapping_bodies():
		var ball := body as Ball
		if ball == null or not ball.in_play or _hit_this_swing.has(ball):
			continue
		var r := ball.global_position - global_position
		var along := r.dot(axis)
		if along < 0.0 or along > length + tip_radius:
			continue
		var surface_v := Vector2(-angular_speed * r.y, angular_speed * r.x) # ω × r
		if surface_v.length() < 1.0:
			continue
		var n := surface_v.normalized()
		var perp := r - axis * along
		if perp.dot(n) <= 0.0:
			continue # ball is behind the swinging face
		var target := surface_v.length() * hit_assist
		var current := ball.linear_velocity.dot(n)
		if current < target:
			ball.add_impulse(n * (target - current))
		_hit_this_swing[ball] = true


func _build_polygon(r0: float, r1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var dir := Vector2.from_angle(TAU * i / 16.0)
		pts.append(dir * r0)
		pts.append(Vector2(length, 0) + dir * r1)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_set_transform(Vector2.ZERO, _rest) # preview at rest angle
	draw_colored_polygon(_polygon, color)
	var outline := _polygon.duplicate()
	outline.append(_polygon[0])
	draw_polyline(outline, color.darkened(0.4), 2.0, true)
	draw_circle(Vector2.ZERO, 4.0, Color(0.2, 0.2, 0.25))
