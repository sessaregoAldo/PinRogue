class_name FeedbackViewer
extends VBoxContainer
## Developer-only list of bug reports and suggestions (main menu > Feedback >
## View reports). Opens with a PIN that the server checks (see
## Leaderboard.fetch_feedback and supabase/feedback_admin.sql): the game itself
## doesn't know the PIN. Three views: PIN pad -> list -> one report.

const WIDTH := 480.0
const PIN_LENGTH := 6
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)
const DIM := Color(0.6, 0.65, 0.8)
const BAD := Color(1.0, 0.5, 0.45)
const GOOD := Color(0.5, 1.0, 0.6)
const BUG_COLOR := Color(1.0, 0.45, 0.4)
const IDEA_COLOR := Color(0.4, 0.85, 1.0)
const CONFIRM_TIME := 3.0
## Characters of the message shown in the list (about two lines).
const PREVIEW_CHARS := 90

var _pin: String = ""
var _busy: bool = false
var _entries: Array = []
var _open_entry: Dictionary = {}

var _pin_view: VBoxContainer
var _pin_dots: Label
var _pin_status: Label
var _list_view: VBoxContainer
var _list_box: VBoxContainer
var _list_scroll: ScrollContainer
var _list_status: Label
var _detail_view: VBoxContainer
var _detail_box: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0)
	_build_pin_view()
	_build_list_view()
	_build_detail_view()


## Call when the page is shown: always starts locked.
func open() -> void:
	_pin = ""
	_entries = []
	_open_entry = {}
	_busy = false
	_show(_pin_view)
	_update_dots()
	_set_status(_pin_status, "Developer access only.", DIM)


## Back inside the viewer (report -> list). False when the page should close.
func back() -> bool:
	if _detail_view.visible:
		_show(_list_view)
		return true
	return false


func _show(view: Control) -> void:
	_pin_view.visible = view == _pin_view
	_list_view.visible = view == _list_view
	_detail_view.visible = view == _detail_view


func _input(event: InputEvent) -> void:
	# Number keys on the PIN pad.
	if not (is_visible_in_tree() and _pin_view.visible) or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.keycode
	if code >= KEY_0 and code <= KEY_9:
		_press_digit(str(code - KEY_0))
	elif code >= KEY_KP_0 and code <= KEY_KP_9:
		_press_digit(str(code - KEY_KP_0))
	elif code == KEY_BACKSPACE:
		_press_erase()
	else:
		return
	get_viewport().set_input_as_handled()


# --- PIN pad ------------------------------------------------------------------------

func _build_pin_view() -> void:
	_pin_view = VBoxContainer.new()
	_pin_view.add_theme_constant_override("separation", 14)
	add_child(_pin_view)
	_pin_view.add_child(_label("Enter PIN", 22, SOFT, true))
	_pin_dots = _label("", 34, GOLD, true)
	_pin_view.add_child(_pin_dots)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.add_child(grid)
	_pin_view.add_child(center)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "<"]:
		var b := Button.new()
		b.text = {"C": "Clear", "<": "Del"}.get(key, key)
		b.custom_minimum_size = Vector2(96, 64)
		b.add_theme_font_size_override("font_size", 26 if key.is_valid_int() else 18)
		b.focus_mode = Control.FOCUS_NONE
		match key:
			"C":
				b.pressed.connect(_press_clear)
			"<":
				b.pressed.connect(_press_erase)
			_:
				b.pressed.connect(_press_digit.bind(key))
		grid.add_child(b)
	_pin_status = _label("", 15, DIM, true)
	_pin_view.add_child(_pin_status)


func _press_digit(digit: String) -> void:
	if _busy or _pin.length() >= PIN_LENGTH:
		return
	Sfx.play("click")
	_pin += digit
	_update_dots()
	if _pin.length() == PIN_LENGTH:
		_unlock()


func _press_erase() -> void:
	if _busy or _pin == "":
		return
	Sfx.play("click")
	_pin = _pin.left(_pin.length() - 1)
	_update_dots()


func _press_clear() -> void:
	if _busy:
		return
	Sfx.play("click")
	_pin = ""
	_update_dots()


