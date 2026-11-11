class_name ResumeCountdown
extends CanvasLayer
## "3 · 2 · 1" before play continues after the pause menu or a spare-part pick
## (GameManager.resume_play). The game stays paused while it counts, so the
## player has a moment to get their fingers back on the flippers.
## Skipped in the tutorial (Sal runs the machine there) and cancelled if the
## pause menu opens again or a new run starts.

const STEPS := 3
const STEP_TIME := 0.5

var _label: Label
var _counting: bool = false
var _run: int = 0 # bumped to cancel a running countdown


func _ready() -> void:
	layer = 19 # above the HUD, spare-part picker and end screen; below the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 120)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.add_theme_constant_override("outline_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	GameManager.resume_requested.connect(_start)
	GameManager.game_started.connect(func() -> void:
		if _counting:
			cancel()
			get_tree().paused = false)


func is_counting() -> bool:
	return _counting


## Stop counting without unpausing (the pause menu opened again).
func cancel() -> void:
	_run += 1
	_counting = false
	_label.visible = false


func _start() -> void:
	if GameManager.game_mode == "tutorial" or GameManager.is_game_over:
		cancel()
		get_tree().paused = false
		return
	_run += 1
	var run := _run
	_counting = true
	get_tree().paused = true
	_label.visible = true
	for n in range(STEPS, 0, -1):
		_label.text = str(n)
		_label.pivot_offset = _label.size * 0.5
		_label.scale = Vector2.ONE * 1.4
		_label.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_property(_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(_label, "modulate:a", 0.35, STEP_TIME).set_delay(0.2)
		Sfx.play("click", 0.0, 1.5)
		await get_tree().create_timer(STEP_TIME, true, false, true).timeout
		if run != _run:
			return
	_counting = false
	_label.visible = false
	get_tree().paused = false
