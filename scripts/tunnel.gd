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
## Drop shadow layers: [share of the track's height it drops, extra width per
## side, alpha] (outer = softer). Shadows fall straight down the table.
const SHADOW_LAYERS := [[1.0, 7.0, 0.07], [0.72, 4.0, 0.09], [0.45, 1.0, 0.13]]
const RAIL_COLOR := Color(0.85, 0.88, 0.95)
const POST_COLOR := Color(0.55, 0.5, 0.55)

## A ball rode this track (and any ramps chained after it) all the way out.
signal completed(ball: Ball)
## A ball was lifted onto this track (its mouth, or from a chained ramp).
signal entered(ball: Ball)

@export var path: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0, -200)]):
	set(value):
		path = value
		_rebuild()
@export var width: float = 34.0:
	set(value):
		width = value
		_rebuild()
## Catmull-Rom subdivisions per path segment (higher = smoother curves).
@export_range(1, 16) var smoothing: int = 10:
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
## The mouth flares open by this many px per side, narrowing to the track width
## over `flare_length` px: a funnel that guides off-center shots in.
@export var mouth_flare: float = 10.0:
	set(value):
		mouth_flare = value
		_rebuild()
@export var flare_length: float = 70.0:
	set(value):
		flare_length = value
		_rebuild()
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
## How strongly the rails steer the ball along the track (sideways motion is
## damped at this rate per second), so fast shots follow the curves instead of
## ricocheting between the rails and back out of the mouth.
@export var guide_strength: float = 14.0
## The ball leaves the far end with the speed it had on the ramp (the booster's
## push included), aimed along the end of the track, up to this.
@export var exit_max_speed: float = 1400.0
@export var score_value: int = 1000
## Lands on this upper deck (UpperDeck) at the far end instead of the playfield.
@export var to_deck: NodePath
## Chained ramps: at the far end the ball goes straight on into this ramp
## instead of dropping to the table (lets a track cross itself: the next ramp
## sits on its own rail layer, a level higher).
@export var next_ramp: NodePath
## A ball on the table can enter at the mouth. Off for a ramp that is only
## reached from another one (`next_ramp`).
@export var table_entry: bool = true
## Keep the track up at that end (no slope down to the table), for the ends
## where a chained ramp hands over.
@export var raised_start: bool = false
@export var raised_end: bool = false
## With raised_start: the height the track starts at (a chained ramp picking up
## where a lower one ends), climbing to lift_height over `ramp_rise` px. -1 = off.
@export var start_lift: float = -1.0
## How long the climb from (and down to) the table is, at most.
@export var ramp_rise: float = 140.0
## Show the whole track whenever a ball rides this ramp or that one (chained ramps).
@export var reveal_with: NodePath
## From the table: hide the mouth too (a ramp reached only from another), and/or
## keep the last `shown_end` px visible (where the ball comes back down).
@export var hide_mouth: bool = false
@export var shown_end: float = 0.0
## Support posts: one every `post_spacing` px; off for a track carried by another's.
@export var post_spacing: float = 70.0
## Friction of the rails. 0: a fast ball doesn't lose speed pressing into a curve.
@export var rail_friction: float = 0.2
@export var posts_shown: bool = true
## How fast the track fades back out once no ball rides it (per second; 5 = 0.2 s).
@export var fade_out_speed: float = 5.0
## While a ball rides it, show the track only up to this far ahead of the ball
## (it grows with the ball). -1: the whole track at once. With reveal_with, a
## ball on that ramp shows this one's start once the window reaches past its end.
@export var lookahead: float = -1.0
## While a ball rides it, hide the track more than this far behind the ball (the
## trail fades out after it). -1: keep it. With next_ramp, a ball that has gone
## on into that ramp still shows this one's last stretch until the trail passes.
@export var lookbehind: float = -1.0
@export var color: Color = Color(0.4, 0.75, 1.0):
	set(value):
		color = value
		queue_redraw()
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Tunnel"
@export_group("Look")
## How much of the track, from the mouth, is always shown. The rest only
## appears while a ball rides it (0 = always show the whole track).
@export var shown_length: float = 40.0:
	set(value):
		shown_length = value
		queue_redraw()
