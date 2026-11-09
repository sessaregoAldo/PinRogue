extends Node2D
## Main menu: Start Run, Options, Leaderboard, Machines (once there are more
## than 2 levels), Exit (desktop only). The first machine is shown dimmed in
## the background.
##
## Start Run -> pick a game mode (Endless; the others are greyed out until they
## exist) -> pick the starting machine (or Random) -> a controls summary for this device (PC or touch screen) -> any key,
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
var _machines_box: VBoxContainer
var _parts_scroll: ScrollContainer
var _tab_machines: Button
var _tab_parts: Button
var _notes_corner: Button
var _modes_page: VBoxContainer
var _notes_page: VBoxContainer
var _notes_scroll: ScrollContainer
var _pick_page: VBoxContainer
var _pick_view: SubViewport
var _pick_name: Label
var _pick_desc: Label
var _pick_count: Label
var _pick_mystery: Label
var _pick_play: Button
## Starting machine choice: -1 = Random, otherwise a LevelRegistry index.
var _pick_index: int = 0
var _pick_cycle_time: float = 0.0
var _pick_cycle_level: int = 0
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
	if _pick_page.visible and not (event is InputEventKey and event.echo):
		if event.is_action_pressed("ui_left") or event.is_action_pressed("flipper_left"):
			get_viewport().set_input_as_handled()
			_click_pick(_pick_index - 1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("flipper_right"):
			get_viewport().set_input_as_handled()
			_click_pick(_pick_index + 1)


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
	_notes_corner.visible = page == _main_page
	if page == _main_page:
		_start_button.grab_focus()
	elif page == _options_page:
		_settings.refresh()
		_settings.focus_first()
	elif page == _leaderboard_page:
		_leaderboard.refresh()
	elif page == _machines_page:
		_show_machine(_machine_index)
		_show_tab(false)
	elif page == _modes_page:
		_endless_button.grab_focus()
	elif page == _notes_page:
		_notes_scroll.scroll_vertical = 0
	elif page == _pick_page:
		_show_pick(_pick_index)
		_pick_play.grab_focus()
	elif page == _controls_page:
		_fill_controls()
		_controls_ready_at = Time.get_ticks_msec() / 1000.0 + 0.35


func _back() -> void:
	if _options_page.visible:
		Sfx.save_settings()
	Sfx.play("click")
	if _controls_page.visible:
		_show_page(_pick_page)
	elif _pick_page.visible:
		_show_page(_modes_page)
	else:
		_show_page(_main_page)


func _pick_mode(mode: String) -> void:
	GameManager.game_mode = mode
	_click_to(_pick_page)


# --- Starting machine -------------------------------------------------------------

func _process(delta: float) -> void:
	# "Random" flips through the machines in its preview.
	if _pick_page.visible and _pick_index < 0:
		_pick_cycle_time -= delta
		if _pick_cycle_time <= 0.0:
			_pick_cycle_time = 0.5
			_pick_cycle_level = (_pick_cycle_level + 1) % LevelRegistry.count()
			_put_level(_pick_view, _pick_cycle_level)


## Entries run Random, machine 1, machine 2, ... and wrap around.
func _show_pick(index: int) -> void:
	_pick_index = posmod(index + 1, LevelRegistry.count() + 1) - 1
	_pick_count.text = "%d / %d" % [_pick_index + 2, LevelRegistry.count() + 1]
	_pick_mystery.visible = _pick_index < 0
	if _pick_index < 0:
		_pick_name.text = "Random"
		_pick_desc.text = "A surprise machine every run."
		_pick_cycle_time = 0.0
	else:
		var level := _put_level(_pick_view, _pick_index)
		_pick_name.text = level.level_name
		_pick_desc.text = level.description


func _click_pick(index: int) -> void:
	Sfx.play("click")
	_show_pick(index)


func _confirm_pick() -> void:
	GameManager.start_random = _pick_index < 0
	GameManager.start_level = maxi(0, _pick_index)
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
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))


# --- Machine browser ------------------------------------------------------------

func _show_machine(index: int) -> void:
	_machine_index = posmod(index, LevelRegistry.count())
	var level := _put_level(_machine_view, _machine_index)
	_machine_name.text = level.level_name
	_machine_desc.text = level.description
	_machine_count.text = "%d / %d" % [_machine_index + 1, LevelRegistry.count()]


