class_name LeaderboardPanel
extends VBoxContainer
## All-time top 10 (online board, or this device's scores) from the Leaderboard
## autoload. Shared by the pause menu and the main menu. Call refresh() when shown.

const GOLD := Color(1.0, 0.85, 0.3)

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
	# The legend doubles as a filter: click a run ending to show only those runs.
	add_child(RunIcon.legend(func(ending: String) -> void:
		_ending = ending
		refresh()))
	add_child(_note)


## "" = all runs, "won" = ended after a boss, "lost" = out of balls.
var _ending: String = ""
## Bumped on every refresh, so an older, slower request can't add rows.
var _generation: int = 0


func refresh() -> void:
	_generation += 1
	var gen := _generation
	_clear()
	_note.text = "Loading..."
	var res: Dictionary = await Leaderboard.fetch_top(_ending)
	if not is_visible_in_tree() or gen != _generation:
		return
	_clear()
	var entries: Array = res["entries"]
	var me := Leaderboard.last_name # this device's player
	var me_shown := false
	for i in entries.size():
		var e: Dictionary = entries[i]
		var c := Color.WHITE if i < 3 else Color(0.75, 0.8, 0.95)
		if not me_shown and me != "" and e["name"] == me:
			c = GOLD # the player's best score is in the top 10
			me_shown = true
		_cell("%d." % (i + 1), c, HORIZONTAL_ALIGNMENT_RIGHT)
		_grid.add_child(RunIcon.name_cell(str(e["name"]), bool(e["won"]), c, 18))
		_cell(GameManager.format_number(float(e["score"])), c, HORIZONTAL_ALIGNMENT_RIGHT)
	var notes: Array[String] = []
	if entries.is_empty():
		notes.append("No scores yet." if _ending == "" else "No runs like that yet.")
	var scope := "All-time, all players" if res["online"] else "This device only"
	match _ending:
		"won":
			scope += " · only runs that ended after a boss"
		"lost":
			scope += " · only runs that ran out of balls"
	notes.append(scope + ".")
	if res["error"] != "":
		notes.append(res["error"])
	_note.text = "\n".join(notes)
	if me != "" and not me_shown and not entries.is_empty():
		await _add_player_row(me, entries.size(), gen)


## Below the top 10: "···" and the player's best score with its position
## (within the current filter).
func _add_player_row(player_name: String, shown: int, gen: int) -> void:
	var best: Dictionary = await Leaderboard.fetch_player_best(player_name, _ending)
	if not is_visible_in_tree() or gen != _generation or not best["found"] or int(best["rank"]) <= shown:
		return
	_cell("", GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell("···", Color(0.6, 0.65, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	_cell("", GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell("%d." % int(best["rank"]), GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_grid.add_child(RunIcon.name_cell(player_name, bool(best["won"]), GOLD, 18))
	_cell(GameManager.format_number(float(best["score"])), GOLD, HORIZONTAL_ALIGNMENT_RIGHT)


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
