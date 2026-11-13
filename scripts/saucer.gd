@tool
class_name Saucer
extends Area2D
## Saucer (kick-out hole): catches a ball that rolls in, holds it for a moment,
## then fires it out along `eject_velocity`. Scores on the catch.
## A ball moving faster than `max_capture_speed` skips over it.

@export var radius: float = 17.0:
	set(value):
		radius = value
		queue_redraw()
@export var hold_time: float = 0.7
## Where the ball goes when it is fired out (px/s).
@export var eject_velocity: Vector2 = Vector2(0, 700):
	set(value):
		eject_velocity = value
		queue_redraw()
## Random +/- angle (degrees) added to each shot, so a ball fired straight at a
## bumper can't end up bouncing dead straight back and forth.
@export_range(0.0, 20.0) var eject_jitter_deg: float = 5.0
@export var max_capture_speed: float = 1100.0
@export var score_value: int = 500
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Saucer"
@export var color: Color = Color(1.0, 0.55, 0.85):
	set(value):
		color = value
		queue_redraw()

var _held: Ball = null
var _held_for: float = 0.0
var _cooldown: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius - 6.0, 4.0) # the ball has to be well over the hole
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or _held != null or _cooldown > 0.0 or GameManager.tilted:
		return
	if ball.linear_velocity.length() > max_capture_speed:
		return
	_held = ball
	_held_for = 0.0
	_flash = 1.0
	GameManager.add_score(score_value, global_position)
	Sfx.play("ramp_complete", -4.0, 1.2)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _held == null:
		return
	if not is_instance_valid(_held) or not _held.in_play:
		_held = null
		return
	_held_for += delta
	if _held_for >= hold_time or GameManager.tilted:
		_held.set_velocity_safe(eject_velocity.rotated(deg_to_rad(randf_range(-eject_jitter_deg, eject_jitter_deg))))
		_held = null
		_cooldown = 0.6
		_flash = 1.0
		Sfx.play("launch", -4.0)
		return
	# Keep the ball seated in the hole.
	_held.teleport(global_position)
	_held.set_velocity_safe(Vector2.ZERO)


func _process(delta: float) -> void:
	if _flash > 0.0 or _held != null:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	var rim := color.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + 3.0, color.darkened(0.6))
	draw_circle(Vector2.ZERO, radius, Color(0.02, 0.02, 0.05))
	draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 32, rim, 3.0, true)
	# Arrow showing where the ball will be fired.
	if eject_velocity.length() > 1.0:
		var d := eject_velocity.normalized()
		var side := d.orthogonal() * 6.0
		var tip := d * (radius + 16.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 10.0 + side, tip - d * 10.0 - side]), Color(rim, 0.8))