## Show a machine (still, as a picture) in a preview viewport.
func _put_level(view: SubViewport, index: int) -> Level:
	for child in view.get_children():
		if child is Level:
			view.remove_child(child)
			child.queue_free()
	var level := LevelRegistry.instantiate(index)
	level.process_mode = Node.PROCESS_MODE_DISABLED # just a picture
	view.add_child(level)
	return level


## A framed preview of a table at 45% size, centered in `parent`.
func _build_preview(parent: Control) -> SubViewport:
	var stack := MarginContainer.new() # stacks the preview and any overlay
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(270, 504)
	var view := SubViewport.new()
	view.size = Vector2i(270, 504)
	view.transparent_bg = false
	var cam := Camera2D.new()
	cam.position = Vector2(300, 560)
	cam.zoom = Vector2(0.45, 0.45)
	view.add_child(cam)
	frame.add_child(view)
	stack.add_child(frame)
	var row := CenterContainer.new()
	row.add_child(stack)
	parent.add_child(row)
	return view


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
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	_machines_page.add_child(tabs)
	_tab_machines = _tab_button(tabs, "Tables", func() -> void: _click_tab(false))
	_tab_parts = _tab_button(tabs, "Spare Parts", func() -> void: _click_tab(true))
	_machines_box = VBoxContainer.new()
	_machines_box.add_theme_constant_override("separation", 12)
	_machines_page.add_child(_machines_box)
	_machine_view = _build_preview(_machines_box)
	_machine_name = _label(_machines_box, "", 24, Color.WHITE)
	_machine_desc = _label(_machines_box, "", 14, SOFT)
	_machine_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_machine_desc.custom_minimum_size = Vector2(380, 0)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	_machines_box.add_child(nav)
	_small_button(nav, "<", func() -> void: _click_show(_machine_index - 1))
	_machine_count = Label.new()
	_machine_count.add_theme_font_size_override("font_size", 18)
	nav.add_child(_machine_count)
	_small_button(nav, ">", func() -> void: _click_show(_machine_index + 1))
	_parts_scroll = ScrollContainer.new()
	_parts_scroll.custom_minimum_size = Vector2(480, 640)
	_parts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parts_scroll.add_child(_build_spare_parts())
	_machines_page.add_child(_parts_scroll)
	_button(_machines_page, "Back", _back)

	# Patch notes
	_notes_page = _page(holder)
	_label(_notes_page, "PATCH NOTES", 40, GOLD)
	_notes_scroll = ScrollContainer.new()
	_notes_scroll.custom_minimum_size = Vector2(480, 700)
	_notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_notes_page.add_child(_notes_scroll)
	_notes_scroll.add_child(_build_patch_notes())
	_button(_notes_page, "Back", _back)

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

	# Starting machine (Endless)
	_pick_page = _page(holder)
	_label(_pick_page, "STARTING MACHINE", 36, GOLD)
	_pick_view = _build_preview(_pick_page)
	var mystery_dim := ColorRect.new() # Random: the flipping preview is dimmed under a big "?"
	mystery_dim.color = Color(0, 0, 0, 0.45)
	_pick_mystery = _label(_pick_page, "?", 160, GOLD)
	_pick_view.get_parent().get_parent().add_child(mystery_dim)
	_pick_page.remove_child(_pick_mystery)
	_pick_view.get_parent().get_parent().add_child(_pick_mystery)
	_pick_mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pick_mystery.visibility_changed.connect(func() -> void: mystery_dim.visible = _pick_mystery.visible)
	_pick_name = _label(_pick_page, "", 24, Color.WHITE)
	_pick_desc = _label(_pick_page, "", 14, SOFT)
	_pick_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick_desc.custom_minimum_size = Vector2(380, 0)
	var pick_nav := HBoxContainer.new()
	pick_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	pick_nav.add_theme_constant_override("separation", 12)
	_pick_page.add_child(pick_nav)
	_small_button(pick_nav, "<", func() -> void: _click_pick(_pick_index - 1)).focus_mode = Control.FOCUS_NONE
	_pick_count = Label.new()
	_pick_count.add_theme_font_size_override("font_size", 18)
	pick_nav.add_child(_pick_count)
	_small_button(pick_nav, ">", func() -> void: _click_pick(_pick_index + 1)).focus_mode = Control.FOCUS_NONE
	_pick_play = _button(_pick_page, "Play", _confirm_pick)
	_button(_pick_page, "Back", _back)

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

	# Small "Patch notes" button in the bottom-left corner, just above the version tag.
	_notes_corner = Button.new()
	_notes_corner.text = "Patch notes"
	_notes_corner.flat = true
	_notes_corner.position = Vector2(2, 1070)
	_notes_corner.size = Vector2(96, 26)
	_notes_corner.add_theme_font_size_override("font_size", 13)
	_notes_corner.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95, 0.8))
	_notes_corner.add_theme_color_override("font_hover_color", GOLD)
	_notes_corner.focus_mode = Control.FOCUS_NONE
	_notes_corner.pressed.connect(func() -> void: _click_to(_notes_page))
	ui.add_child(_notes_corner)

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


