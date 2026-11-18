class_name LeaderboardPanel
extends VBoxContainer
## All-time top 10 (online board, or this device's scores) from the Leaderboard
## autoload. Shared by the pause menu and the main menu. Call refresh() when shown.

const GOLD := Color(1.0, 0.85, 0.3)

## Which board to show: "" = Endless, otherwise a story chapter id.
var board: String = ""
## Leaderboard.SORT_SCORE or SORT_TIME (story boards only).
var sort: String = Leaderboard.SORT_SCORE
var _grid: GridContainer
var _note: Label
var _sort_row: HBoxContainer
var _sort_buttons: Dictionary = {}
var _legend: Control
## Colors: light on the dark menu, or ink on the Story journal's paper.
var _top := Color.WHITE
var _rest := Color(0.75, 0.8, 0.95)
var _mine := GOLD
var _faint := Color(0.7, 0.75, 0.9)


func _init(paper: bool = false) -> void:
	if paper:
		_top = Color(0.17, 0.13, 0.1)
		_rest = Color(0.3, 0.24, 0.18)
		_mine = Color(0.5, 0.16, 0.1)
		_faint = Color(0.43, 0.36, 0.28)
	add_theme_constant_override("separation", 10)
	# Story boards: rank by highest score or by fastest win.
	_sort_row = HBoxContainer.new()
	_sort_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sort_row.add_theme_constant_override("separation", 8)
	add_child(_sort_row)
	var group := ButtonGroup.new()
	for item: Array in [[Leaderboard.SORT_SCORE, "High score"], [Leaderboard.SORT_TIME, "Fastest win"]]:
		var b := Button.new()
		b.text = item[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 34)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_pressed_color", _mine)
		if paper:
			_ink_button(b)
		var mode: String = item[0]
		b.pressed.connect(func() -> void:
			if sort != mode:
				Sfx.play("click")
				sort = mode
				refresh())
		_sort_row.add_child(b)
		_sort_buttons[mode] = b
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
	_note.add_theme_color_override("font_color", _faint)
	# The legend doubles as a filter: click a run ending to show only those runs.
	var on_filter := func(ending: String) -> void:
		_ending = ending
		refresh()
	_legend = RunIcon.legend(on_filter, _faint, _mine, Color(_mine, 0.7)) if paper else RunIcon.legend(on_filter)
	add_child(_legend)
	add_child(_note)


## "" = all runs, "won" = ended after a boss, "lost" = out of balls.
var _ending: String = ""
## Bumped on every refresh, so an older, slower request can't add rows.
var _generation: int = 0
## A run not posted yet, shown in gold where it would land while its name is
## being typed (as in Endless): {score, won, time}. Empty = none.
var pending: Dictionary = {}
## The name being typed for the pending run (updated live, no reload).
var pending_name: String = "":
	set(value):
		pending_name = value
		if is_instance_valid(_pending_label):
			_pending_label.text = _pending_text()
var _pending_label: Label = null


