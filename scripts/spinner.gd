@tool
class_name Spinner
extends Area2D
## Spinner: a plate hanging across a lane. A ball passing through sets it
## spinning; every half turn scores. The faster the ball, the more spins.
## It never blocks the ball. Rotate the node so the plate spans the lane.

@export var width: float = 44.0:
	set(value):
		width = value
		queue_redraw()
@export var score_per_spin: int = 100
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Spinner"
@export var color: Color = Color(1.0, 0.75, 0.3):
	set(value):
		color = value
		queue_redraw()
## Ball speed (px/s) that gives one spin per second right after the hit.
@export var speed_per_spin: float = 110.0
@export var max_spin: float = 14.0

var _spin: float = 0.0 # turns per second (signed)
var _angle: float = 0.0 # radians
var _half_turns: int = 0
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 14.0)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	# Spin with the ball's motion through the plate.
	var through := ball.linear_velocity.dot(Vector2.DOWN.rotated(global_rotation))
	var spin := clampf(absf(through) / speed_per_spin, 1.5, max_spin)
	_spin = spin if through >= 0.0 else -spin


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		queue_redraw()
	if _spin == 0.0:
		return
	_angle += _spin * TAU * delta
	var halves := int(floor(absf(_angle) / PI))
	while _half_turns < halves:
		_half_turns += 1
		GameManager.add_score(score_per_spin, global_position)
		Sfx.play("click", -8.0, 1.6, 40)
		_flash = 1.0
	_spin *= exp(-1.3 * delta)
	if absf(_spin) < 0.6:
		# Settle flat and start counting afresh.
		_spin = 0.0
		_angle = 0.0
		_half_turns = 0
	queue_redraw()


func _draw() -> void:
	var half := width * 0.5
	# Posts at both ends and the axle.
	draw_circle(Vector2(-half, 0), 4.0, color.darkened(0.3))
	draw_circle(Vector2(half, 0), 4.0, color.darkened(0.3))
	draw_line(Vector2(-half, 0), Vector2(half, 0), color.darkened(0.5), 2.0, true)
	# The plate, seen from above: its height follows the spin angle.
	var tall := 3.0 + 9.0 * absf(cos(_angle))
	var face := color.lerp(Color.WHITE, _flash * 0.7)
	if sin(_angle * 0.5) < 0.0:
		face = face.darkened(0.25) # the back of the plate
	draw_rect(Rect2(-half + 5.0, -tall * 0.5, width - 10.0, tall), face)