# --- Spare parts (power-up list on the Machines page) ------------------------------

func _click_tab(parts: bool) -> void:
	Sfx.play("click")
	_show_tab(parts)


func _show_tab(parts: bool) -> void:
	_machines_box.visible = not parts
	_parts_scroll.visible = parts
	_tab_machines.button_pressed = not parts
	_tab_parts.button_pressed = parts
	if parts:
		_parts_scroll.scroll_vertical = 0


func _tab_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _build_spare_parts() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.custom_minimum_size = Vector2(462, 0)
	var sections := [
		["major", "MAJOR PARTS", "Earned by lighting the machine's lights near the boss."],
		["minor", "MINOR PARTS", "Earned by lighting both inlane lights behind the bottom slingshots."],
	]
	for sec: Array in sections:
		if sec[0] == "minor":
			_spacer(list, 10)
		var head := Label.new()
		head.text = sec[1]
		head.add_theme_font_size_override("font_size", 22)
		head.add_theme_color_override("font_color", PowerupManager.TIER_COLORS[sec[0]])
		list.add_child(head)
		var note := Label.new()
		note.text = sec[2]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(450, 0)
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
		list.add_child(note)
		for part: Dictionary in PowerupManager.POWERUPS:
			if part["tier"] == sec[0]:
				list.add_child(_part_row(part))
	return list


## One power-up: its icon in a colored badge, the name and a short description.
func _part_row(part: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.2, 0.95)
	style.border_color = part["color"]
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(66, 48)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := Label.new()
	icon.text = part["icon"]
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 20 if str(part["icon"]).length() <= 3 else 15)
	icon.add_theme_color_override("font_color", part["color"])
	badge.add_child(icon)
	row.add_child(badge)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = part["title"]
	title.add_theme_font_size_override("font_size", 17)
	text.add_child(title)
	var desc := Label.new()
	desc.text = part["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(370, 0)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	text.add_child(desc)
	row.add_child(text)
	return row


func _build_patch_notes() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(462, 0)
	for i in PatchNotes.NOTES.size():
		var entry: Dictionary = PatchNotes.NOTES[i]
		if i > 0:
			_spacer(list, 14)
		var head := Label.new()
		head.text = "v%s  ·  %s" % [entry["version"], entry["name"]]
		head.add_theme_font_size_override("font_size", 24 if i == 0 else 21)
		head.add_theme_color_override("font_color", GOLD)
		head.add_theme_constant_override("outline_size", 5)
		head.add_theme_color_override("font_outline_color", Color.BLACK)
		list.add_child(head)
		var date := Label.new()
		date.text = str(entry["date"]) + ("   ·   LATEST" if i == 0 else "")
		date.add_theme_font_size_override("font_size", 13)
		date.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
		list.add_child(date)
		for line: String in entry["notes"]:
			var item := Label.new()
			item.text = "•  " + line
			item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.custom_minimum_size = Vector2(450, 0)
			item.add_theme_font_size_override("font_size", 16)
			item.add_theme_color_override("font_color", Color(0.88, 0.9, 0.97))
			list.add_child(item)
	return list


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
