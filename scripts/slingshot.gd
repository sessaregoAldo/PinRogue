@tool
class_name Slingshot
extends StaticBody2D
## Triangular kicker. Only the edge corner_a -> corner_b kicks; the kick goes
## along that edge's normal, away from corner_c.

@export var corner_a: Vector2 = Vector2(0, 0)
@export var corner_b: Vector2 = Vector2(45, 115)
@export var corner_c: Vector2 = Vector2(0, 90)
@export var kick_strength: float = 650.0
@export var score_value: int = 10
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Slingshot"
@export var cooldown: float = 0.1
@export var color: Color = Color(0.4, 1.0, 0.5)
@export_group("Kick shaping")
## Turns the kick away from the edge normal toward the bottom of the table
## (degrees). Positive values send the ball down toward the flippers.
@export_range(-45.0, 45.0) var kick_tilt_deg: float = 0.0
## Random +/- spread added to the kick angle (degrees).
@export_range(0.0, 30.0) var kick_angle_jitter_deg: float = 0.0
## Random +/- fraction added to the kick strength (0.1 = +/-10%).
@export_range(0.0, 0.5) var kick_strength_jitter: float = 0.0
## How much of the ball's motion along the edge survives the kick.
@export_range(0.0, 1.0) var keep_tangent: float = 0.8

var _normal: Vector2
var _flash: float = 0.0
var _last_hit_ms: int = -100000


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	physics_material_override = mat

	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array([corner_a, corner_b, corner_c])
	add_child(poly)

	var edge := corner_b - corner_a
	_normal = edge.orthogonal().normalized()
	if _normal.dot(corner_c - corner_a) > 0.0:
		_normal = -_normal

	# Thin trigger strip just outside the kicking edge.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var rect := RectangleShape2D.new()
	rect.size = Vector2(edge.length() * 0.8, 8.0)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	cs.position = (corner_a + corner_b) * 0.5 + _normal * 2.0
	cs.rotation = edge.angle()
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < int(cooldown * 1000.0):
		return
	_last_hit_ms = now
	ball.kick(_kick_direction(), kick_strength * (1.0 + randf_range(-kick_strength_jitter, kick_strength_jitter)), keep_tangent)
	GameManager.add_score(score_value, to_global((corner_a + corner_b) * 0.5))
	_flash = 1.0
	Sfx.play("slingshot")
	GameManager.part_hit.emit(self)


func _kick_direction() -> Vector2:
	var dir := _normal.rotated(global_rotation)
	# With y pointing down, a clockwise turn tilts a right-going kick downward
	# and a left-going kick upward, so the tilt's sign follows the kick's side.
	var side := 1.0 if dir.x >= 0.0 else -1.0
	dir = dir.rotated(deg_to_rad(kick_tilt_deg) * side)
	return dir.rotated(deg_to_rad(randf_range(-kick_angle_jitter_deg, kick_angle_jitter_deg)))


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([corner_a, corner_b, corner_c]), color.darkened(0.6))
	var edge_color := color.lerp(Color.WHITE, _flash)
	draw_line(corner_a + _normal * _flash * 4.0, corner_b + _normal * _flash * 4.0, edge_color, 5.0, true)
	draw_line(corner_b, corner_c, color.darkened(0.2), 3.0, true)
	draw_line(corner_c, corner_a, color.darkened(0.2), 3.0, true)
