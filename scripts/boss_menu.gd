extends CanvasLayer
## Shown when the boss reaches 0 HP: Continue (new round, all progress kept,
## stronger boss) or End Run (victory screen + high-score entry).
## Pauses the game while open.

const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.78, 0.82, 0.95)

var _root: Control
var _title: Label
var _details: Label
var _continue_button: Button


func _ready() -> void:
	layer = 17 # above HUD/power-ups, below the end screen and pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	GameManager.boss_beaten.connect(func(info: Dictionary) -> void: _open.call_deferred(info))
	GameManager.game_started.connect(func() -> void: _root.visible = false)


func _open(info: Dictionary) -> void:
	GameManager.choosing = true # blocks the pause menu, restart key and power-up picker
	get_tree().paused = true
	var defeated := GameManager.bosses_defeated
	_title.text = "BOSS DEFEATED!" if defeated == 1 else "BOSS #%d DEFEATED!" % defeated
	_details.text = "Damage dealt  %s / %s HP  (x%.2f)\n\nContinue: keep your score, balls and power-ups.\nThe next boss has  %s HP.\n\nEnd Run: finish now and post your score." % [
		GameManager.format_number(float(info["total_damage"])),
		GameManager.format_number(float(info["max_hp"])),
		float(info["ratio"]),
		GameManager.format_number(float(info["next_max_hp"])),
	]
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)
	_continue_button.grab_focus()


func _close() -> void:
	_root.visible = false
	GameManager.choosing = false
	get_tree().paused = false


func _on_continue() -> void:
	Sfx.play("click")
	_close()
	GameManager.continue_run()


func _on_end_run() -> void:
	Sfx.play("click")
	_close()
	GameManager.declare_victory()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1: _on_continue()
		KEY_2: _on_end_run()
		_: return
	get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(420, 0)
	center.add_child(col)

	_title = _label(col, "", 40, GOLD)
	_details = _label(col, "", 17, SOFT)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	_continue_button = _button(row, "[1] Continue", _on_continue)
	_button(row, "[2] End Run", _on_end_run)


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


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
