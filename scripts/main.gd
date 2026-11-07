extends Node2D
## Table controller: ball spawning, nudging (with tilt), camera shake, debug tools.

@export var spawn_point: Vector2 = Vector2(560, 1020)
@export var respawn_delay: float = 1.0
@export_group("Nudge")
@export var nudge_side_strength: float = 420.0
@export var nudge_up_strength: float = 480.0
@export var nudge_cooldown: float = 0.35
@export var nudge_tilt_cost: float = 1.0
@export var shake_distance: float = 8.0
@export_group("Debug")
## Ctrl + left-click anywhere to drop the ball there (handy for tuning).
@export var debug_mouse_drop: bool = true
## If the ball escapes this rectangle it counts as drained.
@export var table_bounds: Rect2 = Rect2(-50, -50, 700, 1250)
@export var background_color: Color = Color(0.07, 0.08, 0.16)

@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

var _nudge_timer: float = 0.0
var _shake_tween: Tween


func _ready() -> void:
	GameManager.nudge_cost = nudge_tilt_cost
	GameManager.ball_lost.connect(_on_ball_lost)
	GameManager.game_started.connect(_spawn_ball)
	GameManager.victory.connect(func(_score: int) -> void: ball.remove_from_play())
	_spawn_ball()


func _physics_process(delta: float) -> void:
	_nudge_timer = maxf(0.0, _nudge_timer - delta)
	if Input.is_action_just_pressed("nudge_left"):
		_nudge(Vector2(-nudge_side_strength, -nudge_side_strength * 0.25))
	if Input.is_action_just_pressed("nudge_right"):
		_nudge(Vector2(nudge_side_strength, -nudge_side_strength * 0.25))
	if Input.is_action_just_pressed("nudge_up"):
		_nudge(Vector2(0, -nudge_up_strength))

	if ball.in_play and not table_bounds.has_point(ball.global_position):
		ball.remove_from_play()
		GameManager.ball_drained()


## Restart (R) is handled by the pause menu, which asks for confirmation.
func _unhandled_input(event: InputEvent) -> void:
	if debug_mouse_drop and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed:
		ball.place(get_global_mouse_position())


func _spawn_ball() -> void:
	ball.place(spawn_point)


func _on_ball_lost() -> void:
	var round_at_loss := GameManager.round_id
	await get_tree().create_timer(respawn_delay).timeout
	if round_at_loss == GameManager.round_id and not GameManager.is_game_over:
		_spawn_ball()


## Shove the cabinet: the ball gets a velocity change and the table jolts.
func _nudge(impulse: Vector2) -> void:
	if _nudge_timer > 0.0 or GameManager.tilted or GameManager.is_game_over:
		return
	_nudge_timer = nudge_cooldown
	if ball.in_play:
		ball.add_impulse(impulse)
	GameManager.add_tilt(nudge_tilt_cost)
	_shake(impulse.normalized())


func _shake(dir: Vector2) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_property(camera, "offset", dir * shake_distance, 0.04)
	_shake_tween.tween_property(camera, "offset", -dir * shake_distance * 0.4, 0.08)
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.1)


func _draw() -> void:
	draw_rect(Rect2(-100, -100, 800, 1400), background_color.darkened(0.5))
	draw_rect(Rect2(20, 20, 560, 1100), background_color)
	_draw_playfield_art()


## Decorative artwork printed on the playfield (no physics).
func _draw_playfield_art() -> void:
	var accent := Color(0.35, 0.45, 0.9, 0.35)
	# Ring around the pop bumpers and the boss.
	draw_arc(Vector2(280, 345), 112.0, 0.0, TAU, 64, accent, 3.0, true)
	draw_arc(Vector2(280, 345), 120.0, 0.0, TAU, 64, Color(accent, 0.15), 2.0, true)
	# Arrow inserts leading into each tunnel mouth (follow the tunnels if moved).
	for node in get_tree().get_nodes_in_group("tunnels"):
		var tunnel := node as Tunnel
		if tunnel and tunnel.path.size() >= 2:
			var mouth := tunnel.to_global(tunnel.path[0])
			var dir := tunnel.path[1] - tunnel.path[0]
			_draw_arrows(mouth, dir, Color(tunnel.color, 0.45))
	# Drain hole at the bottom of the funnel.
	draw_rect(Rect2(252, 1076, 56, 50), Color(0.01, 0.01, 0.02))
	draw_line(Vector2(252, 1077), Vector2(308, 1077), Color(1, 0.25, 0.2, 0.6), 2.0)
	# Outlane danger stripes.
	for x in [40.0, 520.0]:
		for i in 4:
			var y := 850.0 + i * 40.0
			draw_line(Vector2(x - 10, y), Vector2(x + 10, y + 10), Color(1, 0.25, 0.2, 0.35), 4.0, true)
	# Title between the slingshots.
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(180, 860), "PINBALL", HORIZONTAL_ALIGNMENT_CENTER, 200, 30, Color(1, 1, 1, 0.12))


func _draw_arrows(mouth: Vector2, dir: Vector2, c: Color) -> void:
	var d := dir.normalized()
	var side := d.orthogonal() * 9.0
	for k in 3:
		var tip := mouth - d * (34.0 + k * 22.0)
		var col := Color(c, c.a * (1.0 - k * 0.25))
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 + side, tip - d * 14.0 - side]), col)
