extends Node2D
## The game shell: holds the current level (table layout), the ball, HUD and
## menus. Loads levels from LevelRegistry, spawns the ball at the level's
## launcher, handles nudging (with tilt), camera shake and level switching.
##
## - A new run (GameManager.game_started) loads GameManager.start_level.
## - Continue after a boss (GameManager.round_continued) loads a random other
##   level and puts the ball back in the launcher; score, balls and power-ups
##   carry over.
## - Debug builds only: F9 / F10 switch to the previous / next level.

const MAIN_MENU := "res://scenes/main_menu.tscn"

## The player nudged the machine (keys, swipe or tilt). Used by the tutorial.
signal nudged(dir: Vector2)

@export var respawn_delay: float = 1.0
@export_group("Nudge")
@export var nudge_side_strength: float = 420.0
@export var nudge_up_strength: float = 480.0
@export var nudge_cooldown: float = 0.28
@export var nudge_tilt_cost: float = 1.0
@export var shake_distance: float = 8.0
@export_group("Debug")
## Ctrl + left-click anywhere to drop the ball there (handy for tuning).
@export var debug_mouse_drop: bool = true

@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D
@onready var level_holder: Node2D = $LevelHolder
@onready var hud: Node = $HUD

## The level currently being played.
var level: Level

var _nudge_timer: float = 0.0
var _shake_tween: Tween
var _fade: ColorRect


func _ready() -> void:
	_build_fade()
	GameManager.nudge_cost = nudge_tilt_cost
	GameManager.ball_lost.connect(_on_ball_lost)
	GameManager.ball_saved.connect(_on_ball_saved)
	GameManager.game_started.connect(_on_game_started)
	GameManager.round_continued.connect(_on_round_continued)
	GameManager.victory.connect(func(_score: float) -> void: ball.remove_from_play())
	var stuck_hint := StuckHint.new()
	stuck_hint.name = "StuckHint"
	add_child(stuck_hint)
	var countdown := ResumeCountdown.new()
	countdown.name = "ResumeCountdown"
	add_child(countdown)
	var multiball := Multiball.new()
	multiball.name = "Multiball"
	multiball.game = self
	add_child(multiball)
	if GameManager.game_mode == "story":
		var director := StoryDirector.new()
		director.name = "StoryDirector"
		director.game = self
		add_child(director) # before restart(), so it hears game_started
	if GameManager.game_mode == "tutorial":
		var tutorial := Tutorial.new()
		tutorial.game = self
		add_child(tutorial) # before restart(), so it hears game_started
	GameManager.restart() # every visit to this scene starts a fresh run
	fade_in()


func _physics_process(delta: float) -> void:
	_nudge_timer = maxf(0.0, _nudge_timer - delta)
	var can_nudge := GameManager.player_can("nudge")
	if can_nudge and Input.is_action_just_pressed("nudge_left"):
		_nudge(Vector2(-nudge_side_strength, -nudge_side_strength * 0.25))
	if can_nudge and Input.is_action_just_pressed("nudge_right"):
		_nudge(Vector2(nudge_side_strength, -nudge_side_strength * 0.25))
	if can_nudge and Input.is_action_just_pressed("nudge_up"):
		_nudge(Vector2(0, -nudge_up_strength))

	if level:
		for node in get_tree().get_nodes_in_group("ball"):
			var b := node as Ball
			if b and b.in_play and not level.table_bounds.has_point(b.global_position):
				GameManager.drain_ball(b)


## Restart (R) is handled by the pause menu, which asks for confirmation.
func _unhandled_input(event: InputEvent) -> void:
	if debug_mouse_drop and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed:
		ball.place(get_global_mouse_position())
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and not get_tree().paused:
		if event.physical_keycode == KEY_F9:
			switch_level(GameManager.current_level - 1)
		elif event.physical_keycode == KEY_F10:
			switch_level(GameManager.current_level + 1)


# --- Levels ---------------------------------------------------------------------