## Over how many px the always-shown part fades out.
@export var shown_fade: float = 90.0
## How long the preview (shown_length, from the table) takes to fade out (px).
@export var preview_fade: float = 60.0
## How high the track runs: how far its shadow falls (and its posts reach) at the
## top. Tracks to an upper deck climb all the way; the others rise and come back down.
@export var lift_height: float = 30.0:
	set(value):
		lift_height = value
		queue_redraw()
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
## Also keep the ball from going faster than booster_speed (downhill, gravity
## included): it rides the booster's stretch at one steady speed.
@export var booster_holds_speed: bool = false

var _center := PackedVector2Array()
var _cum := PackedFloat32Array() # distance along the centerline at each point
var _length: float = 0.0
var _boost_glow: float = 0.0
var _anim: float = 0.0
var _left := PackedVector2Array()
var _right := PackedVector2Array()
var _prev_pos: Dictionary = {} # Ball -> last local position
var _stall_time: Dictionary = {} # Ball -> seconds spent nearly stopped on the rails
var _last_along: Dictionary = {} # Ball -> speed along the track last step (guide)
## Draws only the moving booster chevrons, every frame. The tunnel body is drawn
## once (it never changes), which keeps phones from redrawing hundreds of shapes
## per frame.
var _fx: Node2D
## 0 = only the first `shown_length` px show, 1 = the whole track (a ball is riding it).
var _reveal: float = 0.0
## Tracks to an upper deck: the deck, and how far along the track its edge is
## (the track isn't drawn past it: under the deck it is hidden by the floor).
var _deck: Node2D
var _deck_edge: float = -1.0
var _draw_count: int = 0 # centerline points drawn (all of them, or up to the deck's edge)


func _ready() -> void:
	_fx = Node2D.new()
	_fx.draw.connect(_draw_booster)
	add_child(_fx)
	move_child(_fx, 0) # under the rails, like the rest of the track
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group("tunnels")


## True if a circle at `global_point` with radius `extra` overlaps this tunnel's
## footprint. The ball uses this to know when it's hidden underneath.
func covers(global_point: Vector2, extra: float = 0.0) -> bool:
	if _center.size() < 2:
		return false
	var p := to_local(global_point)
	if _distance_to_track(p) >= width * 0.5 + rail_thickness * 0.5 + extra:
		return false
	var s: float = _track_info(p)[0]
	return shown_at(s) > 0.5 and (_deck_edge < 0.0 or s < _deck_edge)


## How visible the track is `s` px along it (0..1).
func shown_at(s: float) -> float:
	if shown_length <= 0.0 or Engine.is_editor_hint():
		return 1.0
	var base := 0.0 if hide_mouth else 1.0 - smoothstep(shown_length, shown_length + preview_fade, s)
	if shown_end > 0.0:
		base = maxf(base, smoothstep(_length - shown_end - shown_fade, _length - shown_end, s))
	if (lookahead >= 0.0 or lookbehind >= 0.0) and not _forced:
		var ahead := 1.0
		if lookahead >= 0.0:
			ahead = 0.0 if _reach <= 0.0 else 1.0 - smoothstep(_reach, _reach + shown_fade, s)
		var behind := 1.0
		if lookbehind >= 0.0:
			behind = smoothstep(_tail - shown_fade, _tail, s)
		return maxf(base, ahead * behind * _reveal)
	return lerpf(base, 1.0, _reveal)


## How far along this track a ball has got (px).
func progress_of(ball: Ball) -> float:
	return _track_info(to_local(ball.global_position))[0]


