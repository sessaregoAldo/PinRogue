class_name StoryResult
extends CanvasLayer
## The Journal's result page at the end of a story run: Victory (the boss's
## story, the machine's change) or Defeat, with the coins earned, the strange
## coin that fell out, and the run's statistics. Next turns to the chapter's
## leaderboard (as in Endless), where the run can be posted or not; from there
## Continue goes to the Story menu (defeat also offers Try again).

signal retry_pressed
signal menu_pressed

## The Story menu journal's page (StoryJournal.PAGE), so this is the same book.
const WIDTH := 470.0
const PAGE_H := 934.0
const RISE_TIME := 0.6
const TURN_TIME := 0.45
## Going back to the Story menu riffles this many pages back to the start.
const RIFFLE_PAGES := 30

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
var _time: float = -1.0
var _paper: PanelContainer
# The next page of the journal: the chapter's leaderboard.
var _holder: Control
var _board_view: PanelContainer
var _board_title: Label
var _board_run: Label
var _board_panel: LeaderboardPanel
var _busy: bool = false
var _binding: Binding
var _dim: ColorRect
var _won_run: bool = false


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
	_dim = dim
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	# The same journal as the Story menu's, in the same place: leather cover,
	# the pages under the open one, and the open page.
	_binding = Binding.new()
	_binding.position = StoryJournal.COVER.position
	_binding.size = StoryJournal.COVER.size
	_binding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_binding)
	# The two pages share one spot, the leaderboard under the result page, so
	# Next can turn one over to show the other.
	_holder = Control.new()
	_holder.position = Binding.MARGIN_TL
	_holder.size = Vector2(WIDTH, PAGE_H)
	_holder.clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_binding.add_child(_holder)
	_board_view = PanelContainer.new()
	_board_view.add_theme_stylebox_override("panel", _leaf_style())
	_board_view.size = Vector2(WIDTH, PAGE_H)
	_board_view.visible = false
	_holder.add_child(_board_view)
	var board_col := VBoxContainer.new()
	board_col.add_theme_constant_override("separation", 10)
	_board_view.add_child(board_col)
	_board_title = JournalPanel.ink_label("", 30, JournalPanel.RED_INK, WIDTH - 60.0)
	_board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_col.add_child(_board_title)
	_board_run = JournalPanel.ink_label("", 17, JournalPanel.FADED, WIDTH - 60.0)
	_board_run.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_col.add_child(_board_run)
	board_col.add_child(JournalPanel.rule())
	_board_panel = LeaderboardPanel.new(true)
	var board_center := CenterContainer.new()
	board_center.add_child(_board_panel)
	board_col.add_child(board_center)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_col.add_child(spacer)
	# Signing the page: the name and Post sit at the foot of the leaderboard page.
	board_col.add_child(JournalPanel.rule())
	_entry_row = HBoxContainer.new()
	_entry_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_entry_row.add_theme_constant_override("separation", 8)
	board_col.add_child(_entry_row)
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
	_post_status = JournalPanel.ink_label("", 15, JournalPanel.FADED, WIDTH - 60.0)
	_post_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_col.add_child(_post_status)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", _leaf_style())
	paper.size = Vector2(WIDTH, PAGE_H)
	_holder.add_child(paper)
	_paper = paper
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH - 40.0, PAGE_H - 32.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(_scroll)
	TouchScroll.setup(_scroll)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 9)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page)
	# Next / Continue where the Story menu has its Back button, under the book.
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.position = Vector2(0, 1052)
	_buttons.size = Vector2(600, 52)
	_root.add_child(_buttons)


# --- Chapter leaderboard ------------------------------------------------------------

func _on_name_changed(text: String) -> void:
	var cleaned := Leaderboard.clean_name(text)
	if cleaned != text:
		var caret := _name_edit.caret_column
		_name_edit.text = cleaned
		_name_edit.caret_column = mini(caret, cleaned.length())
	_board_panel.pending_name = cleaned