## Load a level (index into LevelRegistry) and put the ball in its launcher.
## Score, balls and power-ups are untouched.
func switch_level(index: int) -> void:
	_load_level(posmod(index, LevelRegistry.count()))
	_spawn_ball()
	hud.show_banner("ROUND %d  ·  %s" % [GameManager.boss_round, level.level_name])


func _load_level(index: int) -> void:
	if level:
		level_holder.remove_child(level)
		level.queue_free()
	level = LevelRegistry.instantiate(index)
	level_holder.add_child(level)
	GameManager.current_level = index
	GameManager.level_changed.emit(level)


func _on_game_started() -> void:
	_load_level(GameManager.start_level)
	_spawn_ball()
	if GameManager.game_mode != "story": # the StoryDirector shows the chapter banner
		hud.show_banner("ROUND 1  ·  %s" % level.level_name)


func _on_round_continued(_round_number: int) -> void:
	switch_level(LevelRegistry.random_other(GameManager.current_level))


func _spawn_ball() -> void:
	ball.place(level.spawn_point)
	GameManager.ball_reset_to_launcher()


func _on_ball_saved() -> void:
	hud.show_banner("BALL SAVED", 0.8)
	_on_ball_lost()


func _on_ball_lost() -> void:
	var round_at_loss := GameManager.round_id
	await get_tree().create_timer(respawn_delay).timeout
	if round_at_loss == GameManager.round_id and not GameManager.is_game_over:
		_spawn_ball()


# --- Nudge ----------------------------------------------------------------------

## Nudge in a direction: Vector2.LEFT, Vector2.RIGHT or Vector2.UP (touch swipes / phone tilt).
func nudge_direction(dir: Vector2) -> void:
	if dir.x < 0.0:
		_nudge(Vector2(-nudge_side_strength, -nudge_side_strength * 0.25))
	elif dir.x > 0.0:
		_nudge(Vector2(nudge_side_strength, -nudge_side_strength * 0.25))
	else:
		_nudge(Vector2(0, -nudge_up_strength))


## Shove the cabinet: the ball gets a velocity change and the table jolts.
func _nudge(impulse: Vector2) -> void:
	if _nudge_timer > 0.0 or GameManager.tilted or GameManager.is_game_over:
		return
	_nudge_timer = nudge_cooldown
	for node in get_tree().get_nodes_in_group("ball"): # every ball, for multiball
		var b := node as Ball
		if b and b.in_play:
			b.add_impulse(impulse)
	GameManager.add_tilt(nudge_tilt_cost)
	_shake(impulse.normalized())
	nudged.emit(impulse.normalized())


func _shake(dir: Vector2) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_property(camera, "offset", dir * shake_distance, 0.04)
	_shake_tween.tween_property(camera, "offset", -dir * shake_distance * 0.4, 0.08)
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.1)


# --- Camera close-up (story mode's victory) ---------------------------------------

var _focus_tween: Tween
const CAMERA_HOME := Vector2(300, 560)


## Zoom in on `point` over `seconds` of real time (works during slow motion).
func focus_camera(point: Vector2, zoom: float, seconds: float) -> void:
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	_focus_tween.tween_property(camera, "position", point, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(camera, "zoom", Vector2.ONE * zoom, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Back to the whole table (instantly when `seconds` is 0).
func reset_camera(seconds: float) -> void:
	if _focus_tween:
		_focus_tween.kill()
	if seconds <= 0.0:
		camera.position = CAMERA_HOME
		camera.zoom = Vector2.ONE
		return
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	_focus_tween.tween_property(camera, "position", CAMERA_HOME, seconds).set_trans(Tween.TRANS_SINE)
	_focus_tween.tween_property(camera, "zoom", Vector2.ONE, seconds).set_trans(Tween.TRANS_SINE)


# --- Transitions ----------------------------------------------------------------

func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func fade_in() -> void:
	_fade.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


## Fade to black, then go to the main menu.
func go_to_main_menu() -> void:
	Engine.time_scale = 1.0 # the tutorial freezes the clock; the fade needs it running
	get_tree().paused = false
	GameManager.choosing = false
	GameManager.entering_name = false
	_fade.process_mode = Node.PROCESS_MODE_ALWAYS
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.4)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
