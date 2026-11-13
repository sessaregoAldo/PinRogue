class_name StoryResult
extends CanvasLayer
## The Journal's result page at the end of a story run: Victory (the boss's
## story, the machine's change) or Defeat, with the coins earned, the strange
## coin that fell out, and the run's statistics.
## Victory offers Continue (to the Story menu); defeat offers Try again too.

signal retry_pressed
signal menu_pressed

const WIDTH := 500.0

var _root: Control
var _page: VBoxContainer
var _buttons: HBoxContainer
var _scroll: ScrollContainer
var _voice: AudioStreamPlayer
## Voice-over ids still to play, one after another (the ghost's closing lines).
var _voice_queue: Array[String] = []
# Posting the run to the chapter's leaderboard (Leaderboard, board = chapter id).
var _entry_row: HBoxContainer
var _name_edit: LineEdit
var _post_button: Button
var _post_status: Label
var _board: String = ""
var _score: float = 0.0
var _won: bool = false
var _posted: bool = false


func _ready() -> void:
	layer = 19 # above everything in the game except the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voice = StoryVoice.make_player()
	add_child(_voice)
	_voice.finished.connect(_speak_next)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", JournalPanel.paper_style())
	col.add_child(paper)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH - 40.0, 730)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 9)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page)
	_entry_row = HBoxContainer.new()
	_entry_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_entry_row.add_theme_constant_override("separation", 8)
	col.add_child(_entry_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "NAME"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(140, 44)
	_name_edit.add_theme_font_size_override("font_size", 24)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _post())
	_entry_row.add_child(_name_edit)
	_post_button = Button.new()
	_post_button.text = "Post score"
	_post_button.custom_minimum_size = Vector2(150, 44)
	_post_button.add_theme_font_size_override("font_size", 18)
	_post_button.pressed.connect(_post)
	_entry_row.add_child(_post_button)
	_post_status = Label.new()
	_post_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_post_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_post_status.custom_minimum_size = Vector2(WIDTH, 0)
	_post_status.add_theme_font_size_override("font_size", 15)
	_post_status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
	col.add_child(_post_status)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	col.add_child(_buttons)


# --- Chapter leaderboard ------------------------------------------------------------

func _on_name_changed(text: String) -> void:
	var cleaned := Leaderboard.clean_name(text)
	if cleaned != text:
		var caret := _name_edit.caret_column
		_name_edit.text = cleaned
		_name_edit.caret_column = mini(caret, cleaned.length())


func _process(_delta: float) -> void:
	# Polled: phone keyboards can change the text without a signal.
	if is_open() and _entry_row.visible and not _posted:
		_post_button.disabled = not Leaderboard.is_valid_name(Leaderboard.clean_name(_name_edit.text))


func _post() -> void:
	var player_name := Leaderboard.clean_name(_name_edit.text)
	if _posted or not Leaderboard.is_valid_name(player_name):
		_post_status.text = Leaderboard.name_rule()
		return
	_posted = true
	_name_edit.editable = false
	_name_edit.release_focus()
	_post_button.disabled = true
	_post_status.text = "Posting..."
	Sfx.play("click")
	var res: Dictionary = await Leaderboard.submit(player_name, _score, _won, _board)
	if not is_open():
		return
	if res["error"] != "":
		_post_status.text = res["error"]
		return
	var rank: int = await Leaderboard.fetch_rank(_score, "", false, _board)
	if not is_open():
		return
	var where := "this chapter's board" if res["online"] else "this device's board"
	_post_status.text = ("Posted! You are #%d on %s." % [rank, where]) if rank > 0 else "Posted to %s!" % where
	Sfx.play("ramp_complete")


func close() -> void:
	_voice_queue.clear()
	if _voice:
		_voice.stop()
	if _root:
		_root.visible = false


## Plays the next recorded line, skipping ids that have no recording yet.
func _speak_next() -> void:
	while not _voice_queue.is_empty():
		var stream := StoryVoice.stream_for(_voice_queue.pop_front())
		if stream != null:
			_voice.stream = stream
			_voice.play()
			return


