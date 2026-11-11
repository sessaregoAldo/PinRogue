@tool
class_name Wall
extends StaticBody2D
## A thick polyline wall. Edit `points` in the inspector to reshape the table.
## Builds one rectangle collider per segment plus a circle at each joint so the
## ball can't snag on corners. With `one_way` on, the ball passes through while
## moving "up" relative to each segment (used for the shooter-lane gate).

@export var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(100, 0)]):
	set(value):
		points = value
		_rebuild()
@export var thickness: float = 8.0:
	set(value):
		thickness = value
		_rebuild()
@export var bounce: float = 0.25:
	set(value):
		bounce = value
		_rebuild()
@export var one_way: bool = false:
	set(value):
		one_way = value
		_rebuild()
@export var color: Color = Color(0.72, 0.78, 0.95):
	set(value):
		color = value
		queue_redraw()
## Physics layers this wall is on (1 = playfield; tunnel rails use 4-8).
@export_flags_2d_physics var physics_layers: int = 1


func _ready() -> void:
	collision_layer = physics_layers
	collision_mask = 0
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()

	var mat := PhysicsMaterial.new()
	mat.bounce = bounce
	mat.friction = 0.2
	physics_material_override = mat

	for i in range(points.size() - 1):
		_add_segment(points[i], points[i + 1])
	if not one_way:
		for p in points:
			_add_joint(p)
	queue_redraw()


func _add_segment(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, thickness)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	cs.position = (a + b) * 0.5
	cs.rotation = (b - a).angle()
	cs.one_way_collision = one_way
	cs.one_way_collision_margin = 4.0
	cs.set_meta("generated", true)
	add_child(cs)


func _add_joint(p: Vector2) -> void:
	var circle := CircleShape2D.new()
	circle.radius = thickness * 0.5
	var cs := CollisionShape2D.new()
	cs.shape = circle
	cs.position = p
	cs.set_meta("generated", true)
	add_child(cs)


func _draw() -> void:
	if points.size() < 2:
		return
	var c := Color(1.0, 0.85, 0.3) if one_way else color
	draw_polyline(points, c, thickness, true)
	if not one_way:
		# Round caps at the ends and at real corners. Smooth curves (tunnel rails
		# have hundreds of points) don't need them, and each circle is a separate
		# draw call, which phones feel.
		var last := points.size() - 1
		for i in points.size():
			if i == 0 or i == last or _is_corner(i):
				draw_circle(points[i], thickness * 0.5, c)


## True if the wall turns by more than a few degrees at point i.
func _is_corner(i: int) -> bool:
	var a := points[i] - points[i - 1]
	var b := points[i + 1] - points[i]
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return false
	return absf(a.angle_to(b)) > deg_to_rad(8.0)
