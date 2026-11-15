@tool
class_name DeckDrop
extends Area2D
## A hole in an UpperDeck (make it a child of the deck): a ball on the deck that
## rolls in drops back down to the playfield right below, with `drop_velocity`.
## Scores on the way down.

@export var radius: float = 16.0:
	set(value):
		radius = value
		queue_redraw()
@export var drop_velocity: Vector2 = Vector2(0, 260)
@export var score_value: int = 500
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Deck drop"
@export var color: Color = Color(1.0, 0.8, 0.35):
	set(value):
		color = value
		queue_redraw()

## Emitted when a ball drops through (the boss gimmick can react).
signal dropped(ball: Ball)

var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.LAYER_BALL_DECK
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius - 4.0, 4.0)
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or ball.deck == null:
		return
	ball.call_deferred("leave_deck")
	ball.set_velocity_safe(drop_velocity)
	_flash = 1.0
	GameManager.add_score(score_value, global_position)
	Sfx.play("ramp_land")
	dropped.emit(ball)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + 4.0, color.darkened(0.55))
	draw_circle(Vector2.ZERO, radius, Color(0.01, 0.01, 0.03))
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 32, color.lerp(Color.WHITE, _flash), 2.5, true)
	# Down chevrons: the way back to the table below.
	for k in 2:
		var y := -radius * 0.35 + k * 7.0
		draw_polyline(PackedVector2Array([Vector2(-6, y), Vector2(0, y + 5), Vector2(6, y)]), Color(color, 0.8), 2.0, true)
