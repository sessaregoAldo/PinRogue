extends CanvasLayer
## On-screen controls for phones and tablets (multi-touch).
##
## - Bottom-left / bottom-right buttons: hold to raise the left / right flipper.
##   The whole lower band of each side counts, so you don't have to hit exactly.
## - Launcher (bottom-right lane): touch it, drag down to pull the plunger back,
##   release to fire. The further you pull, the stronger the launch.
## - Nudge, set in Options > Controls:
##     "swipe": a quick swipe left / right / up in the upper part of the screen.
##     "tilt":  jolt the phone left / right, or push it away from you for an up nudge.
## - "II" button (top middle): pause menu (phones have no Esc key).
## Shown automatically on touch screens; Options > Controls can force it on or off.

const FLIP_TOP := 760.0 # touches below this line are flipper / launcher touches
const SPLIT_X := 300.0 # left / right flipper boundary
const PLUNGER_X := 522.0 # touches right of this (in the lower band) drive the launcher
const PLUNGER_DRAG_FULL := 150.0 # px of downward drag for a full-power launch
const SWIPE_MIN := 60.0
const SWIPE_MAX_TIME := 0.4
const TILT_THRESHOLD := 6.5 # m/s² of sudden change (gravity filtered out)
const TILT_COOLDOWN := 0.45
const LEFT_BUTTON := Rect2(14, 1004, 170, 98)
const RIGHT_BUTTON := Rect2(336, 1004, 170, 98)
const PLUNGER_ZONE := Rect2(526, 860, 70, 250)

var enabled: bool = false

var _touches: Dictionary = {} # finger index -> {"role", "start", "time"}
var _seen_touch: bool = false
var _canvas: Control
var _pause_button: Button
var _gravity: Vector3 = Vector3.ZERO
var _tilt_cooldown: float = 0.0
var _hint_time: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS # releases must register even while paused
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.position = Vector2(274, 2)
	_pause_button.size = Vector2(52, 40)
	_pause_button.add_theme_font_size_override("font_size", 20)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(_on_pause_pressed)
	add_child(_pause_button)
	GameManager.controls_changed.connect(_refresh_enabled)
	GameManager.game_started.connect(func() -> void: _hint_time = 5.0)
	_refresh_enabled()


func _refresh_enabled() -> void:
	var mode := GameManager.touch_controls
	enabled = mode == "on" or (mode == "auto" and (DisplayServer.is_touchscreen_available() or _seen_touch))
	_canvas.visible = enabled
	_pause_button.visible = enabled
	if not enabled:
		_release_all()


func _process(delta: float) -> void:
	if not enabled:
		return
	_pulse += delta
	_hint_time = maxf(0.0, _hint_time - delta)
	if _blocked():
		_release_all() # a menu opened: never leave a flipper stuck up
	elif GameManager.nudge_mode == "tilt":
		_read_tilt(delta)
	_canvas.queue_redraw()


func _blocked() -> bool:
	return get_tree().paused or GameManager.choosing or GameManager.entering_name


# --- Touch input ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not _seen_touch:
			_seen_touch = true
			_refresh_enabled()
		if not enabled:
			return
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index, event.position)
	elif event is InputEventScreenDrag and enabled:
		_on_drag(event.index, event.position)


func _on_press(index: int, pos: Vector2) -> void:
	if _blocked():
		return
	var role := "swipe"
	if pos.y >= FLIP_TOP:
		if PLUNGER_ZONE.has_point(pos) or pos.x >= PLUNGER_X:
			role = "plunger"
		elif pos.x < SPLIT_X:
			role = "flip_l"
		else:
			role = "flip_r"
	_touches[index] = {"role": role, "start": pos, "time": Time.get_ticks_msec() / 1000.0}
	match role:
		"flip_l":
			Input.action_press("flipper_left")
		"flip_r":
			Input.action_press("flipper_right")
		"plunger":
			var plunger := _plunger()
			if plunger:
				plunger.touch_set_charge(0.0)


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t["role"] == "plunger":
		var plunger := _plunger()
		if plunger:
			plunger.touch_set_charge((pos.y - (t["start"] as Vector2).y) / PLUNGER_DRAG_FULL)


