@tool
class_name TrapExit
extends Node2D
## One exit hole of a BallTrap (make it a child of the trap). The ball is fired
## out of it along the node's rotation: rotation 0 = straight up the table,
## 90 = to the right, -90 = to the left.
## It lights up while it is the exit the ball will come out of
## (BallTrap.warn_time before the launch).

@export var launch_speed: float = 900.0:
	set(value):
		launch_speed = value
		queue_redraw()
@export var radius: float = 14.0:
	set(value):
		radius = value
		queue_redraw()
@export var color: Color = Color(0.55, 1.0, 0.95):
	set(value):
		color = value
		queue_redraw()

## Story mode (the Collector's Till): the exit he admires. A turning ring of
## sparkles marks it.
var showcase: bool = false:
	set(value):
		showcase = value
		queue_redraw()

## 0 = idle, rising to 1 while armed (the light pulses on top of this).
var _armed: float = 0.0
var _arming: bool = false
var _flash: float = 0.0


## The ball's velocity when it leaves this hole.
func launch_velocity() -> Vector2:
	return Vector2.UP.rotated(global_rotation) * launch_speed


## Light up: the ball comes out of here next.
func arm() -> void:
	_arming = true
	_armed = 1.0 # full light at once: the warning is short
	queue_redraw()


## The ball has just left.
func fire() -> void:
	_arming = false
	_armed = 0.0
	_flash = 1.0
	queue_redraw()


func disarm() -> void:
	_arming = false
	_armed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if showcase:
		queue_redraw() # the sparkle ring turns
	if _arming:
		_armed = minf(1.0, _armed + delta * 6.0)
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	# Light ring: dim when idle; bright and pulsing while armed.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 6.0)
	var glow := _armed * (0.6 + 0.4 * pulse)
	# The hole (it glows from inside while armed)
	if glow > 0.05:
		draw_circle(Vector2.ZERO, radius + 14.0, Color(color, 0.18 * glow))
	draw_circle(Vector2.ZERO, radius + 3.0, color.darkened(0.65).lerp(color, glow))
	draw_circle(Vector2.ZERO, radius, Color(0.02, 0.02, 0.05).lerp(Color(color, 1.0), 0.55 * glow))
	var ring := color.darkened(0.45).lerp(color, glow).lerp(Color.WHITE, _flash * 0.8)
	draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 32, ring, 2.5 + glow * 2.0, true)
	if glow > 0.05:
		draw_arc(Vector2.ZERO, radius + 6.0 + pulse * 3.0, 0.0, TAU, 32, Color(color, 0.45 * glow), 3.0, true)
	if showcase:
		var spin := Time.get_ticks_msec() / 1000.0 * 1.6
		for i in 6:
			var p := Vector2.from_angle(spin + TAU * i / 6.0) * (radius + 9.0)
			draw_circle(p, 2.2, Color(1.0, 0.85, 0.35, 0.9))
	# Arrow showing which way the ball will fly (always shown, brighter when armed).
	var tip := Vector2(0, -(radius + 15.0))
	var arrow := Color(ring, 0.35 + 0.65 * maxf(glow, _flash))
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, 9), tip + Vector2(6, 9)]), arrow)