func _update_dots() -> void:
	var dots := PackedStringArray()
	for i in PIN_LENGTH:
		dots.append("●" if i < _pin.length() else "○")
	_pin_dots.text = " ".join(dots)


func _unlock() -> void:
	_busy = true
	_set_status(_pin_status, "Checking...", SOFT)
	var res: Dictionary = await Leaderboard.fetch_feedback(_pin)
	_busy = false
	if not is_inside_tree() or not _pin_view.visible:
		return
	if not res["ok"]:
		_pin = ""
		_update_dots()
		_set_status(_pin_status, "Refused: %s." % res["error"], BAD)
		Sfx.play("warning")
		return
	Sfx.play("ramp_complete")
	_entries = res["entries"]
	_show(_list_view)
	_fill_list()


# --- List ---------------------------------------------------------------------------

func _build_list_view() -> void:
	_list_view = VBoxContainer.new()
	_list_view.add_theme_constant_override("separation", 8)
	add_child(_list_view)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_list_view.add_child(top)
	_list_status = _label("", 15, DIM, false)
	_list_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_list_status)
	var refresh := _small_button("Refresh", 15)
	refresh.custom_minimum_size = Vector2(100, 36)
	refresh.pressed.connect(_refresh)
	top.add_child(refresh)
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(WIDTH, 640)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_view.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 8)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list_box)


func _refresh() -> void:
	if _busy:
		return
	Sfx.play("click")
	_busy = true
	_set_status(_list_status, "Loading...", SOFT)
	var res: Dictionary = await Leaderboard.fetch_feedback(_pin)
	_busy = false
	if not is_inside_tree():
		return
	if not res["ok"]:
		_set_status(_list_status, "Couldn't load (%s)." % res["error"], BAD)
		return
	_entries = res["entries"]
	_fill_list()


func _fill_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	_list_scroll.scroll_vertical = 0
	_update_count()
	if _entries.is_empty():
		_list_box.add_child(_label("Nothing here. All caught up!", 18, SOFT, true))
		return
	for entry: Dictionary in _entries:
		_list_box.add_child(_entry_card(entry))


func _update_count() -> void:
	var bugs := 0
	for e: Dictionary in _entries:
		if str(e.get("kind", "")) == "bug":
			bugs += 1
	_set_status(_list_status, "%d report%s  ·  %d bug%s, %d suggestion%s" % [
			_entries.size(), "" if _entries.size() == 1 else "s",
			bugs, "" if bugs == 1 else "s",
			_entries.size() - bugs, "" if _entries.size() - bugs == 1 else "s"], DIM)


func _entry_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(_kind_color(entry)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_header_row(entry))
	var text := str(entry.get("message", "")).replace("\n", " ").strip_edges()
	if text.length() > PREVIEW_CHARS:
		text = text.left(PREVIEW_CHARS).strip_edges() + "…"
	var preview := _label(text, 16, Color.WHITE, false)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(WIDTH - 40, 0)
	box.add_child(preview)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var open_button := _small_button("Open", 15)
	open_button.pressed.connect(_open.bind(entry))
	buttons.add_child(open_button)
	var delete_button := _small_button("Delete", 15)
	delete_button.pressed.connect(_delete.bind(entry, delete_button))
	buttons.add_child(delete_button)
	return card


## Kind tag, name and date on one line.
func _header_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var is_bug := str(entry.get("kind", "")) == "bug"
	row.add_child(_label("BUG" if is_bug else "IDEA", 14, _kind_color(entry), false))
	var who := str(entry.get("name", "")).strip_edges()
	var name_label := _label(who if who != "" else "(no name)", 16, SOFT if who != "" else DIM, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(_label(_date_text(entry), 14, DIM, false))
	return row


# --- One report ---------------------------------------------------------------------

func _build_detail_view() -> void:
	_detail_view = VBoxContainer.new()
	_detail_view.add_theme_constant_override("separation", 10)
	add_child(_detail_view)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_view.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 10)
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_box)