func _process(_delta: float) -> void:
	# Polled: phone keyboards can change the text without a signal.
	if is_open() and _entry_row.visible and not _posted:
		_post_button.disabled = not Leaderboard.is_valid_name(Leaderboard.clean_name(_name_edit.text))
		_board_panel.pending_name = Leaderboard.clean_name(_name_edit.text)


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
	var res: Dictionary = await Leaderboard.submit(player_name, _score, _won, _board, _time)
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
	_entry_row.visible = false
	_board_panel.pending = {} # posted: the board now has the real row
	_board_panel.refresh()


## Step two, after Next: the result page turns over like a journal page,
## uncovering the chapter's leaderboard. There the run can be posted (its row
## shows where it would land while the name is typed) or not, before moving on.
func _show_board() -> void:
	if _busy:
		return
	_busy = true
	var ch := StoryData.chapter(0)
	for c: Dictionary in StoryData.CHAPTERS:
		if c["id"] == _board:
			ch = c
	_board_title.text = "Chapter %d Leaderboard" % int(ch["number"])
	_board_run.text = "This run  ·  %s  ·  %s%s" % [GameManager.format_number(_score), Story.clock(maxf(_time, 0.0)), "  ·  won" if _won else ""]
	var can_post := _score > 0.0 and not _posted
	_board_panel.board = _board
	_board_panel.pending = {"score": _score, "won": _won, "time": _time} if can_post else {}
	_board_panel.pending_name = Leaderboard.clean_name(_name_edit.text)
	_board_view.visible = true
	_board_panel.refresh()
	for child in _buttons.get_children():
		child.queue_free()
	_voice_queue.clear()
	_voice.stop()
	# Forward: the open page folds away toward the spine; the shade over the
	# page underneath lifts.
	Sfx.play("page", -3.0, randf_range(0.9, 1.1))
	var shade := _shade()
	_holder.add_child(shade)
	_holder.move_child(shade, 1)
	_paper.pivot_offset = Vector2(0, PAGE_H * 0.5)
	var tw := create_tween().set_parallel()
	tw.tween_property(_paper, "scale:x", 0.001, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_paper, "modulate", Color(0.62, 0.56, 0.5), TURN_TIME).set_ease(Tween.EASE_IN)
	tw.tween_property(shade, "modulate:a", 0.0, TURN_TIME)
	await tw.finished
	shade.queue_free()
	_paper.visible = false
	_busy = false
	_entry_row.visible = can_post
	_post_status.visible = true
	_post_status.text = ("Type a name to see where you'd land, then post it, or move on.") if can_post else ""
	if _won_run:
		_button("Continue", func() -> void: _riffle_back(func() -> void: menu_pressed.emit()))
	else:
		_button("Try again", func() -> void: retry_pressed.emit())
		_button("Story menu", func() -> void: _riffle_back(func() -> void: menu_pressed.emit()))
	if can_post:
		_name_edit.grab_focus.call_deferred()
		_name_edit.caret_column = _name_edit.text.length()
	else:
		(_buttons.get_child(_buttons.get_child_count() - 1) as Button).grab_focus.call_deferred()


