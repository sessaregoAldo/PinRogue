@tool
class_name MovingBumper
extends Bumper
## A pop bumper that circles a point (e.g. around the boss). Otherwise it is an
## ordinary Bumper: it kicks, scores and can carry a score multiplier.

@export var orbit_center: Vector2 = Vector2(280, 400):
	set(value):
		orbit_center = value
		_place()
@export var orbit_radius: float = 120.0:
	set(value):
		orbit_radius = value
		_place()
## Seconds for one full circle. Negative = counter-clockwise.
@export var period: float = 8.0
## Where on the circle it starts (degrees, 0 = to the right of the center).
@export var start_angle_deg: float = 0.0:
	set(value):
		start_angle_deg = value
		_place()

var _time: float = 0.0


func _ready() -> void:
	super()
	_place()
	if not Engine.is_editor_hint():
		add_to_group("split_avoid") # the Splitter's halves keep off its track


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_place()


func _place() -> void:
	var turn := 0.0 if is_zero_approx(period) else _time / period
	position = orbit_center + Vector2.from_angle(deg_to_rad(start_angle_deg) + TAU * turn) * orbit_radius


## True if a circle of radius `extra` at `global_point` would sit on this
## bumper's track.
func covers(global_point: Vector2, extra: float = 0.0) -> bool:
	var parent := get_parent() as Node2D
	var center := parent.to_global(orbit_center) if parent else orbit_center
	return absf(global_point.distance_to(center) - orbit_radius) < radius + extra
