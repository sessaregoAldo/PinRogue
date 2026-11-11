class_name FeedbackPanel
extends VBoxContainer
## Bug report / suggestion form. Shared by the pause menu and the main menu.
## Sends to the online "feedback" table (see Leaderboard.submit_feedback and
## supabase/feedback.sql) along with the game version, machine, round, score
## and platform. Players can only send; the developer reads the reports in
## the PIN-locked viewer (FeedbackViewer) or Supabase > Table Editor > feedback.

const MAX_CHARS := 500
const MIN_CHARS := 3
const NAME_MAX := 30
const COOLDOWN := 30.0
const WIDTH := 400.0

static var _last_sent_ms: int = -1000000 # shared by every form, for the cooldown

var _bug_button: Button
var _idea_button: Button
var _message: TextEdit
var _count: Label
var _name: LineEdit
var _send: Button
var _status: Label
var _sending: bool = false


func _init() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0)
	var kinds := HBoxContainer.new()
	kinds.alignment = BoxContainer.ALIGNMENT_CENTER
	kinds.add_theme_constant_override("separation", 8)
	add_child(kinds)
	var group := ButtonGroup.new()
	_bug_button = _kind_button(kinds, "Bug", group)
	_idea_button = _kind_button(kinds, "Suggestion", group)
	_bug_button.button_pressed = true

	_message = TextEdit.new()
	_message.placeholder_text = "What happened, or what would you like to see?"
	_message.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message.custom_minimum_size = Vector2(WIDTH, 170)
	_message.add_theme_font_size_override("font_size", 17)
	_message.text_changed.connect(_on_text_changed)
	add_child(_message)
	_count = _small_label("0 / %d" % MAX_CHARS)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_name = LineEdit.new()
	_name.placeholder_text = "Your name (optional)"
	_name.max_length = NAME_MAX
	_name.custom_minimum_size = Vector2(WIDTH, 40)
	_name.add_theme_font_size_override("font_size", 17)
	add_child(_name)

	_send = Button.new()
	_send.text = "Send"
	_send.custom_minimum_size = Vector2(200, 46)
	_send.add_theme_font_size_override("font_size", 20)
	_send.pressed.connect(_on_send)
	var row := CenterContainer.new()
	row.add_child(_send)
	add_child(row)
	_status = _small_label("")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH, 0)


## Call when the page is shown. Keeps an unsent draft.
func refresh() -> void:
	if _name.text == "" and Leaderboard.last_name != "":
		_name.text = Leaderboard.last_name
	if not _sending:
		_status.text = "Reports include the game version, machine, round, score and device type."
		_status.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	_on_text_changed()


func focus_first() -> void:
	_message.grab_focus()


func _process(_delta: float) -> void:
	# The phone keyboard can change the text without a signal: keep the counter right.
	if is_visible_in_tree():
		_on_text_changed()


func _on_text_changed() -> void:
	if _message.text.length() > MAX_CHARS:
		var caret := _message.get_caret_column()
		_message.text = _message.text.left(MAX_CHARS)
		_message.set_caret_column(mini(caret, MAX_CHARS))
	_count.text = "%d / %d" % [_message.text.length(), MAX_CHARS]
	_send.disabled = _sending


func _on_send() -> void:
	var text := _message.text.strip_edges()
	if text.length() < MIN_CHARS:
		_show_status("Please write a few words first.", Color(1.0, 0.85, 0.3))
		return
	var wait := COOLDOWN - (Time.get_ticks_msec() - _last_sent_ms) / 1000.0
	if wait > 0.0:
		_show_status("Thanks! You can send another one in %d s." % ceili(wait), Color(1.0, 0.85, 0.3))
		return
	_sending = true
	_send.disabled = true
	_show_status("Sending...", Color(0.75, 0.8, 0.95))
	Sfx.play("click")
	var res: Dictionary = await Leaderboard.submit_feedback({
		"kind": "bug" if _bug_button.button_pressed else "suggestion",
		"message": text,
		"name": _name.text.strip_edges().left(NAME_MAX),
	}.merged(_context()))
	_sending = false
	_send.disabled = false
	if res["ok"]:
		_last_sent_ms = Time.get_ticks_msec()
		_message.text = ""
		_on_text_changed()
		_show_status("Thanks! Sent.", Color(0.5, 1.0, 0.6))
		Sfx.play("ramp_complete")
	else:
		_show_status("Couldn't send it (%s). Your text is kept, so you can try again." % res["error"], Color(1.0, 0.5, 0.45))


## Where the player is: attached to every report.
func _context() -> Dictionary:
	var machine := "main menu"
	var scene := get_tree().current_scene
	if scene and "level" in scene and scene.level != null:
		machine = str(scene.level.level_name)
	var platform := "web" if OS.has_feature("web") else OS.get_name()
	for tag in ["web_android", "web_ios", "web_windows", "web_macos", "web_linuxbsd"]:
		if OS.has_feature(tag):
			platform = tag
	if DisplayServer.is_touchscreen_available():
		platform += " (touch)"
	return {
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"machine": machine,
		"boss_round": GameManager.boss_round if machine != "main menu" else 0,
		"score": GameManager.score if machine != "main menu" else 0.0,
		"platform": platform,
	}


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _kind_button(parent: Control, text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.3))
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	add_child(label)
	return label
