@tool
class_name Rollover
extends Area2D
## A lane switch the ball rolls over. It scores and lights up. When every
## rollover in the same group is lit, they all pay `group_bonus`, flash and reset.

@export var group_name: StringName = &"top_lanes"
@export var size: Vector2 = Vector2(16, 16)
@export var score_value: int = 50
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Rollover"
## Paid once when the whole group is lit (only the rollover that completes it pays).
@export var group_bonus: int = 2000
@export var color: Color = Color(1.0, 0.85, 0.2)
## Completing this rollover's group offers a power-up pick.
@export var grants_powerup: bool = true
## Which kind of pick: "minor" (the inlane lights behind the bottom slingshots)
## or "major" (the machine's own lights near the boss).
@export_enum("major", "minor") var powerup_tier: String = "major"

var lit: bool = false
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # playfield ball only: a ball riding a tunnel passes over
	monitorable = false
	add_to_group(group_name)
	var rect := RectangleShape2D.new()
	rect.size = size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)
	if not Engine.is_editor_hint():
		GameManager.game_started.connect(func() -> void:
			lit = false
			queue_redraw())


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 0.8)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	GameManager.add_score(score_value, global_position)
	Sfx.play("rollover")
	if lit:
		return
	lit = true
	queue_redraw()
	for node in get_tree().get_nodes_in_group(group_name):
		var other := node as Rollover
		if other and not other.lit:
			return
	GameManager.add_score(group_bonus, global_position + Vector2(0, -26))
	Sfx.play("ramp_complete")
	if grants_powerup:
		GameManager.request_powerup_choice(powerup_tier)
	for node in get_tree().get_nodes_in_group(group_name):
		var other := node as Rollover
		if other:
			other.lit = false
			other._flash = 1.0


func _draw() -> void:
	var on := lit or (_flash > 0.0 and fmod(_flash * 8.0, 1.0) > 0.5)
	var r := minf(size.x, size.y) * 0.5
	if on:
		draw_circle(Vector2.ZERO, r + 4.0, Color(color, 0.25))
	draw_circle(Vector2.ZERO, r, color if on else color.darkened(0.75))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, color.darkened(0.3), 1.5, true)
