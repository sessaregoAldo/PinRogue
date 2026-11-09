extends CanvasLayer
## On-screen controls for phones and tablets (multi-touch).
##
## - Bottom band (below the flippers): hold the left / right half to raise the
##   left / right flipper. It spans the whole width once the ball is launched.
## - Launcher (bottom-right lane, while a ball waits in it): touch it, drag down
##   to pull the plunger back, release to fire. The further you pull, the stronger.
## - Nudge, set in Options > Controls:
##     "swipe": a quick swipe left / right / up anywhere on the screen. A swipe
##              that starts on a flipper button still nudges (and lets go of it).
##     "tilt":  jolt the phone left / right, or push it away from you for an up nudge.
## - "II" button (top middle): pause menu (phones have no Esc key).
## Shown automatically on touch screens; Options > Controls can force it on or off.

const FLIP_TOP := 975.0 # flipper buttons start here (level with the flippers, never above)
const SPLIT_X := 300.0 # left / right flipper boundary
const PLUNGER_X := 522.0 # while a ball waits, touches right of this drive the launcher
const PLUNGER_DRAG_FULL := 300.0 # px of downward drag for a full-power launch...
const PLUNGER_DRAG_MIN := 110.0 # ...shortened to the room left below the finger (never below this)
const SWIPE_MIN := 40.0 # px the finger must travel...
const SWIPE_WINDOW := 0.35 # ...within this many seconds (measured over a sliding window)
const SWIPE_SIDE_RATIO := 0.75 # sideways wins unless the swipe is clearly vertical
const TILT_THRESHOLD := 6.5 # m/s² of sudden change (gravity filtered out)
const TILT_COOLDOWN := 0.45
const PLUNGER_ZONE := Rect2(524, 640, 72, 470)

var enabled: bool = false

var _touches: Dictionary = {} # finger index -> {"role", "start", "samples"}
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
	if _launcher_ready() and (PLUNGER_ZONE.has_point(pos) or (pos.y >= FLIP_TOP and pos.x >= PLUNGER_X)):
		role = "plunger"
	elif pos.y >= FLIP_TOP:
		role = "flip_l" if pos.x < SPLIT_X else "flip_r"
	_touches[index] = {"role": role, "start": pos, "samples": [[pos, _now()]], "full": _pull_length(pos)}
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
			plunger.touch_set_charge((pos.y - (t["start"] as Vector2).y) / float(t["full"]))
	else:
		_track_swipe(t, pos)


## Swipes win over flippers: any non-launcher finger that moves far enough, fast
## enough, nudges. The check uses a sliding time window, so a slow start or a
## curved path still counts, and one long swipe can nudge again after a pause.
func _track_swipe(t: Dictionary, pos: Vector2) -> void:
	if GameManager.nudge_mode != "swipe" or _blocked():
		return
	var now := _now()
	var samples: Array = t["samples"]
	samples.append([pos, now])
	while samples.size() > 1 and now - float(samples[0][1]) > SWIPE_WINDOW:
		samples.pop_front()
	var d: Vector2 = pos - (samples[0][0] as Vector2)
	if d.length() < SWIPE_MIN:
		return
	var dir := Vector2.ZERO
	if absf(d.x) >= absf(d.y) * SWIPE_SIDE_RATIO:
		dir = Vector2(signf(d.x), 0.0)
	elif d.y < 0.0:
		dir = Vector2.UP
	else:
		return # swiping down does nothing
	_nudge(dir)
	samples.clear()
	samples.append([pos, now])
	var role: String = t["role"]
	if role == "flip_l" or role == "flip_r":
		t["role"] = "swipe" # this finger was nudging, not flipping
		_release_flipper(role)


func _release_flipper(role: String) -> void:
	if _role_held(role):
		return # another finger still holds it
	Input.action_release("flipper_left" if role == "flip_l" else "flipper_right")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Drag distance for full power from a touch at `start`: the full length if it
## fits above the bottom of the screen, otherwise whatever room is left, so the
## pull stays proportional wherever the finger lands.
func _pull_length(start: Vector2) -> float:
	var bottom := _canvas.get_viewport_rect().size.y - 12.0
	return clampf(bottom - start.y, PLUNGER_DRAG_MIN, PLUNGER_DRAG_FULL)


## True while a ball rests in the launcher (or a finger is pulling it back).
func _launcher_ready() -> bool:
	if _role_held("plunger"):
		return true
	var plunger := _plunger()
	return plunger != null and plunger.has_ball()


