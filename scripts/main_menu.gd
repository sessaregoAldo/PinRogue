extends Node2D
## Main menu: Start Run, Options, Leaderboard, Machines (once there are more
## than 2 levels), Exit (desktop only). The first machine is shown dimmed in
## the background. Start Run fades to black and opens the game, which fades in
## on round 1.

const GAME_SCENE := "res://scenes/game.tscn"
const BUTTON_SIZE := Vector2(280, 52)
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)

var _pages: Array[Control] = []
var _main_page: VBoxContainer
var _options_page: VBoxContainer
var _leaderboard_page: VBoxContainer
var _machines_page: VBoxContainer
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _main_page.visible:
		get_viewport().set_input_as_handled()
		_back()


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


func _back() -> void:
	if _options_page.visible:
		Sfx.save_settings()
	Sfx.play("click")
	_show_page(_main_page)


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
	_start_button = _button(_main_page, "Start Run", _start_run)
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


func _small_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(56, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
