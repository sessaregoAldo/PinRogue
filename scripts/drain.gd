@tool
class_name Drain
extends Area2D
## Below the flippers: a ball entering here is lost.

@export var size: Vector2 = Vector2(480, 50)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var rect := RectangleShape2D.new()
	rect.size = size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball and ball.in_play:
		GameManager.drain_ball(ball) # multiball aware
