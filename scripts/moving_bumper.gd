@tool
class_name MovingBumper
extends Bumper
## A pop bumper that circles a point (e.g. around the boss), or with `travel`
## set, slides back and forth along a line. Otherwise it is an ordinary Bumper:
## it kicks, scores and can carry a score multiplier.

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
## Slide instead of circling: back and forth between orbit_center - travel and
## orbit_center + travel at a steady speed, one round trip per `period`
## (start_angle_deg then sets where in the trip it starts: 0 = the + end).
@export var travel: Vector2 = Vector2.ZERO:
	set(value):
		travel = value
		_place()
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
	if travel != Vector2.ZERO:
		var phase := fposmod(turn + start_angle_deg / 360.0, 1.0)
		position = orbit_center + travel * (4.0 * absf(phase - 0.5) - 1.0) # +1 at phase 0, -1 halfway
		return
	position = orbit_center + Vector2.from_angle(deg_to_rad(start_angle_deg) + TAU * turn) * orbit_radius


## True if a circle of radius `extra` at `global_point` would sit on this
## bumper's track.
func covers(global_point: Vector2, extra: float = 0.0) -> bool:
	var parent := get_parent() as Node2D
	var center := parent.to_global(orbit_center) if parent else orbit_center
	if travel != Vector2.ZERO:
		var a := center - travel
		var b := center + travel
		var t := clampf((global_point - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		return global_point.distance_to(a.lerp(b, t)) < radius + extra
	return absf(global_point.distance_to(center) - orbit_radius) < radius + extra
