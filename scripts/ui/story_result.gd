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
	_scroll.custom_minimum_size = Vector2(WIDTH - 40.0, 800)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 9)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	col.add_child(_buttons)


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