func refresh() -> void:
	_generation += 1
	var gen := _generation
	_clear()
	if board == "":
		sort = Leaderboard.SORT_SCORE # times are kept on story boards only
	var by_time := sort == Leaderboard.SORT_TIME
	_sort_row.visible = board != ""
	(_sort_buttons[sort] as Button).button_pressed = true
	_legend.visible = not by_time # every run on the time board is a win
	_note.text = "Loading..."
	var res: Dictionary = await Leaderboard.fetch_top(_ending, board, sort)
	if not is_visible_in_tree() or gen != _generation:
		return
	_clear()
	var entries: Array = res["entries"]
	var me := Leaderboard.last_name # this device's player
	var me_shown := false
	_pending_label = null
	# Where the pending run would land (after equal scores / times, which keep
	# the older run first). Beyond the top 10 it goes below, with its rank.
	var pend_at := -1
	if _pending_fits(by_time):
		pend_at = 0
		for e: Dictionary in entries:
			if (float(e.get("time", INF)) <= float(pending["time"])) if by_time else (float(e["score"]) >= float(pending["score"])):
				pend_at += 1
	var rank := 0
	for i in entries.size():
		if i == pend_at:
			rank += 1
			_pending_row(rank)
		if rank >= Leaderboard.TOP_COUNT:
			break # the pending run pushed the last one off the top 10
		var e: Dictionary = entries[i]
		rank += 1
		var c := _top if rank <= 3 else _rest
		if not me_shown and me != "" and e["name"] == me and pending.is_empty():
			c = _mine # the player's best score is in the top 10
			me_shown = true
		_cell("%d." % rank, c, HORIZONTAL_ALIGNMENT_RIGHT)
		_grid.add_child(RunIcon.name_cell(str(e["name"]), bool(e["won"]), c, 18))
		_cell(_value_text(e), c, HORIZONTAL_ALIGNMENT_RIGHT)
	if pend_at == entries.size() and pend_at < Leaderboard.TOP_COUNT:
		_pending_row(pend_at + 1)
	elif pend_at >= Leaderboard.TOP_COUNT:
		var far := 0
		if by_time:
			far = await Leaderboard.fetch_time_rank(float(pending["time"]), board)
		else:
			far = await Leaderboard.fetch_rank(float(pending["score"]), _ending, true, board)
		if not is_visible_in_tree() or gen != _generation:
			return
		_cell("", _mine, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell("···", _faint, HORIZONTAL_ALIGNMENT_LEFT)
		_cell("", _mine, HORIZONTAL_ALIGNMENT_RIGHT)
		_pending_row(maxi(far, Leaderboard.TOP_COUNT + 1))
	var notes: Array[String] = []
	if entries.is_empty():
		if by_time:
			notes.append("No timed wins yet.")
		else:
			notes.append("No scores yet." if _ending == "" else "No runs like that yet.")
	var scope := "All-time, all players" if res["online"] else "This device only"
	if by_time:
		scope += " · fastest wins"
	else:
		match _ending:
			"won":
				scope += " · only runs that ended after a boss"
			"lost":
				scope += " · only runs that ran out of balls"
	notes.append(scope + ".")
	if res["error"] != "":
		notes.append(res["error"])
	_note.text = "\n".join(notes)
	if me != "" and not me_shown and not entries.is_empty() and pending.is_empty():
		await _add_player_row(me, entries.size(), gen)


## Below the top 10: "···" and the player's best score with its position
## (within the current filter).
func _add_player_row(player_name: String, shown: int, gen: int) -> void:
	var best: Dictionary = await Leaderboard.fetch_player_best(player_name, _ending, board, sort)
	if not is_visible_in_tree() or gen != _generation or not best["found"] or int(best["rank"]) <= shown:
		return
	_cell("", _mine, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell("···", _faint, HORIZONTAL_ALIGNMENT_LEFT)
	_cell("", _mine, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell("%d." % int(best["rank"]), _mine, HORIZONTAL_ALIGNMENT_RIGHT)
	_grid.add_child(RunIcon.name_cell(player_name, bool(best["won"]), _mine, 18))
	_cell(_value_text(best), _mine, HORIZONTAL_ALIGNMENT_RIGHT)


func _pending_fits(by_time: bool) -> bool:
	if pending.is_empty():
		return false
	if by_time:
		return bool(pending.get("won", false)) and float(pending.get("time", 0.0)) > 0.0
	return _ending == "" or (_ending == "won") == bool(pending.get("won", false))


func _pending_text() -> String:
	return pending_name if pending_name != "" else "?????"


## The run being named: in gold, its name following the typing.
func _pending_row(rank: int) -> void:
	_cell("%d." % rank, _mine, HORIZONTAL_ALIGNMENT_RIGHT)
	var cell := RunIcon.name_cell(_pending_text(), bool(pending.get("won", false)), _mine, 18)
	_pending_label = cell.get_child(0) as Label
	_grid.add_child(cell)
	var shown := {"score": pending["score"], "time": pending.get("time", 0.0)}
	_cell(_value_text(shown), _mine, HORIZONTAL_ALIGNMENT_RIGHT)


## The number shown for a row: the score, or the run time on the time board.
func _value_text(e: Dictionary) -> String:
	if sort == Leaderboard.SORT_TIME:
		return Story.clock(float(e.get("time", 0.0)))
	return GameManager.format_number(float(e["score"]))


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


## A flat toggle with ink text, for the paper version.
func _ink_button(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(_top, 0.0 if state == "normal" or state == "focus" else 0.07)
		box.border_color = Color(_mine, 0.8) if state.contains("pressed") else Color(_top, 0.0 if state == "normal" else 0.3)
		box.set_border_width_all(2 if state.contains("pressed") else 1)
		box.set_corner_radius_all(6)
		if state == "focus":
			box.draw_center = false
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", _rest)
	b.add_theme_color_override("font_hover_color", _top)
	b.add_theme_color_override("font_hover_pressed_color", _mine)
