extends Node2D
## Main menu: Start Run, Options, Leaderboard, Machines (once there are more
## than 2 levels), Exit (desktop only). The first machine is shown dimmed in
## the background.
##
## Start Run -> pick a game mode (Endless; the others are greyed out until they
## exist) -> a controls summary for this device (PC or touch screen) -> any key,
## click or tap fades to black and opens the game, which fades in on round 1.

const GAME_SCENE := "res://scenes/game.tscn"
const BUTTON_SIZE := Vector2(280, 52)
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)

var _pages: Array[Control] = []
var _main_page: VBoxContainer
var _options_page: VBoxContainer
var _leaderboard_page: VBoxContainer
var _machines_page: VBoxContainer
var _modes_page: VBoxContainer
var _controls_page: VBoxContainer
var _endless_button: Button
var _controls_title: Label
var _controls_grid: GridContainer
var _controls_footer: Label
## Input is ignored on the controls page until this time (so the click / key that
## picked the mode doesn't skip it).
var _controls_ready_at: float = 0.0
## True when the player is using a touch screen (last input was a touch, not a key).
var _touch_used: bool = false
var _start_button: Button
var _settings: SettingsPanel
var _leaderboard: LeaderboardPanel
var _fade: ColorRect
var _starting: bool = false

# Machine browser
var _machine_index: int = 0
var _machine_view: SubViewport
var _machine_name: Label
var _machine_desc: Label
var _machine_count: Label


func _ready() -> void:
	get_tree().paused = false
	_build_background()
	_build_ui()
	_show_page(_main_page)
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.5)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_used = true
	elif event is InputEventKey and event.pressed:
		_touch_used = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _main_page.visible:
		get_viewport().set_input_as_handled()
		_back()
		return
	if _controls_page.visible and _is_any_press(event) \
			and Time.get_ticks_msec() / 1000.0 >= _controls_ready_at:
		get_viewport().set_input_as_handled()
		_start_run()


## A fresh key press, mouse click or gamepad button (a tap arrives as a click).
func _is_any_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	return (event is InputEventMouseButton or event is InputEventJoypadButton) and event.pressed


func _show_page(page: Control) -> void:
	for p in _pages:
		p.visible = p == page
	if page == _main_page:
		_start_button.grab_focus()
	elif page == _options_page:
		_settings.refresh()
		_settings.focus_first()
	elif page == _leaderboard_page:
		_leaderboard.refresh()
	elif page == _machines_page:
		_show_machine(_machine_index)
	elif page == _modes_page:
		_endless_button.grab_focus()
	elif page == _controls_page:
		_fill_controls()
		_controls_ready_at = Time.get_ticks_msec() / 1000.0 + 0.35


func _back() -> void:
	if _options_page.visible:
		Sfx.save_settings()
	Sfx.play("click")
	_show_page(_modes_page if _controls_page.visible else _main_page)


func _pick_mode(mode: String) -> void:
	GameManager.game_mode = mode
	_click_to(_controls_page)


# --- Controls summary -----------------------------------------------------------

## Touch layout if the setting forces it, otherwise whatever the player is using.
func _touch_layout() -> bool:
	match GameManager.touch_controls:
		"on":
			return true
		"off":
			return false
	return _touch_used or (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc"))


func _fill_controls() -> void:
	for child in _controls_grid.get_children():
		_controls_grid.remove_child(child)
		child.queue_free()
	var touch := _touch_layout()
	_controls_title.text = "TOUCH CONTROLS" if touch else "KEYBOARD CONTROLS"
	var rows: Array
	if touch:
		var nudge := "Swipe left, up or right anywhere" if GameManager.nudge_mode == "swipe" \
				else "Jolt the phone left, right or away from you"
		rows = [
			["Flippers", "Hold the left or right half of the bottom of the screen"],
			["Launch", "Drag the launcher (right lane) down and let go. Pull further for more power"],
			["Nudge", nudge + ". Too many in a row: TILT"],
			["Pause", "The II button at the top"],
		]
	else:
		rows = [
			["Left flipper", "Z  or  Left arrow"],
			["Right flipper", "M,  /  or  Right arrow"],
			["Launch", "Hold Space (or Down) and release. Hold longer for more power"],
			["Nudge", "A  W  D  (left, up, right). Too many in a row: TILT"],
			["Pause", "Esc"],
			["Restart", "R"],
		]
	for row: Array in rows:
		var action := Label.new()
		action.text = row[0]
		action.add_theme_font_size_override("font_size", 18)
		action.add_theme_color_override("font_color", GOLD)
		action.custom_minimum_size = Vector2(130, 0)
		_controls_grid.add_child(action)
		var how := Label.new()
		how.text = row[1]
		how.add_theme_font_size_override("font_size", 18)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size = Vector2(300, 0)
		_controls_grid.add_child(how)
	_controls_footer.text = "Tap anywhere to start" if touch else "Press any key or click to start"


func _start_run() -> void:
	if _starting:
		return
	_starting = true
	Sfx.play("click")
	GameManager.start_level = 0
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))


# --- Machine browser ------------------------------------------------------------

func _show_machine(index: int) -> void:
	_machine_index = posmod(index, LevelRegistry.count())
	for child in _machine_view.get_children():
		if child is Level:
			_machine_view.remove_child(child)
			child.queue_free()
	var level := LevelRegistry.instantiate(_machine_index)
	level.process_mode = Node.PROCESS_MODE_DISABLED # just a picture
	_machine_view.add_child(level)
	_machine_name.text = level.level_name
	_machine_desc.text = level.description
	_machine_count.text = "%d / %d" % [_machine_index + 1, LevelRegistry.count()]