func is_open() -> bool:
	return _root != null and _root.visible


## data: {won, first, chapter, coins, coin, score, stats, boss_share, revealed}
func open(data: Dictionary) -> void:
	for child in _page.get_children() + _buttons.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	var won: bool = data["won"]
	var ch: Dictionary = data["chapter"]
	var st: Dictionary = data["stats"]
	var title := _ink("VICTORY" if won else "NOT THIS TIME", 34, JournalPanel.RED_INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var who := str(ch["boss"]) if data["revealed"] else str(ch["title"])
	var sub := _ink("Chapter %d  ·  %s" % [int(ch["number"]), who], 17, JournalPanel.FADED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var closing: Array = ch["victory"] if won else ch["defeat"]
	_voice_queue.clear()
	for i in closing.size():
		_ink(str(closing[i]), 17)
		_voice_queue.append("%s_%s_%d" % [ch["id"], "victory" if won else "defeat", i + 1])
	_speak_next()
	_page.add_child(JournalPanel.rule())
	_ink("+%d coins   (you have %d)" % [int(data["coins"]), Story.coins], 22, JournalPanel.RED_INK)
	var coin: Dictionary = data["coin"]
	_ink("One of them: " + str(coin.get("text", "")), 15, JournalPanel.FADED)
	_page.add_child(JournalPanel.rule())
	_ink("This run", 20, JournalPanel.RED_INK)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 3)
	_page.add_child(grid)
	var seconds := int(float(st.get("time", 0.0)))
	var rows := [
		["Score", GameManager.format_number(float(data["score"]))],
		["Damage dealt", GameManager.format_number(float(st.get("damage", 0.0)))],
		["Boss hits", str(int(st.get("boss_hits", 0)))],
		["Bumpers hit", str(int(st.get("bumper_hits", 0)))],
		["Nudges used", str(int(st.get("nudges", 0)))],
		["Tilts", str(int(st.get("tilts", 0)))],
		["Balls lost", str(int(st.get("balls_lost", 0)))],
		["Spare parts taken", str(int(st.get("parts", 0)))],
		["Time played", "%d:%02d" % [seconds / 60, seconds % 60]],
	]
	if data["revealed"]:
		rows.insert(2, ["Boss health removed", "%d%%" % roundi(float(data["boss_share"]) * 100.0)])
	for row: Array in rows:
		grid.add_child(JournalPanel.ink_label(row[0], 16, JournalPanel.FADED, 200.0))
		grid.add_child(JournalPanel.ink_label(row[1], 16, JournalPanel.INK, 200.0))
	if won and data["first"]:
		_page.add_child(JournalPanel.rule())
		_ink("New journal page", 20, JournalPanel.RED_INK)
		_ink(str(ch["journal"]), 16)
		_ink(str(ch["machine_change"]), 15, JournalPanel.FADED)
	if won:
		_button("Continue", func() -> void: menu_pressed.emit()).grab_focus.call_deferred()
	else:
		_button("Try again", func() -> void: retry_pressed.emit()).grab_focus.call_deferred()
		_button("Story menu", func() -> void: menu_pressed.emit())
	_board = str(ch["id"])
	_score = float(data["score"])
	_won = won
	_posted = false
	_entry_row.visible = _score > 0.0
	_name_edit.editable = true
	_name_edit.text = Leaderboard.last_name
	_post_status.text = "Post this run to the Chapter %d leaderboard." % int(ch["number"]) if _score > 0.0 else ""
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.6)


func _ink(text: String, font_size: int, color: Color = JournalPanel.INK) -> Label:
	var label := JournalPanel.ink_label(text, font_size, color, WIDTH - 60.0)
	_page.add_child(label)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		_voice_queue.clear()
		_voice.stop()
		on_pressed.call())
	_buttons.add_child(b)
	return b