func _on_release(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	_touches.erase(index)
	match t["role"]:
		"flip_l":
			if not _role_held("flip_l"):
				Input.action_release("flipper_left")
		"flip_r":
			if not _role_held("flip_r"):
				Input.action_release("flipper_right")
		"plunger":
			var plunger := _plunger()
			if plunger:
				plunger.touch_release()
		"swipe":
			if GameManager.nudge_mode == "swipe" and not _blocked():
				var d: Vector2 = pos - (t["start"] as Vector2)
				var dt: float = Time.get_ticks_msec() / 1000.0 - float(t["time"])
				if d.length() >= SWIPE_MIN and dt <= SWIPE_MAX_TIME:
					if absf(d.x) > absf(d.y):
						_nudge(Vector2(signf(d.x), 0.0))
					elif d.y < 0.0:
						_nudge(Vector2.UP)


func _role_held(role: String) -> bool:
	for t in _touches.values():
		if t["role"] == role:
			return true
	return false


func _release_all() -> void:
	for t in _touches.values():
		if t["role"] == "plunger":
			var plunger := _plunger()
			if plunger:
				plunger.touch_release()
	_touches.clear()
	if Input.is_action_pressed("flipper_left") and not Input.is_physical_key_pressed(KEY_Z) and not Input.is_physical_key_pressed(KEY_LEFT):
		Input.action_release("flipper_left")
	if Input.is_action_pressed("flipper_right") and not Input.is_physical_key_pressed(KEY_M) \
			and not Input.is_physical_key_pressed(KEY_SLASH) and not Input.is_physical_key_pressed(KEY_RIGHT):
		Input.action_release("flipper_right")


# --- Tilt nudges --------------------------------------------------------------

## A nudge is a sudden jolt: compare the accelerometer with a slow running
## average (which tracks gravity and how the phone is held).
func _read_tilt(delta: float) -> void:
	_tilt_cooldown = maxf(0.0, _tilt_cooldown - delta)
	var acc := Input.get_accelerometer()
	if acc == Vector3.ZERO:
		return # no sensor data (desktop, or permission not granted)
	if _gravity == Vector3.ZERO:
		_gravity = acc
	_gravity = _gravity.lerp(acc, 1.0 - exp(-4.0 * delta))
	var jolt := acc - _gravity
	if _tilt_cooldown > 0.0:
		return
	if absf(jolt.x) > TILT_THRESHOLD:
		_nudge(Vector2(signf(jolt.x), 0.0))
		_tilt_cooldown = TILT_COOLDOWN
	elif absf(jolt.z) > TILT_THRESHOLD:
		_nudge(Vector2.UP) # pushing the phone away from you (or pulling it in)
		_tilt_cooldown = TILT_COOLDOWN


func _nudge(dir: Vector2) -> void:
	var game := get_parent()
	if game and game.has_method("nudge_direction"):
		game.nudge_direction(dir)


func _plunger() -> Plunger:
	var game := get_parent()
	if game == null or not ("level" in game) or game.level == null:
		return null
	return game.level.get_node_or_null("Plunger") as Plunger


func _on_pause_pressed() -> void:
	if GameManager.choosing or GameManager.entering_name:
		return
	var press := InputEventAction.new()
	press.action = "pause"
	press.pressed = true
	Input.parse_input_event(press)


# --- Drawing --------------------------------------------------------------------

func _draw_controls() -> void:
	var font := ThemeDB.fallback_font
	_draw_button(LEFT_BUTTON, _role_held("flip_l"), -1.0)
	_draw_button(RIGHT_BUTTON, _role_held("flip_r"), 1.0)
	# Launcher: a pull-down hint while a ball waits in it.
	var plunger := _plunger()
	var pulling := _role_held("plunger")
	if plunger and (plunger.has_ball() or pulling):
		var zone := PLUNGER_ZONE
		var a := 0.25 + 0.15 * sin(_pulse * 4.0) if not pulling else 0.45
		_canvas.draw_rect(zone, Color(1, 1, 1, a * 0.25))
		_canvas.draw_rect(zone, Color(1, 1, 1, a), false, 2.0)
		var cx := zone.position.x + zone.size.x * 0.5
		for k in 3:
			var y := zone.position.y + 60.0 + k * 22.0 + (fmod(_pulse * 30.0, 22.0) if not pulling else 0.0)
			_canvas.draw_polyline(PackedVector2Array([Vector2(cx - 12, y), Vector2(cx, y + 10), Vector2(cx + 12, y)]), Color(1, 1, 1, a + 0.2), 3.0, true)
		_canvas.draw_string(font, zone.position + Vector2(0, 30), "PULL", HORIZONTAL_ALIGNMENT_CENTER, zone.size.x, 15, Color(1, 1, 1, a + 0.3))
	# Nudge hint for a few seconds at the start of a run.
	if _hint_time > 0.0:
		var text := "Swipe < ^ > to nudge" if GameManager.nudge_mode == "swipe" else "Jolt the phone to nudge"
		_canvas.draw_string_outline(font, Vector2(0, 735), text, HORIZONTAL_ALIGNMENT_CENTER, 600, 18, 5, Color(0, 0, 0, minf(1.0, _hint_time)))
		_canvas.draw_string(font, Vector2(0, 735), text, HORIZONTAL_ALIGNMENT_CENTER, 600, 18, Color(1, 1, 1, minf(1.0, _hint_time) * 0.85))


func _draw_button(rect: Rect2, held: bool, side: float) -> void:
	var fill := Color(1, 1, 1, 0.22 if held else 0.08)
	_canvas.draw_rect(rect, fill)
	_canvas.draw_rect(rect, Color(1, 1, 1, 0.45 if held else 0.28), false, 2.0)
	# Flipper-shaped icon pointing toward the middle of the table.
	var c := rect.get_center()
	var pivot := c + Vector2(-34.0 * side, 4.0)
	var tip := c + Vector2(34.0 * side, -10.0 if held else 14.0)
	_canvas.draw_line(pivot, tip, Color(Palette.FLIPPER, 0.75 if held else 0.5), 14.0, true)
	_canvas.draw_circle(pivot, 9.0, Color(Palette.FLIPPER, 0.75 if held else 0.5))
