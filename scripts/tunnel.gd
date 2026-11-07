@tool
class_name Tunnel
extends Node2D
## Raised tunnel/ramp (a "habitrail") running above the playfield.
##
## How it works:
## - Rails are generated from the `path` centerline on their own physics layer.
##   A ball on the playfield doesn't collide with them, so it rolls *under* the tunnel.
## - The ball is raised only when it crosses the mouth (path[0]) moving forward,
##   faster than `min_entry_speed` and within `entry_angle_deg` of the tunnel's direction.
##   Any other approach just passes underneath.
## - While raised, the ball physically rides the rails (gravity still pulls, so
##   weak shots roll back out of the mouth and drop to the playfield).
## - Crossing the far end (the last path point) drops the ball back onto the playfield and scores.
##
## Put this node at the scene origin (or at least unrotated). `path` is in local coordinates.
## Tunnels that cross each other need different `rail_layer` and `z_index` values.

const LAYER_TABLE := 1

@export var path: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0, -200)]):
	set(value):
		path = value
		_rebuild()
@export var width: float = 34.0:
	set(value):
		width = value
		_rebuild()
## Catmull-Rom subdivisions per path segment (higher = smoother curves).
@export_range(1, 16) var smoothing: int = 6:
	set(value):
		smoothing = value
		_rebuild()
## Physics layer number (4-8) used by this tunnel's rails.
@export_range(4, 8) var rail_layer: int = 4:
	set(value):
		rail_layer = value
		_rebuild()
@export var rail_thickness: float = 4.0:
	set(value):
		rail_thickness = value
		_rebuild()
## Small posts on the playfield at the mouth corners.
@export var entrance_posts: bool = true:
	set(value):
		entrance_posts = value
		_rebuild()
@export_group("Entry")
@export var min_entry_speed: float = 300.0
@export_range(5.0, 89.0) var entry_angle_deg: float = 50.0
@export_group("Ride")
## Extra rolling drag while the ball is on the tunnel.
@export var ramp_damp: float = 0.3
## The ball's speed is capped at this when it drops out of the far end.
@export var exit_max_speed: float = 400.0
@export var score_value: int = 1000
@export var color: Color = Color(0.4, 0.75, 1.0):
	set(value):
		color = value
		queue_redraw()
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Tunnel"
@export_group("Booster")
## Push the ball along the track once it is past `booster_from`.
@export var booster_enabled: bool = true:
	set(value):
		booster_enabled = value
		queue_redraw()
## Where the booster section starts and ends, as a fraction of the track length.
@export_range(0.0, 1.0) var booster_from: float = 0.5:
	set(value):
		booster_from = value
		queue_redraw()
@export_range(0.0, 1.0) var booster_to: float = 0.95:
	set(value):
		booster_to = value
		queue_redraw()
## The booster tops the ball's speed along the track up to this...
@export var booster_speed: float = 650.0
## ...accelerating at most this fast (px/s²).
@export var booster_accel: float = 5000.0

var _center := PackedVector2Array()
var _cum := PackedFloat32Array() # distance along the centerline at each point
var _length: float = 0.0
var _boost_glow: float = 0.0
var _anim: float = 0.0
var _left := PackedVector2Array()
var _right := PackedVector2Array()
var _prev_pos: Dictionary = {} # Ball -> last local position
var _stall_time: Dictionary = {} # Ball -> seconds spent nearly stopped on the rails
func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group("tunnels")


## True if a circle at `global_point` with radius `extra` overlaps this tunnel's
## footprint. The ball uses this to know when it's hidden underneath.
func covers(global_point: Vector2, extra: float = 0.0) -> bool:
	if _center.size() < 2:
		return false
	return _distance_to_track(to_local(global_point)) < width * 0.5 + rail_thickness * 0.5 + extra


func _distance_to_track(p: Vector2) -> float:
	var best := INF
	for i in _center.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, _center[i], _center[i + 1])
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