## The window a riding ball lets the player see along this track (on this ramp,
## the one it's chained from, or the one it went on into): [reach, tail] in px.
## reach -1 = no rider.
func _rider_window() -> Array:
	var reach := -1.0
	var tail := NO_TAIL
	var before := get_node_or_null(reveal_with) as Tunnel
	var after := get_node_or_null(next_ramp) as Tunnel
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null or not ball.in_play or ball.ramp == null:
			continue
		if ball.ramp == self:
			var at := progress_of(ball)
			reach = maxf(reach, at + maxf(lookahead, 0.0))
			tail = maxf(tail, at - lookbehind)
		elif before != null and ball.ramp == before:
			reach = maxf(reach, before.progress_of(ball) + maxf(lookahead, 0.0) - before._length)
		elif after != null and ball.ramp == after and lookbehind >= 0.0:
			reach = maxf(reach, _length + shown_fade)
			tail = maxf(tail, _length + after.progress_of(ball) - lookbehind)
	return [reach, tail]


## How high the track is drawn `s` px along it (px).
func _lift_at(s: float) -> float:
	var h := height_along(s)
	if raised_start and start_lift >= 0.0:
		var rise := minf(_length * 0.3, ramp_rise)
		return lerpf(start_lift, lift_height, smoothstep(0.0, rise, s)) * h
	return lift_height * h


## The track's height `s` px along it: 0 on the table, 1 at the top (an upper
## deck's level for tracks that lead to one).
func height_along(s: float) -> float:
	if _deck_edge > 0.0:
		return smoothstep(0.0, _deck_edge, s)
	var rise := minf(_length * 0.3, ramp_rise)
	if rise <= 0.0:
		return 0.0
	var up := 1.0 if raised_start else smoothstep(0.0, rise, s)
	var down := 1.0 if raised_end else smoothstep(_length, _length - rise, s)
	return minf(up, down)


## Height (0..1) of the track at the point nearest `global_point`.
func height_at(global_point: Vector2) -> float:
	if _center.size() < 2:
		return 0.0
	return height_along(_track_info(to_local(global_point))[0])


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

		if ball.deck != null:
			continue # up on a deck: the ramps below don't exist for it
		if ball.ramp == null:
			if table_entry and _crosses(prev, cur, _left[0], _right[0]) and step.dot(_mouth_dir()) > 0.0 \
					and _entry_allowed(ball.linear_velocity):
				take_ball(ball)
				Sfx.play("ramp_enter")
		elif ball.ramp == self:
			var last := _center.size() - 1
			if _crosses(prev, cur, _left[last], _right[last]) and step.dot(_exit_dir()) > 0.0:
				# Keep the momentum: same speed, pointed out of the end of the track.
				var speed := minf(ball.linear_velocity.length(), exit_max_speed)
				var chained := get_node_or_null(next_ramp) as Tunnel
				if chained:
					chained.take_ball(ball) # straight on, still up in the air
					continue
				var upper := get_node_or_null(to_deck) as Node2D
				if upper:
					ball.enter_deck(upper)
				else:
					ball.leave_ramp()
				ball.set_velocity_safe(_exit_dir() * speed)
				GameManager.add_score(score_value * (1 + GameManager.ramp_turbo), to_global(_center[_center.size() - 1]))
				Sfx.play("ramp_land")
				Sfx.play("ramp_complete")
				completed.emit(ball)
			elif _crosses(prev, cur, _left[0], _right[0]) and step.dot(_mouth_dir()) < 0.0:
				ball.leave_ramp() # rolled back out of the mouth
				Sfx.play("ramp_land", -6.0)
			else:
				_guide(ball, cur, delta)
				_apply_booster(ball, cur, delta)
				_check_stall(ball, delta)


## Lift the ball onto this track (its mouth, or the end of a chained ramp).
func take_ball(ball: Ball) -> void:
	entered.emit(ball)
	var draw_z := z_index + 1
	if _deck:
		draw_z = maxi(draw_z, _deck.z_index + 2) # its end runs under the deck's floor
	ball.enter_ramp(self, 1 << (rail_layer - 1), draw_z, ramp_damp)
	_prev_pos[ball] = to_local(ball.global_position)
	_stall_time[ball] = 0.0
	_last_along.erase(ball)