## Back to the Story menu: dozens of pages riffle back over the open one, fast
## through the middle of the book; the screen goes dark before they stop, and
## the menu carries the riffle on (StoryJournal.riffle_in) to the Chapters page.
func _riffle_back(done: Callable) -> void:
	if _busy:
		return
	_busy = true
	_entry_row.visible = false
	_post_status.visible = false
	for b in _buttons.get_children():
		(b as Button).disabled = true
	var fade: Tween = null
	for k in RIFFLE_PAGES:
		var t := float(k) / (RIFFLE_PAGES - 1)
		if fade == null and t >= 0.6: # the dark comes in while pages are still turning
			fade = create_tween()
			fade.tween_property(_root, "modulate", Color(0, 0, 0, 1), 0.45)
		# Slow, then fast, then slow again as the front of the book comes up.
		var swing := lerpf(0.05, 0.16, pow(absf(t - 0.45) / 0.55, 2.0))
		var leaf := _blank_leaf(k)
		_holder.add_child(leaf)
		leaf.pivot_offset = Vector2(0, PAGE_H * 0.5)
		leaf.scale.x = 0.001
		leaf.modulate = Color(0.62, 0.56, 0.5)
		if k % 3 == 0 or k == RIFFLE_PAGES - 1:
			Sfx.play("page", -6.0 if k < RIFFLE_PAGES - 1 else -2.0, randf_range(0.95, 1.35))
		var tw := create_tween().set_parallel()
		tw.tween_property(leaf, "scale:x", 1.0, swing).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(leaf, "modulate", Color.WHITE, swing)
		await get_tree().create_timer(swing * 0.55, true, false, true).timeout
	if fade.is_running():
		await fade.finished
	_busy = false
	done.call() # the Story menu picks the riffle up where this one went dark


## A plain leaf for the riffle: paper with a few faint lines of writing.
func _blank_leaf(seed_value: int) -> PanelContainer:
	var leaf := PanelContainer.new()
	leaf.add_theme_stylebox_override("panel", _leaf_style())
	leaf.size = Vector2(WIDTH, PAGE_H)
	leaf.mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var lines := Control.new()
	lines.draw.connect(func() -> void:
		var y := 40.0
		while y < PAGE_H - 60.0:
			var w := rng.randf_range(0.35, 0.95) * (WIDTH - 80.0)
			lines.draw_line(Vector2(10, y), Vector2(10 + w, y), Color(JournalPanel.INK, 0.12), 2.0)
			y += rng.randf_range(22.0, 34.0))
	leaf.add_child(lines)
	return leaf


