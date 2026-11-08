@tool
class_name TargetButton
extends StaticBody2D
## A stand-up target: a short rubber bar the ball bounces off. Each hit emits
## `hit`. Its states (lit, special/gold, part of the goal pattern) are managed
## by the parent ButtonBank. `point_a` / `point_b` are local coordinates.

signal hit(button: TargetButton)

@export var point_a: Vector2 = Vector2.ZERO:
	set(value):
		point_a = value
		_rebuild()
@export var point_b: Vector2 = Vector2(30, 0):
	set(value):
		point_b = value
		_rebuild()
@export var thickness: float = 10.0:
	set(value):
		thickness = value
		_rebuild()
## Where the goal marker sits: the side of the button facing this point (global).
@export var table_center: Vector2 = Vector2(280, 560)

var lit: bool = false:
	set(value):
		lit = value
		queue_redraw()
## Gold "chase" button.
var special: bool = false:
	set(value):
		special = value
		queue_redraw()
## Part of the combination the player has to light.
var goal: bool = false:
	set(value):
		goal = value
		queue_redraw()

var _flash: float = 0.0
var _last_hit_ms: int = -100000


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.45
	physics_material_override = mat
	_rebuild()


func center_global() -> Vector2:
	return to_global((point_a + point_b) * 0.5)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	var edge := point_b - point_a
	var mid := (point_a + point_b) * 0.5
	var rect := RectangleShape2D.new()
	rect.size = Vector2(edge.length(), thickness)
	_add_shape(self, rect, mid, edge.angle())
	for p in [point_a, point_b]:
		var cap := CircleShape2D.new()
		cap.radius = thickness * 0.5
		_add_shape(self, cap, p, 0.0)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2 # balls on the playfield only
	area.monitorable = false
	area.set_meta("generated", true)
	var trigger := RectangleShape2D.new()
	trigger.size = Vector2(edge.length() + thickness + 6.0, thickness + 14.0)
	_add_shape(area, trigger, mid, edge.angle())
	add_child(area)
	if not Engine.is_editor_hint():
		area.body_entered.connect(_on_body_entered)
	queue_redraw()


func _add_shape(parent: Node, shape: Shape2D, pos: Vector2, rot: float) -> void:
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	if parent == self:
		cs.set_meta("generated", true)
	parent.add_child(cs)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 150:
		return
	_last_hit_ms = now
	_flash = 1.0
	hit.emit(self)


func flash() -> void:
	_flash = 1.0
	queue_redraw()


func _draw() -> void:
	var base := Palette.BUTTON_SPECIAL if special else (Palette.BUTTON_LIT if lit else Palette.BUTTON_OFF)
	var c := base.lerp(Color.WHITE, _flash * 0.6)
	if lit or special:
		draw_line(point_a, point_b, Color(base, 0.3), thickness + 8.0, true) # glow
	draw_line(point_a, point_b, c, thickness, true)
	draw_circle(point_a, thickness * 0.5, c)
	draw_circle(point_b, thickness * 0.5, c)
	draw_line(point_a, point_b, c.lightened(0.35), 2.0, true)
	# Goal marker on the playfield side: filled diamond = must be lit for the bonus.
	var mid := (point_a + point_b) * 0.5
	var n := (point_b - point_a).orthogonal().normalized()
	if n.dot(to_local(table_center) - mid) < 0.0:
		n = -n
	var p := mid + n * (thickness * 0.5 + 11.0)
	var t := (point_b - point_a).normalized()
	var diamond := PackedVector2Array([p + n * 7.0, p + t * 7.0, p - n * 7.0, p - t * 7.0])
	if goal:
		draw_colored_polygon(diamond, Palette.BUTTON_LIT)
	else:
		diamond.append(diamond[0])
		draw_polyline(diamond, Color(Palette.BUTTON_LIT, 0.45), 1.5, true)