# --- Gameplay -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _center.size() < 2:
		return
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null:
			continue
		if not ball.in_play:
			_prev_pos.erase(ball)
			continue
		var cur := to_local(ball.global_position)
		var prev: Vector2 = _prev_pos.get(ball, cur)
		_prev_pos[ball] = cur
		var step := cur - prev
		if step.length_squared() < 0.0001 or step.length() > 60.0:
			continue # not moving, or teleported

		if ball.ramp == null:
			if _crosses(prev, cur, _left[0], _right[0]) and step.dot(_mouth_dir()) > 0.0 \
					and _entry_allowed(ball.linear_velocity):
				ball.enter_ramp(self, 1 << (rail_layer - 1), z_index + 1, ramp_damp)
				_stall_time[ball] = 0.0
				Sfx.play("ramp_enter")
		elif ball.ramp == self:
			var last := _center.size() - 1
			if _crosses(prev, cur, _left[last], _right[last]) and step.dot(_exit_dir()) > 0.0:
				ball.leave_ramp()
				ball.set_velocity_safe(ball.linear_velocity.limit_length(exit_max_speed))
				GameManager.add_score(score_value, to_global(_center[_center.size() - 1]))
				Sfx.play("ramp_land")
				Sfx.play("ramp_complete")
			elif _crosses(prev, cur, _left[0], _right[0]) and step.dot(_mouth_dir()) < 0.0:
				ball.leave_ramp() # rolled back out of the mouth
				Sfx.play("ramp_land", -6.0)
			else:
				_apply_booster(ball, cur, delta)
				_check_stall(ball, delta)


## Past the halfway mark, accelerate the ball along the track so it makes it through.
func _apply_booster(ball: Ball, local_pos: Vector2, delta: float) -> void:
	if not booster_enabled or _length <= 0.0:
		return
	var info := _track_info(local_pos)
	var progress: float = info[0] / _length
	if progress < booster_from or progress > booster_to:
		return
	var tangent := global_transform.basis_xform(info[1]).normalized()
	var along := ball.linear_velocity.dot(tangent)
	if along < booster_speed:
		if _boost_glow < 0.2:
			Sfx.play("booster", -4.0, 1.0, 250)
		ball.add_impulse(tangent * minf(booster_accel * delta, booster_speed - along))
		_boost_glow = 1.0


