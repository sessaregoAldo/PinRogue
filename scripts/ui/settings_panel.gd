class_name SettingsPanel
extends VBoxContainer
## Settings, in two tabs:
## - Audio: master / effects / music volume, and the score popups toggle.
## - Controls: keyboard bindings (any key for any action; hidden on phones and
##   tablets) and the touch-screen options (shown on touch screens).
## Shared by the pause menu and the main menu. Changes apply immediately;
## call Sfx.save_settings() when leaving the page.

const WIDTH := 320.0
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.7, 0.75, 0.9)
const NUDGE_MODES: Array[String] = ["swipe", "tilt"]
const TOUCH_MODES: Array[String] = ["auto", "on", "off"]

var _tab_audio: Button
var _tab_controls: Button
var _audio_box: VBoxContainer
var _controls_box: VBoxContainer

var _master: HSlider
var _sfx: HSlider
var _music: HSlider
var _popups: CheckButton

var _keys_box: VBoxContainer
var _key_buttons: Dictionary = {} # action -> Button
var _capturing: String = "" # action waiting for a key press
var _touch_box: VBoxContainer
var _nudge_mode: OptionButton
var _touch_mode: OptionButton


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	var group := ButtonGroup.new()
	_tab_audio = _tab_button(tabs, "Audio", group, false)
	_tab_controls = _tab_button(tabs, "Controls", group, true)

	# --- Audio ---
	_audio_box = _section()
	_master = _slider(_audio_box, "Master volume", func(v: float) -> void:
		Sfx.set_master_volume(v)
		Sfx.play("bumper", 0.0, 1.0, 120))
	_sfx = _slider(_audio_box, "Effects volume", func(v: float) -> void:
		Sfx.set_sfx_volume(v)
		Sfx.play("bumper", 0.0, 1.0, 120))
	_music = _slider(_audio_box, "Music volume", func(v: float) -> void: Sfx.set_music_volume(v))
	_popups = CheckButton.new()
	_popups.text = "Score popups"
	_popups.add_theme_font_size_override("font_size", 18)
	_popups.toggled.connect(func(on: bool) -> void:
		Sfx.play("click")
		GameManager.set_show_score_popups(on))
	_audio_box.add_child(_popups)

	# --- Controls ---
	_controls_box = _section()
	_keys_box = VBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", 6)
	_controls_box.add_child(_keys_box)
	_heading(_keys_box, "Keyboard")
	_note(_keys_box, "Click an action, then press the key you want for it.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_keys_box.add_child(grid)
	for action in GameManager.BINDABLE:
		var name_label := Label.new()
		name_label.text = GameManager.ACTION_NAMES[action]
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(name_label)
		var b := Button.new()
		b.custom_minimum_size = Vector2(WIDTH - 132.0, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_start_capture.bind(action))
		grid.add_child(b)
		_key_buttons[action] = b
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(func() -> void:
		Sfx.play("click")
		_capturing = ""
		GameManager.reset_keys()
		_refresh_keys())
	var reset_row := CenterContainer.new()
	reset_row.add_child(reset)
	_keys_box.add_child(reset_row)

	_touch_box = VBoxContainer.new()
	_touch_box.add_theme_constant_override("separation", 6)
	_controls_box.add_child(_touch_box)
	_heading(_touch_box, "Touch screen")
	_nudge_mode = _option(_touch_box, "Nudge", ["Swipe the screen", "Tilt the phone"], func(i: int) -> void:
		Sfx.play("click")
		GameManager.set_nudge_mode(NUDGE_MODES[i])
		if NUDGE_MODES[i] == "tilt":
			_request_motion_permission())
	_touch_mode = _option(_touch_box, "On-screen buttons", ["Automatic", "Always on", "Off"], func(i: int) -> void:
		Sfx.play("click")
		GameManager.set_touch_controls(TOUCH_MODES[i])
		_refresh_sections())

	_show_tab(false)


## Show the current values (without triggering sounds).
func refresh() -> void:
	_master.set_value_no_signal(Sfx.master_volume)
	_sfx.set_value_no_signal(Sfx.sfx_volume)
	_music.set_value_no_signal(Sfx.music_volume)
	_popups.set_pressed_no_signal(GameManager.show_score_popups)
	_nudge_mode.select(maxi(0, NUDGE_MODES.find(GameManager.nudge_mode)))
	_touch_mode.select(maxi(0, TOUCH_MODES.find(GameManager.touch_controls)))
	_capturing = ""
	_refresh_keys()
	_refresh_sections()


func focus_first() -> void:
	if _audio_box.visible:
		_master.grab_focus()
	else:
		_tab_controls.grab_focus()


# --- Tabs ---------------------------------------------------------------------------

func _show_tab(controls: bool) -> void:
	_audio_box.visible = not controls
	_controls_box.visible = controls
	_tab_audio.set_pressed_no_signal(not controls)
	_tab_controls.set_pressed_no_signal(controls)
	_capturing = ""
	_refresh_keys()


## Keyboard bindings unless this is a phone / tablet; touch options on touch screens.
func _refresh_sections() -> void:
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_keys_box.visible = not mobile
	_touch_box.visible = mobile or DisplayServer.is_touchscreen_available() or GameManager.touch_controls != "auto"


# --- Key binding --------------------------------------------------------------------

func _start_capture(action: String) -> void:
	Sfx.play("click")
	_capturing = action
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if _capturing == "" or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed:
		_capturing = "" # clicked elsewhere: cancel
		_refresh_keys.call_deferred()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled() # the key must not also pause / flip / close the menu
	var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code == KEY_ESCAPE and _capturing != "pause":
		_capturing = "" # Esc cancels (unless binding Pause itself)
	else:
		GameManager.bind_key(_capturing, code)
		Sfx.play("click")
		_capturing = ""
	_refresh_keys()


func _refresh_keys() -> void:
	for action in _key_buttons:
		var b: Button = _key_buttons[action]
		if action == _capturing:
			b.text = "Press a key... (Esc cancels)" if action != "pause" else "Press a key..."
			b.add_theme_color_override("font_color", GOLD)
		else:
			b.text = GameManager.key_label(action, "  ·  ")
			b.remove_theme_color_override("font_color")


# --- Builders -----------------------------------------------------------------------

func _section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(box)
	return box


func _tab_button(parent: Control, text: String, group: ButtonGroup, controls: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(140, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		_show_tab(controls))
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", GOLD)
	parent.add_child(label)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", SOFT)
	parent.add_child(label)


func _option(parent: Control, text: String, items: Array, on_selected: Callable) -> OptionButton:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.custom_minimum_size = Vector2(WIDTH, 40)
	option.add_theme_font_size_override("font_size", 18)
	option.item_selected.connect(on_selected)
	parent.add_child(option)
	return option


func _slider(parent: Control, text: String, on_changed: Callable) -> HSlider:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(WIDTH, 28)
	slider.value_changed.connect(on_changed)
	parent.add_child(slider)
	return slider


## iPhones only give motion data after the page asks during a tap. Godot handles
## input a moment after the tap, so we arm a one-time listener: the player's
## next tap shows the permission prompt. Other browsers ignore this.
func _request_motion_permission() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
		if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
			const ask = () => { DeviceMotionEvent.requestPermission().catch(() => {}); };
			document.addEventListener('touchend', ask, { once: true });
			document.addEventListener('click', ask, { once: true });
		}
	""", true)
