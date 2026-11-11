class_name StuckHint
extends CanvasLayer
## "Ball stuck? Nudge!" hint: shown when a ball in play has barely moved for
## STUCK_TIME seconds anywhere except the shooter lane, and while it isn't being
## held on a raised flipper. Hides as soon as the ball moves again.
## Keyboard players see their nudge keys; touch players are told to swipe.

## Seconds a ball has to sit still before the hint shows.
const STUCK_TIME := 2.5
## A ball that stays within this many pixels counts as not moving.
const STUCK_RADIUS := 14.0
## The shooter lane (plunger) is right of this x: a ball waiting there is fine.
const LANE_X := 515.0
const LANE_TOP := 300.0
## Below this y a ball can rest on a held flipper (cradled), which is on purpose.
const CRADLE_Y := 880.0

## ball -> {"anchor": Vector2, "time": float}
var _still: Dictionary = {}
var _label: Label
var _touch: bool = false
var _shown: bool = false


func _ready() -> void:
	layer = 11 # above the HUD, below touch controls and menus
	_touch = DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")
	_label = Label.new()
	_label.position = Vector2(0, 655)
	_label.size = Vector2(600, 70)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)
	GameManager.game_started.connect(_reset)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch = true
	elif event is InputEventKey and event.pressed:
		_touch = false


func _reset() -> void:
	_still.clear()
	_set_shown(false)


func _physics_process(delta: float) -> void:
	var stuck := false
	if _active():
		var flipper_held := _flipper_held()
		var seen := {}
		for node in get_tree().get_nodes_in_group("ball"):
			var ball := node as Ball
			if ball == null or not ball.in_play or not ball.visible:
				continue
			seen[ball] = true
			var p := ball.global_position
			var info: Dictionary = _still.get(ball, {"anchor": p, "time": 0.0})
			var excused := (p.x > LANE_X and p.y > LANE_TOP) or (flipper_held and p.y > CRADLE_Y)
			if excused or p.distance_to(info["anchor"]) > STUCK_RADIUS:
				info = {"anchor": p, "time": 0.0}
			else:
				info["time"] = float(info["time"]) + delta
			_still[ball] = info
			if float(info["time"]) >= STUCK_TIME:
				stuck = true
		for ball in _still.keys():
			if not seen.has(ball):
				_still.erase(ball)
	else:
		_still.clear()
	_set_shown(stuck)


func _process(_delta: float) -> void:
	if _shown:
		_label.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)


func _active() -> bool:
	return GameManager.game_mode != "tutorial" and not GameManager.is_game_over \
			and not GameManager.tilted and not GameManager.choosing


## Touch flippers press the same actions as the keys.
func _flipper_held() -> bool:
	return Input.is_action_pressed("flipper_left") or Input.is_action_pressed("flipper_right")


func _set_shown(on: bool) -> void:
	if on == _shown:
		return
	_shown = on
	if on:
		_label.text = _hint_text()
		_label.modulate.a = 1.0
	else:
		_label.modulate.a = 0.0


func _hint_text() -> String:
	if _touch:
		return "Ball stuck? Swipe to nudge the table!"
	return "Ball stuck? Nudge!   %s  %s  %s" % [
		GameManager.key_label("nudge_left", "/"),
		GameManager.key_label("nudge_up", "/"),
		GameManager.key_label("nudge_right", "/")]
