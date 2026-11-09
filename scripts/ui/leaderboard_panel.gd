class_name LeaderboardPanel
extends VBoxContainer
## All-time top 10 (online board, or this device's scores) from the Leaderboard
## autoload. Shared by the pause menu and the main menu. Call refresh() when shown.

var _grid: GridContainer
var _note: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.custom_minimum_size = Vector2(320, 0)
	add_child(_grid)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(320, 0)
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	add_child(RunIcon.legend())
	add_child(_note)


func refresh() -> void:
	_clear()
	_note.text = "Loading..."
	var res: Dictionary = await Leaderboard.fetch_top()
	if not is_visible_in_tree():
		return
	_clear()
	var entries: Array = res["entries"]
	for i in entries.size():
		var e: Dictionary = entries[i]
		var c := Color.WHITE if i < 3 else Color(0.75, 0.8, 0.95)
		_cell("%d." % (i + 1), c, HORIZONTAL_ALIGNMENT_RIGHT)
		_grid.add_child(RunIcon.name_cell(str(e["name"]), bool(e["won"]), c, 18))
		_cell(GameManager.format_number(float(e["score"])), c, HORIZONTAL_ALIGNMENT_RIGHT)
	var notes: Array[String] = []
	if entries.is_empty():
		notes.append("No scores yet.")
	notes.append("All-time, all players." if res["online"] else "This device only.")
	if res["error"] != "":
		notes.append(res["error"])
	_note.text = "\n".join(notes)


func _clear() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _cell(text: String, color: Color, align: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(label)