# --- Building -------------------------------------------------------------------

func _build_background() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(300, 560)
	add_child(camera)
	var level := LevelRegistry.instantiate(0)
	level.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(level)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var holder := VBoxContainer.new()
	center.add_child(holder)

	# Main page
	_main_page = _page(holder)
	_label(_main_page, "PINROGUE", 64, GOLD)
	_label(_main_page, "a roguelike pinball", 18, SOFT)
	_spacer(_main_page, 24)
	_start_button = _button(_main_page, "Start Run", func() -> void: _click_to(_modes_page))
	_button(_main_page, "Options", func() -> void: _click_to(_options_page))
	_button(_main_page, "Leaderboard", func() -> void: _click_to(_leaderboard_page))
	if LevelRegistry.count() > 2:
		_button(_main_page, "Machines", func() -> void: _click_to(_machines_page))
	if not OS.has_feature("web"): # a browser tab cannot be closed by the game
		_button(_main_page, "Exit", func() -> void: Sfx.quit_game())

	# Options
	_options_page = _page(holder)
	_label(_options_page, "OPTIONS", 40, GOLD)
	_settings = SettingsPanel.new()
	_options_page.add_child(_settings)
	_button(_options_page, "Back", _back)

	# Leaderboard
	_leaderboard_page = _page(holder)
	_label(_leaderboard_page, "LEADERBOARD", 40, GOLD)
	_leaderboard = LeaderboardPanel.new()
	_leaderboard_page.add_child(_leaderboard)
	_button(_leaderboard_page, "Back", _back)

	# Machines (table layouts)
	_machines_page = _page(holder)
	_label(_machines_page, "MACHINES", 40, GOLD)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(270, 504) # the table at 45% size
	_machine_view = SubViewport.new()
	_machine_view.size = Vector2i(270, 504)
	_machine_view.transparent_bg = false
	var cam := Camera2D.new()
	cam.position = Vector2(300, 560)
	cam.zoom = Vector2(0.45, 0.45)
	_machine_view.add_child(cam)
	frame.add_child(_machine_view)
	var frame_row := CenterContainer.new()
	frame_row.add_child(frame)
	_machines_page.add_child(frame_row)
	_machine_name = _label(_machines_page, "", 24, Color.WHITE)
	_machine_desc = _label(_machines_page, "", 14, SOFT)
	_machine_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_machine_desc.custom_minimum_size = Vector2(380, 0)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	_machines_page.add_child(nav)
	_small_button(nav, "<", func() -> void: _click_show(_machine_index - 1))
	_machine_count = Label.new()
	_machine_count.add_theme_font_size_override("font_size", 18)
	nav.add_child(_machine_count)
	_small_button(nav, ">", func() -> void: _click_show(_machine_index + 1))
	_button(_machines_page, "Back", _back)

	# Game modes
	_modes_page = _page(holder)
	_label(_modes_page, "GAME MODE", 40, GOLD)
	_spacer(_modes_page, 8)
	_endless_button = _mode(_modes_page, "Endless",
			"Beat the boss, take its power-ups and keep going. How far can you get?",
			func() -> void: _pick_mode("endless"))
	_mode(_modes_page, "Story Mode", "Coming soon", Callable())
	_mode(_modes_page, "Daily Challenge", "Coming soon", Callable())
	_mode(_modes_page, "Boss Rush", "Coming soon", Callable())
	_spacer(_modes_page, 8)
	_button(_modes_page, "Back", _back)

	# Controls summary (shown before the first ball)
	_controls_page = _page(holder)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.14, 0.95)
	style.border_color = Color(GOLD, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	var panel_row := CenterContainer.new()
	panel_row.add_child(panel)
	_controls_page.add_child(panel_row)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_controls_title = _label(box, "", 30, GOLD)
	_controls_grid = GridContainer.new()
	_controls_grid.columns = 2
	_controls_grid.add_theme_constant_override("h_separation", 16)
	_controls_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(_controls_grid)
	var goal := _label(box, "Hit the boss bumper until its health runs out. Light every lane in a set to pick a power-up.", 16, SOFT)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size = Vector2(446, 0)
	_controls_footer = _label(_controls_page, "", 22, Color.WHITE)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_controls_footer, "modulate:a", 0.35, 0.7)
	pulse.tween_property(_controls_footer, "modulate:a", 1.0, 0.7)
	var back := _button(_controls_page, "Back", _back)
	back.focus_mode = Control.FOCUS_NONE # Space / Enter should start, not go back

	# Fade overlay for transitions.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 90
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)


func _click_to(page: Control) -> void:
	Sfx.play("click")
	_show_page(page)


func _click_show(index: int) -> void:
	Sfx.play("click")
	_show_machine(index)


func _page(holder: Control) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(page)
	_pages.append(page)
	return page


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	parent.add_child(label)
	return label


func _spacer(parent: Control, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_pressed)
	var row := CenterContainer.new()
	row.add_child(b)
	parent.add_child(row)
	return b


## A game mode: a big button with a short description under it. No callback
## means the mode isn't ready yet, so it is shown greyed out.
func _mode(parent: Control, title: String, desc: String, on_pressed: Callable) -> Button:
	var b := _button(parent, title, on_pressed if on_pressed.is_valid() else func() -> void: pass)
	b.custom_minimum_size = Vector2(320, 52)
	b.disabled = not on_pressed.is_valid()
	var label := _label(parent, desc, 14, SOFT if not b.disabled else Color(0.5, 0.5, 0.58))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(360, 0)
	return b


func _small_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(56, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