func _on_release(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t["role"] != "plunger":
		_track_swipe(t, pos) # a flick may end before the last drag event arrives
	_touches.erase(index)
	match t["role"]:
		"flip_l", "flip_r":
			_release_flipper(t["role"])
		"plunger":
			var plunger := _plunger()
			if plunger:
				plunger.touch_release()


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
	var view := _canvas.get_viewport_rect().size
	var loaded := _launcher_ready()
	var right_end := PLUNGER_X if loaded else view.x
	_draw_button(Rect2(0, FLIP_TOP, SPLIT_X, view.y - FLIP_TOP), _role_held("flip_l"), -1.0)
	_draw_button(Rect2(SPLIT_X, FLIP_TOP, right_end - SPLIT_X, view.y - FLIP_TOP), _role_held("flip_r"), 1.0)
	# Launcher: a pull-down hint while a ball waits in it.
	var pulling := _role_held("plunger")
	if loaded:
		var zone := PLUNGER_ZONE
		var a := 0.25 + 0.15 * sin(_pulse * 4.0) if not pulling else 0.45
		_canvas.draw_rect(zone, Color(1, 1, 1, a * 0.25))
		_canvas.draw_rect(zone, Color(1, 1, 1, a), false, 2.0)
		var cx := zone.position.x + zone.size.x * 0.5
		if pulling:
			_draw_pull_meter(cx, font)
		else:
			_draw_pull_hint(zone, cx, a, font)

	# Nudge hint for a few seconds at the start of a run.
	if _hint_time > 0.0:
		var text := "Swipe < ^ > to nudge" if GameManager.nudge_mode == "swipe" else "Jolt the phone to nudge"
		_canvas.draw_string_outline(font, Vector2(0, 735), text, HORIZONTAL_ALIGNMENT_CENTER, 600, 18, 5, Color(0, 0, 0, minf(1.0, _hint_time)))
		_canvas.draw_string(font, Vector2(0, 735), text, HORIZONTAL_ALIGNMENT_CENTER, 600, 18, Color(1, 1, 1, minf(1.0, _hint_time) * 0.85))


func _draw_pull_hint(zone: Rect2, cx: float, a: float, font: Font) -> void:
	_canvas.draw_string(font, zone.position + Vector2(0, 30), "PULL", HORIZONTAL_ALIGNMENT_CENTER, zone.size.x, 15, Color(1, 1, 1, a + 0.3))
	for k in 5:
		var y := zone.position.y + 60.0 + k * 34.0 + fmod(_pulse * 40.0, 34.0)
		_canvas.draw_polyline(PackedVector2Array([Vector2(cx - 12, y), Vector2(cx, y + 10), Vector2(cx + 12, y)]), Color(1, 1, 1, a + 0.2), 3.0, true)


## While pulling: a track from where the finger started to the full-power point,
## filled as far as the plunger is drawn back, with the launch power in percent.
func _draw_pull_meter(cx: float, font: Font) -> void:
	var t: Dictionary = {}
	for touch in _touches.values():
		if touch["role"] == "plunger":
			t = touch
	var plunger := _plunger()
	if t.is_empty() or plunger == null:
		return
	var top: float = (t["start"] as Vector2).y
	var bottom: float = top + float(t["full"])
	var charge := plunger.charge
	var power := Color(0.35, 1.0, 0.45).lerp(Color(1.0, 0.85, 0.2), minf(1.0, charge * 2.0)) 			.lerp(Color(1.0, 0.3, 0.2), maxf(0.0, charge * 2.0 - 1.0))
	_canvas.draw_line(Vector2(cx, top), Vector2(cx, bottom), Color(1, 1, 1, 0.25), 14.0)
	_canvas.draw_line(Vector2(cx, top), Vector2(cx, lerpf(top, bottom, charge)), power, 14.0)
	_canvas.draw_line(Vector2(cx - 16, bottom), Vector2(cx + 16, bottom), Color(1, 1, 1, 0.7), 3.0)
	var label := "%d%%" % int(round(charge * 100.0))
	var at := Vector2(PLUNGER_ZONE.position.x - 6.0, top - 12.0)
	_canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, PLUNGER_ZONE.size.x + 12.0, 20, 5, Color.BLACK)
	_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, PLUNGER_ZONE.size.x + 12.0, 20, power)


func _draw_button(rect: Rect2, held: bool, side: float) -> void:
	rect = rect.grow(-4.0)
	var fill := Color(1, 1, 1, 0.18 if held else 0.05)
	_canvas.draw_rect(rect, fill)
	_canvas.draw_rect(rect, Color(1, 1, 1, 0.4 if held else 0.2), false, 2.0)
	# Flipper-shaped icon in the lower part (clear of the real flippers),
	# pointing toward the middle of the table.
	var c := Vector2(rect.get_center().x, rect.end.y - 40.0)
	var pivot := c + Vector2(-34.0 * side, 4.0)
	var tip := c + Vector2(34.0 * side, -10.0 if held else 14.0)
	_canvas.draw_line(pivot, tip, Color(Palette.FLIPPER, 0.75 if held else 0.5), 14.0, true)
	_canvas.draw_circle(pivot, 9.0, Color(Palette.FLIPPER, 0.75 if held else 0.5))
