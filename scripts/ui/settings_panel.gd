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


## Show the current values (without triggering sounds).
func refresh() -> void:
	_master.set_value_no_signal(Sfx.master_volume)
	_sfx.set_value_no_signal(Sfx.sfx_volume)
	_music.set_value_no_signal(Sfx.music_volume)
	_popups.set_pressed_no_signal(GameManager.show_score_popups)


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
