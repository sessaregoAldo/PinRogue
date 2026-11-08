@tool
class_name BreakableWall
extends Wall
## A wall section that can be broken (used for the Fortress ring).
## Each ball hit scores `score_value` and deals damage like a boss hit
## (current score x boss damage multiplier). Its HP is `hp_fraction` of the
## current boss's max HP. When broken it disappears and comes back after
## `respawn_min`-`respawn_max` seconds (waiting if the ball is in the way).

@export var hp_fraction: float = 0.10
@export var respawn_min: float = 10.0
@export var respawn_max: float = 15.0
@export var score_value: int = 25
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Fortress wall"

var max_hp: int = 1
var hp: int = 1
var broken: bool = false

var _respawn_left: float = 0.0
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
	max_hp = maxi(1, int(round(GameManager.boss_max_hp * hp_fraction)))
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
	var damage := maxi(1, int(round(GameManager.score * GameManager.boss_damage_mult)))
	hp = maxi(0, hp - damage)
	_flash = 1.0
	if hp == 0:
		_break(center)
	else:
		Sfx.play("guard_hit", -4.0)
		queue_redraw()


func _break(at: Vector2) -> void:
	broken = true
	set_deferred("collision_layer", 0)
	_respawn_left = randf_range(respawn_min, respawn_max)
	Sfx.play("guard_break")
	GameManager.popup("WALL DOWN!", at, Color(0.75, 0.6, 1.0), true)
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()
	if broken and not get_tree().paused:
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
	if broken:
		# Faint outline that fills in as the respawn approaches.
		var progress := clampf(1.0 - _respawn_left / maxf(respawn_max, 0.01), 0.0, 1.0)
		for i in range(points.size() - 1):
			draw_dashed_line(points[i], points[i + 1], Color(color, 0.15 + 0.35 * progress), 2.0, 6.0)
		return
	var ratio := float(hp) / float(max_hp) if not Engine.is_editor_hint() else 1.0
	var c := color.lerp(Color(0.85, 0.2, 0.3), 1.0 - ratio).lerp(Color.WHITE, _flash * 0.6)
	draw_polyline(points, c, thickness, true)
	for p in points:
		draw_circle(p, thickness * 0.5, c)
	# Cracks appear as it weakens.
	if ratio < 0.67:
		var mid := int(points.size() / 2.0)
		var a := points[mid]
		var b := points[mini(mid + 1, points.size() - 1)]
		var n := (b - a).orthogonal().normalized() * thickness * 0.5
		draw_line(a - n, a + n * 0.3 + (b - a) * 0.3, Color(0, 0, 0, 0.6), 1.5)
	if ratio < 0.34:
		var a2 := points[1]
		var b2 := points[mini(2, points.size() - 1)]
		var n2 := (b2 - a2).orthogonal().normalized() * thickness * 0.5
		draw_line(a2 + n2, a2 - n2 * 0.3 + (b2 - a2) * 0.4, Color(0, 0, 0, 0.6), 1.5)