func _open(entry: Dictionary) -> void:
	Sfx.play("click")
	_open_entry = entry
	for child in _detail_box.get_children():
		child.queue_free()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(_kind_color(entry)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	_detail_box.add_child(card)
	box.add_child(_header_row(entry))
	var message := _label(str(entry.get("message", "")), 18, Color.WHITE, false)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(WIDTH - 40, 0)
	box.add_child(message)
	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 14)
	info.add_theme_constant_override("v_separation", 4)
	box.add_child(info)
	var score: Variant = entry.get("score")
	for pair in [
			["Status", str(entry.get("status", "new")).replace("_", " ")],
			["Sent", _date_text(entry, true)],
			["Version", _text_or_dash(entry.get("version"))],
			["Machine", _text_or_dash(entry.get("machine"))],
			["Round", _text_or_dash(entry.get("boss_round"))],
			["Score", GameManager.format_number(float(score)) if score != null else "-"],
			["Device", _text_or_dash(entry.get("platform"))],
			["Report #", _text_or_dash(entry.get("id"))]]:
		info.add_child(_label(pair[0], 15, DIM, false))
		var value := _label(pair[1], 15, SOFT, false)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(WIDTH - 160, 0)
		info.add_child(value)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_detail_box.add_child(buttons)
	var list_button := _small_button("Back to list", 17)
	list_button.custom_minimum_size = Vector2(150, 44)
	list_button.pressed.connect(func() -> void:
		Sfx.play("click")
		_show(_list_view))
	buttons.add_child(list_button)
	var delete_button := _small_button("Delete", 17)
	delete_button.custom_minimum_size = Vector2(150, 44)
	delete_button.pressed.connect(_delete.bind(entry, delete_button))
	buttons.add_child(delete_button)
	_show(_detail_view)


# --- Delete -------------------------------------------------------------------------

## First press asks to confirm (for a few seconds), the second deletes for good.
func _delete(entry: Dictionary, button: Button) -> void:
	if _busy:
		return
	Sfx.play("click")
	if not button.has_meta("armed"):
		button.set_meta("armed", true)
		button.text = "Sure?"
		button.add_theme_color_override("font_color", BAD)
		button.add_theme_color_override("font_hover_color", BAD)
		get_tree().create_timer(CONFIRM_TIME, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(button) and button.has_meta("armed") and not _busy:
				button.remove_meta("armed")
				button.text = "Delete"
				button.remove_theme_color_override("font_color")
				button.remove_theme_color_override("font_hover_color"))
		return
	_busy = true
	button.text = "..."
	var res: Dictionary = await Leaderboard.delete_feedback(_pin, int(entry.get("id", -1)))
	_busy = false
	if not is_inside_tree():
		return
	if is_instance_valid(button):
		button.remove_meta("armed")
		button.text = "Delete"
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
	if not res["ok"]:
		_show(_list_view)
		_set_status(_list_status, "Couldn't delete (%s)." % res["error"], BAD)
		return
	_entries.erase(entry)
	var was_open := _detail_view.visible
	_fill_list()
	if was_open:
		_show(_list_view)
	_set_status(_list_status, "Deleted.  " + _list_status.text, GOOD)
	Sfx.play("ramp_complete")


# --- Helpers ------------------------------------------------------------------------

func _kind_color(entry: Dictionary) -> Color:
	return BUG_COLOR if str(entry.get("kind", "")) == "bug" else IDEA_COLOR


## Local date and time the report was sent: "2026-11-11 14:05" (long adds seconds).
func _date_text(entry: Dictionary, long: bool = false) -> String:
	var unix: Variant = entry.get("created_unix")
	if unix == null:
		return "?"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(float(unix)) + bias * 60)
	var text := "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
	if long:
		text += ":%02d" % d["second"]
	return text


func _text_or_dash(value: Variant) -> String:
	if value == null or str(value).strip_edges() == "":
		return "-"
	if value is float and is_equal_approx(value, roundf(value)):
		return str(int(value))
	return str(value)


func _card_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.16, 0.92)
	style.border_color = Color(accent, 0.55)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _label(text: String, font_size: int, color: Color, centered: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH, 0)
	return label


func _small_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(90, 36)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _set_status(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
