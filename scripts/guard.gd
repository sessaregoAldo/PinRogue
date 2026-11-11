class_name Guard
extends StaticBody2D
## Breakable barrier that bounces the ball back into play (power-up).
## Each save uses one charge; at 0 it shatters and disappears.

signal changed
signal broken

@export var point_a: Vector2 = Vector2.ZERO
@export var point_b: Vector2 = Vector2(40, 0)
@export var thickness: float = 6.0
@export var kick_direction: Vector2 = Vector2.UP
@export var kick_speed: float = 450.0
## Random sideways angle range (degrees) added to the kick, on a random side.
## The gap guard uses this to pop the ball onto one of the flippers.
@export var side_angle_min_deg: float = 0.0
@export var side_angle_max_deg: float = 0.0
@export var color: Color = Color(0.4, 0.9, 1.0)

var saves: int = 1
var _flash: float = 0.0
var _dying: bool = false
var _last_hit_ms: int = -100000
var _area: Area2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.2
	physics_material_override = mat

	var edge := point_b - point_a
	var rect := RectangleShape2D.new()
	rect.size = Vector2(edge.length(), thickness)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	cs.position = (point_a + point_b) * 0.5
	cs.rotation = edge.angle()
	# Blocks only from above: a ball fired up through it (Kickback) passes.
	cs.one_way_collision = true
	cs.one_way_collision_margin = 8.0
	add_child(cs)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var trigger := RectangleShape2D.new()
	trigger.size = Vector2(edge.length() + 6.0, thickness + 16.0)
	var tcs := CollisionShape2D.new()
	tcs.shape = trigger
	tcs.position = cs.position
	tcs.rotation = cs.rotation
	_area.add_child(tcs)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func add_saves(amount: int, max_saves: int) -> void:
	saves = mini(saves + amount, max_saves)
	queue_redraw()
	changed.emit()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or _dying:
		return
	if ball.linear_velocity.y < -150.0: # rising (e.g. a Kickback shot): let it pass
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 150:
		return
	_last_hit_ms = now
	var dir := kick_direction.normalized()
	if side_angle_max_deg > 0.0:
		var side := 1.0 if randf() < 0.5 else -1.0
		dir = dir.rotated(deg_to_rad(randf_range(side_angle_min_deg, side_angle_max_deg)) * side)
	ball.set_velocity_safe(dir * kick_speed)
	saves -= 1
	_flash = 1.0
	GameManager.popup("SAVED!", to_global((point_a + point_b) * 0.5), color, true)
	changed.emit()
	if saves <= 0:
		_break()
	else:
		Sfx.play("guard_hit")
		queue_redraw()


func _break() -> void:
	_dying = true
	Sfx.play("guard_break")
	set_deferred("collision_layer", 0)
	_area.set_deferred("monitoring", false)
	broken.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var c := color.lerp(Color.WHITE, _flash)
	draw_line(point_a, point_b, Color(c, 0.35), thickness + 6.0, true)
	draw_line(point_a, point_b, c, thickness, true)
	# One pip per remaining save.
	var dir := (point_b - point_a)
	for i in saves:
		var p := point_a + dir * (float(i + 1) / float(saves + 1))
		draw_circle(p, 2.5, Color(0.05, 0.1, 0.2))