## Steer the ball along the track: damp its sideways motion (relative to the
## track direction) and never let a rail collision flip a fast forward ride into
## a backward one. A ball that is genuinely too slow still rolls back.
func _guide(ball: Ball, local_pos: Vector2, delta: float) -> void:
	if guide_strength <= 0.0:
		return
	var info := _track_info(local_pos)
	var tangent := global_transform.basis_xform(info[1]).normalized()
	var v := ball.linear_velocity
	var along := v.dot(tangent)
	# A ball going forward fast cannot reverse in a single step except by a hard
	# rail impact: keep it going forward (a real rollback slows down gradually).
	var last_along: float = _last_along.get(ball, along)
	_last_along[ball] = along
	if last_along > 300.0 and along < -50.0:
		ball.set_velocity_safe(tangent * v.length() * 0.7)
		_last_along[ball] = v.length() * 0.7
		return
	var sideways := v - tangent * along
	var k := 1.0 - exp(-guide_strength * delta)
	# Sideways energy is redirected along the track in the current direction of travel.
	var redirect := sideways.length() * k * (1.0 if along >= 0.0 else -1.0) * 0.85
	ball.add_impulse(-sideways * k + tangent * redirect)


## Past the halfway mark, accelerate the ball along the track so it makes it through.
func _apply_booster(ball: Ball, local_pos: Vector2, delta: float) -> void:
	if (not booster_enabled and GameManager.ramp_turbo <= 0) or _length <= 0.0:
		return
	var info := _track_info(local_pos)
	var progress: float = info[0] / _length
	var from := 0.0 if GameManager.ramp_turbo > 0 else booster_from # Turbo Ramps power-up
	if progress < from or progress > booster_to:
		return
	var tangent := global_transform.basis_xform(info[1]).normalized()
	var along := ball.linear_velocity.dot(tangent)
	if booster_holds_speed and along > booster_speed:
		ball.add_impulse(-tangent * minf(booster_accel * delta, along - booster_speed))
		return
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
	if Engine.is_editor_hint():
		return
	var target := 1.0 if _has_rider() or _forced else 0.0
	if _reveal != target and shown_length > 0.0 and not (_force_tween and _force_tween.is_running()):
		_reveal = move_toward(_reveal, target, delta * (5.0 if target > _reveal else fade_out_speed))
		queue_redraw()
	if lookahead >= 0.0 or lookbehind >= 0.0:
		var win := _rider_window()
		if win[0] > _reach or win[1] > _tail:
			_reach = maxf(_reach, win[0]) # the window only ever moves forward during a ride
			_tail = maxf(_tail, win[1])
			queue_redraw()
		elif win[0] < 0.0 and _reveal <= 0.0:
			_reach = 0.0
			_tail = NO_TAIL
	if not booster_enabled:
		return
	_anim += delta
	_boost_glow = maxf(0.0, _boost_glow - delta * 2.0)
	_fx.queue_redraw() # animate the booster chevrons


var _forced: bool = false
var _reach: float = 0.0 # lookahead: shown up to here (px along the track)
var _tail: float = NO_TAIL # lookbehind: hidden before here
const NO_TAIL := -100000.0
var _force_tween: Tween

## Show the whole track (or let it go back to normal), also while the game is
## paused: story mode points it out, upgrade placement shows its deck.
func set_forced(on: bool) -> void:
	if on == _forced:
		return
	_forced = on
	if _force_tween:
		_force_tween.kill()
	var target := 1.0 if on or _has_rider() else 0.0
	_force_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_force_tween.tween_method(func(v: float) -> void:
		_reveal = v
		queue_redraw(), _reveal, target, 0.35).set_trans(Tween.TRANS_SINE)


