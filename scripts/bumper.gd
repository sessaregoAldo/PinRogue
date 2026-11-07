@tool
class_name Bumper
extends StaticBody2D
## Pop bumper: kicks the ball away from its center, scores, and flashes.

@export var radius: float = 24.0
@export var kick_strength: float = 750.0
@export var score_value: int = 100
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Pop bumper"
@export var cooldown: float = 0.08
@export var color: Color = Color(0.2, 0.8, 1.0)
## Pitch of the hit sound (lower = heavier).
@export var hit_pitch: float = 1.0

var _flash: float = 0.0
var _last_hit_ms: int = -100000


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	physics_material_override = mat

	var shape := CircleShape2D.new()
	shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var area_shape := CircleShape2D.new()
	area_shape.radius = radius + 3.0
	var area_cs := CollisionShape2D.new()
	area_cs.shape = area_shape
	area.add_child(area_cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < int(cooldown * 1000.0):
		return
	_last_hit_ms = now
	ball.kick(ball.global_position - global_position, kick_strength)
	GameManager.add_score(score_value, global_position)
	_flash = 1.0
	Sfx.play("bumper", 0.0, hit_pitch)
	GameManager.part_hit.emit(self)
	_after_hit(ball)


## Called after every counted hit. Override in subclasses (see BossBumper).
func _after_hit(_ball: Ball) -> void:
	pass


func _draw() -> void:
	var fill := color.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + _flash * 6.0, color.darkened(0.5))
	draw_circle(Vector2.ZERO, radius, fill)
	draw_circle(Vector2.ZERO, radius * 0.55, fill.darkened(0.25))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color.WHITE, 2.0, true)
