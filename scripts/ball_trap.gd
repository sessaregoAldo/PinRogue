@tool
class_name BallTrap
extends Area2D
## Ball trap: a hole that swallows the ball, holds it out of sight for a moment,
## then fires it out of one of its exits (TrapExit children, 2-3 of them),
## picked at random. The chosen exit lights up `warn_time` seconds before the
## ball comes out, so the player can get ready. Scores on the catch.
##
## To use it on a machine: instance scenes/parts/ball_trap.tscn (or add this
## script to an Area2D), then move its TrapExit children to where the ball
## should come out and rotate each one to aim it (0 = straight up).
## Not used on any machine yet.

## A ball left through `exit`.
signal launched(ball: Ball, exit: TrapExit)

@export var radius: float = 18.0:
	set(value):
		radius = value
		queue_redraw()
## Seconds from swallowing the ball to firing it out.
@export var hold_time: float = 1.3
## How long before the launch the chosen exit lights up.
@export var warn_time: float = 0.5
## A ball faster than this rolls over the hole instead of dropping in.
@export var max_capture_speed: float = 1300.0
@export var score_value: int = 750
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Ball trap"
@export var color: Color = Color(0.55, 1.0, 0.95):
	set(value):
		color = value
		queue_redraw()
## The same exit is never used twice in a row (when there is more than one).
@export var avoid_repeat: bool = true

var _held: Ball = null
var _held_for: float = 0.0
var _exit: TrapExit = null
var _last_exit: TrapExit = null
var _warned: bool = false
var _cooldown: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius - 6.0, 4.0) # the ball has to be well over the hole
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	body_entered.connect(_on_body_entered)


func exits() -> Array[TrapExit]:
	var out: Array[TrapExit] = []
	for child in get_children():
		if child is TrapExit:
			out.append(child)
	return out


## True while a ball is inside.
func is_holding() -> bool:
	return _held != null


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or not ball.visible or _held != null or _cooldown > 0.0:
		return
	if ball.linear_velocity.length() > max_capture_speed or exits().is_empty():
		return
	hold(ball)


## Take `ball` in (also used by story mode to start a fight with the ball in here).
func hold(ball: Ball) -> void:
	if _held != null or exits().is_empty():
		return
	_held = ball
	_held_for = 0.0
	_warned = false
	_flash = 1.0
	_exit = _pick_exit()
	# Out of sight and out of the physics, but still the ball in play (a trapped
	# ball isn't a drained one: multiball and the drain rules leave it alone).
	ball.visible = false
	ball.set_velocity_safe(Vector2.ZERO)
	ball.teleport(global_position)
	ball.call_deferred("_set_frozen", true)
	GameManager.add_score(score_value, global_position)
	GameManager.part_hit.emit(self)
	Sfx.play("ramp_complete", -4.0, 0.8)


func _pick_exit() -> TrapExit:
	var options := exits()
	if avoid_repeat and options.size() > 1 and _last_exit in options:
		options.erase(_last_exit)
	return options[randi() % options.size()]


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _held == null:
		return
	if not is_instance_valid(_held) or not _held.in_play or GameManager.is_game_over:
		_release_hold()
		return
	_held_for += delta
	if not _warned and _held_for >= hold_time - warn_time:
		_warned = true
		_exit.arm()
		Sfx.play("warning", -10.0, 1.6)
	if _held_for >= hold_time:
		_launch()


func _launch() -> void:
	var ball := _held
	var exit := _exit
	_release_hold()
	_last_exit = exit
	_cooldown = 0.4
	ball.place(exit.global_position, exit.launch_velocity())
	exit.fire()
	Sfx.play("launch", -2.0)
	launched.emit(ball, exit)


func _release_hold() -> void:
	if _exit:
		_exit.disarm()
	_held = null
	_exit = null


func _process(delta: float) -> void:
	if _flash > 0.0 or _held != null:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	var rim := color.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + 5.0, color.darkened(0.7))
	draw_circle(Vector2.ZERO, radius, Color(0.01, 0.01, 0.03))
	# A swirl inside the hole, turning faster while it holds a ball.
	var spin := Time.get_ticks_msec() / 1000.0 * (5.0 if _held != null else 1.2)
	for k in 3:
		var a := spin + TAU * k / 3.0
		draw_arc(Vector2.ZERO, radius * 0.62, a, a + 1.4, 10, Color(color, 0.55), 2.0, true)
	draw_arc(Vector2.ZERO, radius + 2.5, 0.0, TAU, 40, rim, 3.0, true)
	# Faint lines to the exits, so it reads as one part.
	for exit in exits():
		draw_dashed_line(Vector2.ZERO, to_local(exit.global_position), Color(color, 0.12), 2.0, 10.0)
