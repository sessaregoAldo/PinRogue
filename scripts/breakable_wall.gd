@tool
class_name BreakableWall
extends Wall
## A wall section that can be broken (used for the Fortress ring).
## Each ball hit scores `score_value` and deals damage like a boss hit
## (current score x boss damage multiplier). Its HP is `hp_fraction` of the
## current boss's max HP, but at least `score_factor` x the player's score when
## it appears, so it always takes a few hits.
## When broken it stays solid while it fades out (so the breaking hit bounces),
## then comes back after `respawn_min`-`respawn_max` seconds (waiting if the
## ball is in the way), fading in. A faint timer shows while it's down.

const FADE_TIME := 0.5

@export var hp_fraction: float = 0.10
@export var score_factor: float = 2.0
@export var respawn_min: float = 10.0
@export var respawn_max: float = 15.0
@export var score_value: int = 25
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Fortress wall"

var max_hp: float = 1.0
var hp: float = 1.0
var broken: bool = false

var _respawn_left: float = 0.0
var _respawn_total: float = 1.0
## 1 = fully there, 0 = gone. Fades over FADE_TIME when breaking / respawning.
var _presence: float = 1.0
var _flash: float = 0.0
var _last_hit_ms: int = -100000
var _area: Area2D


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_reset_hp()
	_build_area()


func _reset_hp() -> void:
	max_hp = maxf(1.0, roundf(maxf(GameManager.boss_max_hp * hp_fraction, GameManager.score * score_factor)))
	hp = max_hp


## Trigger strip around the wall so ball contacts register as hits.
func _build_area() -> void:
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2 # balls on the playfield
	_area.monitorable = false
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var rect := RectangleShape2D.new()
		rect.size = Vector2(a.distance_to(b) + thickness, thickness + 14.0)
		var cs := CollisionShape2D.new()
		cs.shape = rect
		cs.position = (a + b) * 0.5
		cs.rotation = (b - a).angle()
		_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or broken or GameManager.tilted:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 120:
		return
	_last_hit_ms = now
	var center := to_global(points[int(points.size() / 2.0)])
	GameManager.add_score(score_value, center)
	var damage := maxf(1.0, roundf(GameManager.score * GameManager.boss_damage_mult))
	hp = maxf(0.0, hp - damage)
	_flash = 1.0
	if hp <= 0.0:
		_break(center)
	else:
		Sfx.play("guard_hit", -4.0)
		queue_redraw()


func _break(at: Vector2) -> void:
	broken = true # no more damage; stays solid until it has faded out
	_respawn_left = randf_range(respawn_min, respawn_max)
	_respawn_total = _respawn_left
	Sfx.play("guard_break")
	GameManager.popup("WALL DOWN!", at, Color(0.75, 0.6, 1.0), true)
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()
	if get_tree().paused:
		return
	if broken:
		if _presence > 0.0:
			_presence = maxf(0.0, _presence - delta / FADE_TIME)
			if _presence == 0.0:
				collision_layer = 0 # gone: balls pass through now
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			if _ball_in_the_way():
				_respawn_left = 0.3 # never close the wall on top of the ball
			else:
				broken = false
				_reset_hp()
				collision_layer = physics_layers
				Sfx.play("guard_hit", -8.0, 0.7)
		queue_redraw()
	elif _presence < 1.0:
		_presence = minf(1.0, _presence + delta / FADE_TIME)
		queue_redraw()


func _ball_in_the_way() -> bool:
	for body in _area.get_overlapping_bodies():
		if body is Ball:
			return true
	# The area only reports bodies entering while monitoring; also check distance.
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball and ball.in_play:
			var p := to_local(ball.global_position)
			for i in range(points.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
				if p.distance_to(q) < thickness * 0.5 + ball.radius + 2.0:
					return true
	return false


func _draw() -> void:
	if points.size() < 2:
		return
	if broken and not Engine.is_editor_hint():
		_draw_respawn_timer()
	if _presence <= 0.0:
		return
	var ratio := clampf(hp / max_hp, 0.0, 1.0) if not Engine.is_editor_hint() else 1.0
	var a_mul := _presence # fades the whole section in / out
	var thick := thickness * (0.55 + 0.45 * _presence)

	# Casing: the section's full size, always drawn, so the bar keeps its place.
	var border := Color(color.lightened(0.2), 0.75 * a_mul)
	draw_polyline(points, border, thick + 2.0, true)
	for p in points:
		draw_circle(p, thick * 0.5 + 1.0, border)
	var casing := Color(color.darkened(0.6), a_mul)
	draw_polyline(points, casing, thick - 1.0, true)
	for p in points:
		draw_circle(p, thick * 0.5 - 0.5, casing)

	# Health fill: thins across the bar's width as HP drops (centered in the casing).
	var fill_w := maxf(1.5, (thick - 4.0) * ratio)
	var fill := color.lerp(Color(0.95, 0.25, 0.35), 1.0 - ratio).lerp(Color.WHITE, _flash * 0.6)
	fill.a *= a_mul
	draw_polyline(points, fill, fill_w, true)
	for p in points:
		draw_circle(p, fill_w * 0.5, fill)

	# HP written along the middle of the bar, kept upright.
	var mid := int(points.size() / 2.0)
	var a := points[maxi(mid - 1, 0)]
	var b := points[mid]
	var angle := (b - a).angle()
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI
	var text := GameManager.format_short(hp) if not Engine.is_editor_hint() else "HP"
	var font := ThemeDB.fallback_font
	var font_size := 11
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_set_transform((a + b) * 0.5, angle)
	var pos := Vector2(-width * 0.5, font_size * 0.35)
	if not broken: # no HP text while it fades out
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.85 * a_mul))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, a_mul))
	draw_set_transform(Vector2.ZERO, 0.0)


## While the section is down: a barely visible dashed outline, a thin line that
## grows along it as the respawn approaches, and the seconds left.
func _draw_respawn_timer() -> void:
	var progress := clampf(1.0 - _respawn_left / maxf(_respawn_total, 0.01), 0.0, 1.0)
	var faint := (1.0 - _presence) # appears as the wall fades out
	for i in range(points.size() - 1):
		draw_dashed_line(points[i], points[i + 1], Color(color, 0.12 * faint), 2.0, 6.0)
	# Progress line along the polyline.
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	var left := total * progress
	for i in range(points.size() - 1):
		if left <= 0.0:
			break
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		var end := b if left >= seg else a.lerp(b, left / seg)
		draw_line(a, end, Color(color, 0.28 * faint), 2.0, true)
		left -= seg
	# Seconds left, small and dim, next to the middle of the section.
	var mid := points[int(points.size() / 2.0)]
	var font := ThemeDB.fallback_font
	var text := str(int(ceilf(maxf(_respawn_left, 0.0))))
	draw_string(font, mid + Vector2(-10, 4), text, HORIZONTAL_ALIGNMENT_CENTER, 20, 10, Color(1, 1, 1, 0.3 * faint))
