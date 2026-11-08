class_name SettingsPanel
extends VBoxContainer
## Options: master / effects / music volume and the score popups toggle.
## Shared by the pause menu and the main menu. Changes apply immediately;
## call Sfx.save_settings() when leaving the page.

const WIDTH := 260.0

var _master: HSlider
var _sfx: HSlider
var _music: HSlider
var _popups: CheckButton


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_master = _slider("Master volume", func(v: float) -> void:
		Sfx.set_master_volume(v)
		Sfx.play("bumper", 0.0, 1.0, 120))
	_sfx = _slider("Effects volume", func(v: float) -> void:
		Sfx.set_sfx_volume(v)
		Sfx.play("bumper", 0.0, 1.0, 120))
	_music = _slider("Music volume", func(v: float) -> void: Sfx.set_music_volume(v))
	_popups = CheckButton.new()
	_popups.text = "Score popups"
	_popups.add_theme_font_size_override("font_size", 18)
	_popups.toggled.connect(func(on: bool) -> void:
		Sfx.play("click")
		GameManager.set_show_score_popups(on))
	add_child(_popups)

	# Controls (mostly for phones and tablets).
	var heading := Label.new()
	heading.text = "Controls"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	add_child(heading)
	_nudge_mode = _option("Nudge", ["Swipe the screen", "Tilt the phone"], func(i: int) -> void:
		Sfx.play("click")
		GameManager.set_nudge_mode(NUDGE_MODES[i])
		if NUDGE_MODES[i] == "tilt":
			_request_motion_permission())
	_touch_mode = _option("On-screen buttons", ["Automatic", "Always on", "Off"], func(i: int) -> void:
		Sfx.play("click")
		GameManager.set_touch_controls(TOUCH_MODES[i]))


const NUDGE_MODES: Array[String] = ["swipe", "tilt"]
const TOUCH_MODES: Array[String] = ["auto", "on", "off"]
var _nudge_mode: OptionButton
var _touch_mode: OptionButton


func _option(text: String, items: Array, on_selected: Callable) -> OptionButton:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.custom_minimum_size = Vector2(WIDTH, 40)
	option.add_theme_font_size_override("font_size", 18)
	option.item_selected.connect(on_selected)
	add_child(option)
	return option


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


## Show the current values (without triggering sounds).
func refresh() -> void:
	_master.set_value_no_signal(Sfx.master_volume)
	_sfx.set_value_no_signal(Sfx.sfx_volume)
	_music.set_value_no_signal(Sfx.music_volume)
	_popups.set_pressed_no_signal(GameManager.show_score_popups)
	_nudge_mode.select(maxi(0, NUDGE_MODES.find(GameManager.nudge_mode)))
	_touch_mode.select(maxi(0, TOUCH_MODES.find(GameManager.touch_controls)))


func focus_first() -> void:
	_master.grab_focus()


func _slider(text: String, on_changed: Callable) -> HSlider:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(WIDTH, 28)
	slider.value_changed.connect(on_changed)
	add_child(slider)
	return slider