## A shadow falling from the spine across a page (as in the Story journal).
func _shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.12, 0.07, 0.02, 0.55))
	gradient.set_color(1, Color(0.12, 0.07, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 4
	tex.fill_to = Vector2(1, 0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(WIDTH, PAGE_H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


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
	for child in _holder.get_children():
		if child != _paper and child != _board_view:
			child.queue_free() # leaves and shades from last time
	_paper.visible = true
	_paper.scale = Vector2.ONE
	_paper.modulate = Color.WHITE
	_board_view.visible = false
	_busy = false
	_root.modulate = Color.WHITE
	_scroll.scroll_vertical = 0
	var won: bool = data["won"]
	var ch: Dictionary = data["chapter"]
	var st: Dictionary = data["stats"]
	var title := _ink("VICTORY" if won else "NOT THIS TIME", 34, JournalPanel.RED_INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var who := str(ch["boss"]) if data["revealed"] else str(ch["title"])
	var sub := _ink("Chapter %d  ·  %s" % [int(ch["number"]), who], 17, JournalPanel.FADED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The run's time, with the record it set (if any).
	var records: Dictionary = data.get("records", {})
	var time_text := "Run time  " + Story.clock(float(st.get("time", 0.0)))
	if records.get("fastest_win", false):
		time_text += "   ·   fastest win!"
	elif records.get("best_score", false):
		time_text += "   ·   new best score!"
	var time_label := _ink(time_text, 20, JournalPanel.RED_INK)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var closing: Array = ch["victory"] if won else ch["defeat"]
	_voice_queue.clear()
	for i in closing.size():
		_page.add_child(StoryData.rich_label(str(closing[i]), 17, JournalPanel.INK, WIDTH - 60.0))
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
	var rows := [
		["Score", GameManager.format_number(float(data["score"]))],
		["Damage dealt", GameManager.format_number(float(st.get("damage", 0.0)))],
		["Boss hits", str(int(st.get("boss_hits", 0)))],
		["Bumpers hit", str(int(st.get("bumper_hits", 0)))],
		["Nudges used", str(int(st.get("nudges", 0)))],
		["Tilts", str(int(st.get("tilts", 0)))],
		["Balls lost", str(int(st.get("balls_lost", 0)))],
		["Spare parts taken", str(int(st.get("parts", 0)))],
		["Run time", Story.clock(float(st.get("time", 0.0)))],
	]
	if data["revealed"]:
		rows.insert(2, ["Boss health removed", "%d%%" % roundi(float(data["boss_share"]) * 100.0)])
		for extra: Array in ch.get("stat_rows", []): # the chapter's own numbers
			rows.insert(rows.size() - 1, [extra[0], str(int(st.get(extra[1], 0)))])
	for row: Array in rows:
		grid.add_child(JournalPanel.ink_label(row[0], 16, JournalPanel.FADED, 200.0))
		grid.add_child(JournalPanel.ink_label(row[1], 16, JournalPanel.INK, 200.0))
	if won and data["first"]:
		_page.add_child(JournalPanel.rule())
		_ink("New journal page", 20, JournalPanel.RED_INK)
		_page.add_child(StoryData.rich_label(str(ch["journal"]), 16, JournalPanel.INK, WIDTH - 60.0))
		_page.add_child(StoryData.rich_label(str(ch["machine_change"]), 15, JournalPanel.FADED, WIDTH - 60.0))
	_won_run = won
	_button("Next  >", func() -> void: _show_board()).grab_focus.call_deferred()
	_board = str(ch["id"])
	_score = float(data["score"])
	_time = float((data["stats"] as Dictionary).get("time", -1.0))
	_won = won
	_posted = false
	_entry_row.visible = false # on the leaderboard step
	_post_status.visible = false
	_name_edit.editable = true
	_name_edit.text = Leaderboard.last_name
	_post_button.disabled = false
	# The journal rises from the bottom of the screen; the dark comes up behind it.
	_root.visible = true
	_root.modulate = Color.WHITE
	_dim.modulate.a = 0.0
	_buttons.modulate.a = 0.0
	_binding.position.y = 1180.0
	var rise := create_tween().set_parallel()
	rise.tween_property(_dim, "modulate:a", 1.0, RISE_TIME * 0.8)
	rise.tween_property(_binding, "position:y", StoryJournal.COVER.position.y, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_property(_buttons, "modulate:a", 1.0, 0.3).set_delay(RISE_TIME)
	Sfx.play("page", -6.0, 0.7)


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


## A journal page: plain paper, its spine side shaded (the cover does the rest).
func _leaf_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = StoryJournal.PAPER
	style.border_color = Color(0.24, 0.14, 0.04, 0.35)
	style.border_width_left = 6 # the spine's shadow
	style.content_margin_left = 22
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


## The Story menu journal's leather cover (StoryJournal._draw), drawn around
## the pages: leather with stitching down the spine, and the edges of the
## pages under the open one.
class Binding:
	extends Control
	const MARGIN_TL := Vector2(44, 16)
	const MARGIN_BR := Vector2(14, 16)

	func _draw() -> void:
		var cover := StyleBoxFlat.new()
		cover.bg_color = StoryJournal.LEATHER
		cover.corner_radius_top_left = 10
		cover.corner_radius_bottom_left = 10
		cover.corner_radius_top_right = 18
		cover.corner_radius_bottom_right = 18
		cover.shadow_color = Color(0, 0, 0, 0.6)
		cover.shadow_size = 18
		cover.shadow_offset = Vector2(0, 10)
		cover.border_color = Color(0.14, 0.09, 0.05)
		cover.set_border_width_all(2)
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(cover, rect)
		draw_dashed_line(Vector2(18, 14), Vector2(18, size.y - 14), Color(0.54, 0.42, 0.29, 0.6), 2.0, 8.0)
		var page := Rect2(MARGIN_TL, size - MARGIN_TL - MARGIN_BR)
		draw_rect(Rect2(page.position + Vector2(8, 8), page.size), StoryJournal.PAPER.darkened(0.12))
		draw_rect(Rect2(page.position + Vector2(4, 4), page.size), StoryJournal.PAPER.darkened(0.06))
