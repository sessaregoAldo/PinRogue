extends CanvasLayer
## Game over / victory screen with high-score entry and the all-time top 10.
## Names are 2-5 letters (A-Z). See leaderboard.gd for where scores go.

const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)

var _final_score: float = 0.0
var _won: bool = false
var _submitted_name: String = ""

var _root: Control
var _title: Label
var _subtitle: Label
var _score_label: Label
var _entry_row: HBoxContainer
var _name_edit: LineEdit
var _submit_button: Button
var _skip_button: Button
var _status: Label
var _board: GridContainer
var _board_title: Label
var _footer: Label


func _ready() -> void:
	layer = 18 # above HUD and power-ups, below the pause menu
	_build()
	_root.visible = false
	GameManager.game_over.connect(func(score: float) -> void: _open(score, false))
	GameManager.victory.connect(func(score: float) -> void: _open(score, true))
	GameManager.game_started.connect(_close)


func _open(score: float, won: bool) -> void:
	_final_score = score
	_won = won # star: the run ended by choosing End Run after a boss; skull: out of balls
	_submitted_name = ""
	_title.text = "VICTORY!" if won else "GAME OVER"
	_title.add_theme_color_override("font_color", GOLD if won else Color.WHITE)
	var beaten := GameManager.bosses_defeated
	_subtitle.text = "" if beaten == 0 else ("1 boss defeated" if beaten == 1 else "%d bosses defeated" % beaten)
	_subtitle.visible = beaten > 0
	_score_label.text = "Score  %s" % GameManager.format_number(score)
	var can_submit := score > 0
	_entry_row.visible = can_submit
	_name_edit.editable = true
	_name_edit.text = Leaderboard.last_name
	_update_submit_state()
	_skip_button.disabled = false
	_status.text = "Enter a name (2-5 letters) for the all-time board." if can_submit else ""
	_status.modulate = SOFT
	_footer.text = "Press R or Play again" if not can_submit else "Enter submits  ·  Skip to play again"
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.5)
	GameManager.entering_name = can_submit
	if can_submit:
		_name_edit.grab_focus.call_deferred()
		_name_edit.caret_column = _name_edit.text.length()
	_load_board(-1)


func _close() -> void:
	_root.visible = false
	GameManager.entering_name = false


# --- Name entry -------------------------------------------------------------------

func _on_name_changed(text: String) -> void:
	var cleaned := Leaderboard.clean_name(text)
	if cleaned != text:
		var caret := _name_edit.caret_column
		_name_edit.text = cleaned
		_name_edit.caret_column = mini(caret, cleaned.length())
	_update_submit_state()


## Phones type through the browser's on-screen keyboard, which can change the
## text without a text_changed signal (and leave it lower-case). So the button
## state is also polled, and the name is cleaned again on submit.
func _update_submit_state() -> void:
	_submit_button.disabled = not Leaderboard.is_valid_name(Leaderboard.clean_name(_name_edit.text)) \
			or not _name_edit.editable


func _process(_delta: float) -> void:
	if _root.visible and _entry_row.visible:
		_update_submit_state()


func _on_submit(_text: String = "") -> void:
	var player_name := Leaderboard.clean_name(_name_edit.text)
	if not Leaderboard.is_valid_name(player_name) or not _name_edit.editable:
		_status.text = Leaderboard.name_rule()
		_status.modulate = GOLD
		return
	_name_edit.editable = false
	_submit_button.disabled = true
	_skip_button.disabled = true
	_status.text = "Submitting..."
	_status.modulate = SOFT
	Sfx.play("click")
	var res: Dictionary = await Leaderboard.submit(player_name, _final_score, _won)
	_submitted_name = player_name
	_finish_entry()
	if res["error"] != "":
		_status.text = res["error"]
		_status.modulate = GOLD
	else:
		_status.text = "Saved!" + ("" if res["online"] else "  (this device only: online board not set up)")
		_status.modulate = Color(0.5, 1.0, 0.6)
		Sfx.play("ramp_complete")
	var rank: int = await Leaderboard.fetch_rank(_final_score)
	_load_board(rank)


