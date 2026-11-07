@tool
class_name Plunger
extends Area2D
## Shooter-lane plunger. Hold "launch" to charge, release to fire any ball
## resting in the zone straight up.

@export var zone_size: Vector2 = Vector2(30, 36)
@export var min_power: float = 600.0
@export var max_power: float = 1900.0
@export var charge_time: float = 1.0
@export var color: Color = Color(0.9, 0.9, 0.95)

var charge: float = 0.0
var _charging: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var previous := charge
	if Input.is_action_pressed("launch") and not GameManager.is_game_over:
		_charging = true
		charge = minf(1.0, charge + delta / charge_time)
	elif _charging:
		_charging = false
		var power := lerpf(min_power, max_power, charge)
		for body in get_overlapping_bodies():
			var ball := body as Ball
			if ball and ball.in_play:
				ball.set_velocity_safe(Vector2.UP * power)
				Sfx.play("launch", linear_to_db(lerpf(0.4, 1.0, charge)))
		charge = 0.0
	if charge != previous:
		GameManager.set_plunger_charge(charge)
		queue_redraw()


func _draw() -> void:
	# Plunger tip sits under the lane floor and pulls back as it charges.
	var top := zone_size.y * 0.5 + 6.0 + charge * 30.0
	draw_rect(Rect2(-zone_size.x * 0.4, top, zone_size.x * 0.8, 6.0), color)
	draw_line(Vector2(0, top + 6.0), Vector2(0, 90.0), color.darkened(0.3), 4.0)
	var coils := 6
	for i in coils:
		var y := lerpf(top + 10.0, 80.0, float(i) / coils)
		draw_line(Vector2(-6, y), Vector2(6, y + 4.0), Color(0.6, 0.6, 0.65), 2.0)