## A ball is riding this track (not counting one that has gone up onto its deck).
func _has_rider() -> bool:
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		# (A ball that has gone up onto this track's deck no longer counts: the
		# track fades and the deck is drawn without it.)
		if ball and ball.in_play and ball.ramp == self:
			return true
		if ball and ball.in_play and ball.ramp != null and not reveal_with.is_empty() 				and ball.ramp == get_node_or_null(reveal_with):
			return true
		if ball and ball.in_play and ball.ramp != null and lookbehind >= 0.0 and not next_ramp.is_empty() 				and ball.ramp == get_node_or_null(next_ramp):
			return true
	return false


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
	_left = _offset(_center, width * 0.5, true)
	_right = _offset(_center, -width * 0.5, true)
	_find_deck_edge()

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
	rail.bounce = 0.0 # dead rails: the ball slides along instead of bouncing back
	rail.friction = rail_friction
	rail.color = RAIL_COLOR
	rail.points = points
	rail.visible = false # drawn by the tunnel, which fades the unridden part
	rail.set_meta("generated", true)
	add_child(rail)


## For a track that leads to an upper deck: where it passes under the deck's edge.
func _find_deck_edge() -> void:
	_deck = null
	_deck_edge = -1.0
	_draw_count = _center.size()
	if to_deck.is_empty() or not is_inside_tree():
		return
	_deck = get_node_or_null(to_deck) as Node2D
	if _deck == null or not ("outline" in _deck):
		_deck = null
		return
	var outline := PackedVector2Array()
	for q in _deck.outline:
		outline.append(to_local(_deck.to_global(q)))
	for i in _center.size():
		if Geometry2D.is_point_in_polygon(_center[i], outline):
			_deck_edge = _cum[i]
			_draw_count = i + 1
			return


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
## With `flare`, the first `flare_length` px widen by up to `mouth_flare` (a funnel).
func _offset(pts: PackedVector2Array, dist: float, flare: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d := dist
		if flare and flare_length > 0.0 and i < _cum.size():
			var t := clampf(1.0 - _cum[i] / flare_length, 0.0, 1.0)
			d += signf(dist) * mouth_flare * t * t # eases back to the track width
		var d_prev := (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d_next := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else d_prev
		var tangent := (d_prev + d_next).normalized()
		if tangent == Vector2.ZERO:
			tangent = d_prev
		var normal := tangent.orthogonal()
		var miter := 1.0 / maxf(0.35, normal.dot(d_prev.orthogonal()))
		out.append(pts[i] + normal * d * miter)
	return out


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	if _center.size() < 2:
		return
	var n := clampi(_draw_count, 2, _center.size())
	var shown := PackedFloat32Array()
	var drop := PackedFloat32Array()
	for i in n:
		shown.append(shown_at(_cum[i]))
		drop.append(_lift_at(_cum[i]))
	# Soft shadow on the table straight below the track (deeper where it runs
	# higher), then the track itself. Each goes out as one triangle list.
	var bands := []
	for layer in SHADOW_LAYERS:
		bands.append([layer[0], layer[1], Color(0, 0, 0, layer[2])])
	_draw_bands(bands, n, shown, drop)
	# Posts holding the track up. They show along the whole track even where the
	# track itself is hidden, so its route can be read from the table.
	var next_post := 60.0
	for i in n:
		if not posts_shown or _cum[i] < next_post:
			continue
		next_post = _cum[i] + post_spacing
		if drop[i] < 6.0:
			continue
		var foot := _center[i] + Vector2(0, drop[i])
		draw_line(_center[i], foot, POST_COLOR, 4.0, true)
		draw_circle(foot, 3.5, POST_COLOR.darkened(0.4))
		draw_circle(_center[i], 3.0, Color(color, lerpf(0.75, 0.0, shown[i]))) # where the track runs
	_draw_bands([[0.0, 0.0, Color(color, 0.32)]], n, shown, drop)
	# Track edges: a dark underside line (thickness), then the rails.
	var left := _left.slice(0, n)
	var right := _right.slice(0, n)
	var under_l := PackedVector2Array()
	var under_r := PackedVector2Array()
	var dark := PackedColorArray()
	var rail := PackedColorArray()
	for i in n:
		under_l.append(left[i] + Vector2(0, 3))
		under_r.append(right[i] + Vector2(0, 3))
		dark.append(Color(0, 0, 0, 0.45 * shown[i]))
		rail.append(Color(RAIL_COLOR, shown[i]))
	draw_polyline_colors(under_l, dark, 3.0, true)
	draw_polyline_colors(under_r, dark, 3.0, true)
	draw_polyline_colors(left, rail, rail_thickness, true)
	draw_polyline_colors(right, rail, rail_thickness, true)
	# Chevrons at the mouth show which way the ball has to be going to get in.
	var dir := _mouth_dir()
	var side := dir.orthogonal() * width * 0.3
	var mouth_a := 0.0 if hide_mouth else 1.0 # a hidden mouth is a seamless join: never marked
	for k in 2:
		var base := _center[0] + dir * (10.0 + k * 12.0)
		draw_polyline(PackedVector2Array([base + side, base + dir * 8.0, base - side]), Color(color, mouth_a), 3.0, true)
	# Mouth and exit lips (a track that ends under a deck, or runs straight on
	# into a chained ramp, has no visible exit).
	var last := _center.size() - 1
	draw_line(_left[0], _right[0], Color(color, 0.9 * mouth_a), 3.0, true)
	if _deck_edge < 0.0 and next_ramp.is_empty():
		# The exit always shows (lip and arrows out), so you can see where the ball comes back.
		var out := _exit_dir()
		var out_side := out.orthogonal() * width * 0.25
		draw_line(_left[last], _right[last], Color(color, lerpf(0.75, 0.5, shown[last])), 2.5, true)
		for k in 2:
			var tip := _center[last] + out * (8.0 + k * 10.0)
			draw_polyline(PackedVector2Array([tip - out * 6.0 + out_side, tip, tip - out * 6.0 - out_side]), Color(color, 0.8 - 0.25 * k), 2.5, true)
	if _fx:
		_fx.queue_redraw()


## One triangle list of track-shaped bands: [drop share, extra width, color] each.
func _draw_bands(bands: Array, n: int, shown: PackedFloat32Array, drop: PackedFloat32Array) -> void:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for band in bands:
		var share: float = band[0]
		var spread: float = band[1]
		var col: Color = band[2]
		for i in n - 1:
			var n0 := (_left[i] - _right[i]).normalized() * spread
			var n1 := (_left[i + 1] - _right[i + 1]).normalized() * spread
			var o0 := Vector2(0, drop[i] * share)
			var o1 := Vector2(0, drop[i + 1] * share)
			var c0 := Color(col, col.a * shown[i])
			var c1 := Color(col, col.a * shown[i + 1])
			var k := verts.size()
			verts.append_array([_left[i] + o0 + n0, _left[i + 1] + o1 + n1,
					_right[i + 1] + o1 - n1, _right[i] + o0 - n0])
			colors.append_array([c0, c1, c1, c0])
			indices.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	if not verts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, verts, colors)


## Booster section: chevrons scrolling toward the exit, brighter while pushing.
## Drawn on the _fx child, so only these get redrawn every frame.
func _draw_booster() -> void:
	if booster_enabled and _length > 0.0 and _center.size() >= 2:
		var spacing := 22.0
		var turbo := not Engine.is_editor_hint() and GameManager.ramp_turbo > 0
		var start := _length * (0.0 if turbo else booster_from)
		var finish := _length * booster_to
		var shift := fmod(_anim * 60.0, spacing)
		var s := start + shift
		while s < finish:
			var sample := _sample(s)
			var p: Vector2 = sample[0]
			var t: Vector2 = sample[1]
			var side_v := t.orthogonal() * width * 0.28
			if _deck_edge >= 0.0 and s > _deck_edge:
				break
			var fade := clampf(minf(s - start, finish - s) / 20.0, 0.0, 1.0) * shown_at(s)
			var c := Color(1.0, 0.95, 0.5).lerp(Color.WHITE, _boost_glow)
			c.a = (0.35 + 0.55 * _boost_glow) * fade
			_fx.draw_polyline(PackedVector2Array([p - t * 5.0 + side_v, p + t * 4.0, p - t * 5.0 - side_v]), c, 2.5, true)
			s += spacing