func _on_skip() -> void:
	Sfx.play("click")
	_finish_entry()
	_status.text = ""
	_load_board(-1)


func _finish_entry() -> void:
	_name_edit.release_focus()
	_entry_row.visible = false
	GameManager.entering_name = false
	_footer.text = "Press R or Play again"


func _on_main_menu() -> void:
	Sfx.play("click")
	_finish_entry()
	var game := get_parent()
	if game and game.has_method("go_to_main_menu"):
		game.go_to_main_menu()


func _on_play_again() -> void:
	Sfx.play("click")
	_finish_entry()
	GameManager.restart()


# --- Board ------------------------------------------------------------------------

func _load_board(rank: int) -> void:
	_board_title.text = "ALL-TIME TOP %d" % Leaderboard.TOP_COUNT
	_set_board_message("Loading...")
	var res: Dictionary = await Leaderboard.fetch_top()
	if not _root.visible:
		return
	if not res["online"]:
		_board_title.text = "TOP %d  (this device)" % Leaderboard.TOP_COUNT
	var entries: Array = res["entries"]
	for child in _board.get_children():
		child.queue_free()
	if entries.is_empty():
		_set_board_message("No scores yet. Be the first!")
	var highlighted := false
	for i in entries.size():
		var e: Dictionary = entries[i]
		var mine: bool = not highlighted and _submitted_name != "" and e["name"] == _submitted_name and Leaderboard.same_score(float(e["score"]), _final_score)
		if mine:
			highlighted = true
		var c := GOLD if mine else (Color.WHITE if i < 3 else SOFT)
		_cell("%d." % (i + 1), c, HORIZONTAL_ALIGNMENT_RIGHT)
		_board.add_child(RunIcon.name_cell(str(e["name"]), bool(e["won"]), c, 18))
		_cell(GameManager.format_number(float(e["score"])), c, HORIZONTAL_ALIGNMENT_RIGHT)
	if res["error"] != "" and _status.text == "":
		_status.text = res["error"]
		_status.modulate = GOLD
	if _submitted_name != "" and not highlighted and rank > 0:
		_status.text += ("\n" if _status.text != "" else "") + "You placed #%d all-time." % rank


func _set_board_message(text: String) -> void:
	for child in _board.get_children():
		child.queue_free()
	_cell("", SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	_cell(text, SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	_cell("", SOFT, HORIZONTAL_ALIGNMENT_LEFT)


func _cell(text: String, color: Color, align: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_child(label)


# --- UI ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(380, 0)
	center.add_child(col)

	_title = _label(col, "", 54, Color.WHITE)
	_subtitle = _label(col, "", 18, SOFT)
	_score_label = _label(col, "", 30, Color.WHITE)

	_entry_row = HBoxContainer.new()
	_entry_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_entry_row.add_theme_constant_override("separation", 8)
	col.add_child(_entry_row)
	_name_edit = LineEdit.new()
	# No max_length: clean_name() trims to 5 letters max, so pasting "zz9top" gives "ZZTOP".
	_name_edit.placeholder_text = "NAME"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(150, 44)
	_name_edit.add_theme_font_size_override("font_size", 26)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_submit)
	_entry_row.add_child(_name_edit)
	_submit_button = _button(_entry_row, "Submit", func() -> void: _on_submit())
	_skip_button = _button(_entry_row, "Skip", _on_skip)

	_status = _label(col, "", 15, SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_board_title = _label(col, "", 20, GOLD)
	_board = GridContainer.new()
	_board.columns = 3
	_board.add_theme_constant_override("h_separation", 18)
	_board.add_theme_constant_override("v_separation", 4)
	col.add_child(_board)

	col.add_child(RunIcon.legend())

	var again_row := HBoxContainer.new()
	again_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(again_row)
	_button(again_row, "Play again", _on_play_again)
	_button(again_row, "Main Menu", _on_main_menu)
	again_row.add_theme_constant_override("separation", 12)
	_footer = _label(col, "", 14, SOFT)


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
	b.custom_minimum_size = Vector2(96, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b