## [distance along the track, unit tangent] for the point on the centerline closest to `p`.
func _track_info(p: Vector2) -> Array:
	var best := INF
	var best_s := 0.0
	var best_t := Vector2.RIGHT
	for i in _center.size() - 1:
		var a := _center[i]
		var b := _center[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			best_s = _cum[i] + a.distance_to(q)
			best_t = (b - a).normalized()
	return [best_s, best_t]


## Point and tangent at distance `s` along the track (for drawing).
func _sample(s: float) -> Array:
	for i in _center.size() - 1:
		if s <= _cum[i + 1] or i == _center.size() - 2:
			var seg := _cum[i + 1] - _cum[i]
			var t := 0.0 if seg <= 0.0 else clampf((s - _cum[i]) / seg, 0.0, 1.0)
			return [_center[i].lerp(_center[i + 1], t), (_center[i + 1] - _center[i]).normalized()]
	return [_center[0], Vector2.RIGHT]


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not booster_enabled:
		return
	_anim += delta
	_boost_glow = maxf(0.0, _boost_glow - delta * 2.0)
	queue_redraw() # animate the booster chevrons


func _entry_allowed(velocity: Vector2) -> bool:
	var dir := global_transform.basis_xform(_mouth_dir()).normalized()
	var speed := velocity.length()
	if speed < 0.001 or velocity.dot(dir) < min_entry_speed:
		return false
	return velocity.angle_to(dir) <= deg_to_rad(entry_angle_deg) \
			and velocity.angle_to(dir) >= -deg_to_rad(entry_angle_deg)


## Safety net: a ball that somehow stops on the rails drops through.
func _check_stall(ball: Ball, delta: float) -> void:
	if ball.linear_velocity.length() < 8.0:
		_stall_time[ball] = float(_stall_time.get(ball, 0.0)) + delta
		if _stall_time[ball] > 1.5:
			ball.leave_ramp()
	else:
		_stall_time[ball] = 0.0


func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(a, b, c, d) != null


func _mouth_dir() -> Vector2:
	return (_center[1] - _center[0]).normalized()


func _exit_dir() -> Vector2:
	var n := _center.size()
	return (_center[n - 1] - _center[n - 2]).normalized()


# --- Geometry -----------------------------------------------------------------

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	_center = _smooth(path, smoothing)
	if _center.size() < 2:
		queue_redraw()
		return
	_cum = PackedFloat32Array([0.0])
	for i in range(1, _center.size()):
		_cum.append(_cum[i - 1] + _center[i - 1].distance_to(_center[i]))
	_length = _cum[_cum.size() - 1]
	_left = _offset(_center, width * 0.5)
	_right = _offset(_center, -width * 0.5)

	var bits := 1 << (rail_layer - 1)
	_add_rail(_left, bits)
	_add_rail(_right, bits)

	if entrance_posts:
		var posts := StaticBody2D.new()
		posts.collision_layer = LAYER_TABLE
		posts.collision_mask = 0
		posts.set_meta("generated", true)
		for p in [_left[0], _right[0]]:
			var circle := CircleShape2D.new()
			circle.radius = 4.0
			var cs := CollisionShape2D.new()
			cs.shape = circle
			cs.position = p
			posts.add_child(cs)
		add_child(posts)
	queue_redraw()


func _add_rail(points: PackedVector2Array, bits: int) -> void:
	var rail := Wall.new()
	rail.physics_layers = bits
	rail.thickness = rail_thickness
	rail.bounce = 0.1
	rail.color = Color(0.85, 0.88, 0.95)
	rail.points = points
	rail.set_meta("generated", true)
	add_child(rail)


func _smooth(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	if pts.size() < 3 or steps <= 1:
		return pts
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


## Offset a polyline sideways by `dist` (positive = left of travel direction), mitered.
func _offset(pts: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d_prev := (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d_next := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else d_prev
		var tangent := (d_prev + d_next).normalized()
		if tangent == Vector2.ZERO:
			tangent = d_prev
		var normal := tangent.orthogonal()
		var miter := 1.0 / maxf(0.35, normal.dot(d_prev.orthogonal()))
		out.append(pts[i] + normal * dist * miter)
	return out


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	if _center.size() < 2:
		return
	var shadow_offset := Vector2(8, 10)
	for i in _center.size() - 1:
		var quad := PackedVector2Array([_left[i], _left[i + 1], _right[i + 1], _right[i]])
		var shadow := PackedVector2Array()
		for p in quad:
			shadow.append(p + shadow_offset)
		draw_primitive(shadow, PackedColorArray([Color(0, 0, 0, 0.22)]), PackedVector2Array())
		draw_primitive(quad, PackedColorArray([Color(color, 0.32)]), PackedVector2Array())
	# Chevrons at the mouth show which way the ball has to be going to get in.
	var dir := _mouth_dir()
	var side := dir.orthogonal() * width * 0.3
	for k in 2:
		var base := _center[0] + dir * (10.0 + k * 12.0)
		draw_polyline(PackedVector2Array([base + side, base + dir * 8.0, base - side]), color, 3.0, true)
	# Booster section: chevrons scrolling toward the exit, brighter while pushing.
	if booster_enabled and _length > 0.0:
		var spacing := 22.0
		var start := _length * booster_from
		var finish := _length * booster_to
		var shift := fmod(_anim * 60.0, spacing)
		var s := start + shift
		while s < finish:
			var sample := _sample(s)
			var p: Vector2 = sample[0]
			var t: Vector2 = sample[1]
			var side_v := t.orthogonal() * width * 0.28
			var fade := clampf(minf(s - start, finish - s) / 20.0, 0.0, 1.0)
			var c := Color(1.0, 0.95, 0.5).lerp(Color.WHITE, _boost_glow)
			c.a = (0.35 + 0.55 * _boost_glow) * fade
			draw_polyline(PackedVector2Array([p - t * 5.0 + side_v, p + t * 4.0, p - t * 5.0 - side_v]), c, 2.5, true)
			s += spacing
	# Mouth and exit lips.
	var last := _center.size() - 1
	draw_line(_left[0], _right[0], Color(color, 0.9), 3.0, true)
	draw_line(_left[last], _right[last], Color(color, 0.5), 2.0, true)
