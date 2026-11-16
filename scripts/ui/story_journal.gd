class_name StoryJournal
extends Control
## The Story menu, drawn as the Ghost's journal: a leather notebook with a
## bookmark tab for each section on its fore-edge. Sections hold one or more
## pages; tapping a tab, the arrows at the foot of a page, a horizontal swipe
## across the page (or Page Up / Page Down, the flipper keys) turns the page.
##
##   Chapters     the prologue, then one page per chapter reached: its
##                machine, best run, Play
##   Story        page one, then one page per chapter with the person behind its boss
##   Workshop     spare parts for sale, then the ones owned
##   Coins        the strange coins collected, a few per page
##   Wardrobe     one page per cosmetics group, with a small preview table
##   Leaderboard  Endless, then each chapter's board
##
## The menu calls open() when the Story page is shown, or arrive() to have the
## closed journal drop in from above and open; leave() closes it and lifts it
## away (await it).

## chapter_index -1: the prologue (Sal's handover), then chapter 1.
signal play_requested(chapter_index: int)
signal back_requested

const PAPER := Color(0.93, 0.88, 0.74)
const CARD := Color(0.97, 0.94, 0.86)
const INK := Color(0.17, 0.13, 0.1)
const FADED := Color(0.43, 0.36, 0.28)
const RED_INK := Color(0.5, 0.16, 0.1)
const BLUE_INK := Color(0.18, 0.25, 0.33)
const LEATHER := Color(0.23, 0.14, 0.09)
const TAPE := Color(0.84, 0.77, 0.59, 0.8)

const COVER := Rect2(16, 78, 528, 966)
const PAGE := Rect2(60, 94, 470, 934)
const CONTENT_W := 384.0
const TAB_TOP := 116.0
const TAB_H := 138.0
const TAB_GAP := 10.0
const TURN_TIME := 0.45
const SWIPE_MIN := 60.0
const COINS_PER_PAGE := 3

## [id, tab label, tab color, running head]
const SECTIONS: Array = [
	["chapters", "Chapters", Color(0.55, 0.23, 0.18), "Chapters"],
	["story", "Story", Color(0.24, 0.36, 0.46), "The story so far"],
	["workshop", "Workshop", Color(0.37, 0.42, 0.18), "Workshop"],
	["coins", "Coins", Color(0.54, 0.4, 0.08), "Coin tray"],
	["wardrobe", "Wardrobe", Color(0.18, 0.39, 0.38), "Wardrobe"],
	["leaderboard", "Leaderboard", Color(0.29, 0.28, 0.27), "Leaderboard"],
]

static var _hand: FontVariation
static var _hand_bold: FontVariation

var _section: String = "chapters"
var _index: int = 0
var _holder: Control
var _page: JournalPage
var _turning: bool = false
var _tabs: Dictionary = {}
var _press: Vector2 = Vector2.INF
var _swiped_at: int = -100000
## The chapter picked on the Chapters pages (-1: the furthest one reached).
var _pick: int = -1
## Wardrobe: group id -> the item selected on that page.
var _wardrobe_pick: Dictionary = {}
var _focus_after_build: bool = false
## The front cover (shown while the journal is closed) and the Back button.
var _cover: FrontCover
var _back: Button
## True while the journal drops in, opens, closes or leaves.
var animating: bool = false

const DROP_TIME := 0.55
const OPEN_TIME := 0.5
const OFF_SCREEN := -1180.0


## Caveat, the journal's handwriting.
static func hand(bold: bool = false) -> Font:
	if _hand == null:
		var base := load("res://assets/fonts/Caveat.ttf") as Font
		var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
		_hand = FontVariation.new()
		_hand.base_font = base
		_hand.variation_opentype = {wght: 500}
		_hand_bold = FontVariation.new()
		_hand_bold.base_font = base
		_hand_bold.variation_opentype = {wght: 700}
	return _hand_bold if bold else _hand


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(600, 1120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SECTIONS.size():
		_tabs[SECTIONS[i][0]] = _make_tab(i)
	_holder = Control.new()
	_holder.position = PAGE.position
	_holder.size = PAGE.size
	_holder.clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_cover = FrontCover.new()
	_cover.visible = false
	add_child(_cover)
	_back = Button.new()
	_back.text = "Back"
	_back.size = Vector2(280, 48)
	_back.position = Vector2((600.0 - 280.0) * 0.5, 1056)
	_back.add_theme_font_size_override("font_size", 22)
	_back.pressed.connect(func() -> void:
		if not animating:
			back_requested.emit())
	add_child(_back)


## The closed journal drops in from above, settles, and its cover swings open
## onto the Chapters pages.
func arrive() -> void:
	animating = true
	open()
	_cover.visible = true
	_cover.scale.x = 1.0
	_cover.modulate = Color.WHITE
	_back.modulate.a = 0.0
	position.y = OFF_SCREEN
	var drop := create_tween()
	drop.tween_property(self, "position:y", 0.0, DROP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await drop.finished
	Sfx.play("ramp_land", -8.0, 0.6)
	await get_tree().create_timer(0.18).timeout
	Sfx.play("page", -2.0, 0.8)
	var swing := create_tween().set_parallel()
	swing.tween_property(_cover, "scale:x", 0.001, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	swing.tween_property(_cover, "modulate", Color(0.55, 0.5, 0.45), OPEN_TIME).set_ease(Tween.EASE_IN)
	swing.tween_property(_back, "modulate:a", 1.0, OPEN_TIME)
	await swing.finished
	_cover.visible = false
	animating = false


## The cover swings shut, then the journal lifts away through the top.
func leave() -> void:
	animating = true
	_press = Vector2.INF
	_cover.visible = true
	_cover.scale.x = 0.001
	_cover.modulate = Color(0.55, 0.5, 0.45)
	Sfx.play("page", -2.0, 0.75)
	var shut := create_tween().set_parallel()
	shut.tween_property(_cover, "scale:x", 1.0, OPEN_TIME * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	shut.tween_property(_cover, "modulate", Color.WHITE, OPEN_TIME * 0.8)
	shut.tween_property(_back, "modulate:a", 0.0, OPEN_TIME * 0.6)
	await shut.finished
	Sfx.play("ramp_land", -10.0, 0.7)
	await get_tree().create_timer(0.12).timeout
	var lift := create_tween()
	lift.tween_property(self, "position:y", OFF_SCREEN, DROP_TIME * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await lift.finished
	visible = false
	position.y = 0.0
	_cover.visible = false
	_back.modulate.a = 1.0
	animating = false


## Shown: back to the Chapters pages, on the chapter that's up next.
func open() -> void:
	_pick = -1
	_section = "chapters"
	_index = _default_index("chapters")
	_focus_after_build = true
	_show_now()


## Rebuilds the open page in place (after a purchase, for instance).
func refresh() -> void:
	_index = clampi(_index, 0, _page_count(_section) - 1)
	_show_now()


func _show_now() -> void:
	for child in _holder.get_children():
		child.queue_free()
	_page = _build(_section, _index)
	_holder.add_child(_page)
	_update_tabs()


# --- Turning pages ---------------------------------------------------------------

func _open_section(id: String) -> void:
	if _turning or animating or id == _section:
		return
	var order := _section_order(id) - _section_order(_section)
	_turn(id, _default_index(id), 1 if order > 0 else -1)


func _step(delta: int) -> void:
	if _turning or animating:
		return
	var section := _section
	var next := _index + delta
	var order := _section_order(_section)
	# Past either end of a section: on into the next section's first page, or
	# back to the previous section's last. The book itself has two ends.
	if next >= _page_count(_section):
		if order + 1 >= SECTIONS.size():
			return
		section = SECTIONS[order + 1][0]
		next = 0
	elif next < 0:
		if order == 0:
			return
		section = SECTIONS[order - 1][0]
		next = _page_count(section) - 1
	if section == "chapters" and next > 0:
		_pick = next - 1 # page 0 is the prologue
	_turn(section, next, delta)


## Forward: the open page folds away toward the spine, uncovering the next.
## Back: the previous page swings in from the spine over the open one.
func _turn(section: String, index: int, dir: int) -> void:
	_turning = true
	Sfx.play("page", -3.0, randf_range(0.9, 1.1))
	var old := _page
	_section = section
	_index = index
	var fresh := _build(section, index)
	_holder.add_child(fresh)
	_page = fresh
	_update_tabs()
	var shade := _shade()
	var blocker := Control.new() # nothing on either page is clickable mid-turn
	blocker.size = PAGE.size
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween().set_parallel()
	if dir >= 0:
		# old on top, folding away; the shade over the uncovered page lifts.
		_holder.move_child(fresh, 0)
		_holder.add_child(shade)
		_holder.move_child(shade, 1)
		old.pivot_offset = Vector2(0, PAGE.size.y * 0.5)
		tw.tween_property(old, "scale:x", 0.001, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(old, "modulate", Color(0.62, 0.56, 0.5), TURN_TIME).set_ease(Tween.EASE_IN)
		tw.tween_property(shade, "modulate:a", 0.0, TURN_TIME)
	else:
		# fresh on top, swinging in; the page it covers darkens under it.
		_holder.add_child(shade)
		_holder.move_child(fresh, _holder.get_child_count() - 1)
		shade.modulate.a = 0.0
		fresh.pivot_offset = Vector2(0, PAGE.size.y * 0.5)
		fresh.scale.x = 0.001
		fresh.modulate = Color(0.62, 0.56, 0.5)
		tw.tween_property(fresh, "scale:x", 1.0, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(fresh, "modulate", Color.WHITE, TURN_TIME).set_ease(Tween.EASE_OUT)
		tw.tween_property(shade, "modulate:a", 1.0, TURN_TIME)
	_holder.add_child(blocker)
	await tw.finished
	for node: Node in [old, shade, blocker]:
		if is_instance_valid(node):
			node.queue_free()
	_turning = false


## A shadow falling from the spine across a page.
func _shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.12, 0.07, 0.02, 0.55))
	gradient.set_color(1, Color(0.12, 0.07, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = PAGE.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or animating:
		_press = Vector2.INF
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if event.is_pressed():
			_press = pos if PAGE.has_point(pos) else Vector2.INF
		elif _press != Vector2.INF:
			var d := pos - _press
			_press = Vector2.INF
			if absf(d.x) >= SWIPE_MIN and absf(d.x) > absf(d.y) * 1.3:
				_swiped_at = Time.get_ticks_msec()
				_step(1 if d.x < 0.0 else -1) # swipe left: the next page
		return
	if event is InputEventKey and event.is_echo():
		return
	if event.is_action_pressed("ui_page_down") or event.is_action_pressed("flipper_right"):
		get_viewport().set_input_as_handled()
		_step(1)
	elif event.is_action_pressed("ui_page_up") or event.is_action_pressed("flipper_left"):
		get_viewport().set_input_as_handled()
		_step(-1)


## A button let go at the end of a swipe or a scroll must not press.
func _gesture() -> bool:
	return Time.get_ticks_msec() - _swiped_at < 300 or (_page != null and TouchScroll.dragged(_page.scroll))


# --- Sections ---------------------------------------------------------------------

func _section_order(id: String) -> int:
	for i in SECTIONS.size():
		if SECTIONS[i][0] == id:
			return i
	return 0


func _page_count(id: String) -> int:
	match id:
		"chapters":
			return _last_open() + 2 if Story.intro_seen else 1 # the prologue first
		"story":
			return StoryData.CHAPTERS.size() + 1 if Story.intro_seen else 1
		"workshop":
			return 2
		"coins":
			return maxi(1, ceili(Story.coin_tray.size() / float(COINS_PER_PAGE)))
		"wardrobe":
			return Cosmetics.GROUPS.size()
		"leaderboard":
			return StoryData.CHAPTERS.size() + 1
	return 1


func _default_index(id: String) -> int:
	match id:
		"chapters":
			return _current_chapter() + 1 if Story.intro_seen else 0
		"leaderboard":
			return _current_chapter() + 1 # the chapter the Chapters pages are on
	return 0


## The furthest chapter that can be played: the first not beaten (or the last).
func _last_open() -> int:
	var next := Story.next_chapter()
	return next if next >= 0 else StoryData.CHAPTERS.size() - 1


func _current_chapter() -> int:
	var last := _last_open()
	return _pick if _pick >= 0 and _pick <= last else last


func _update_tabs() -> void:
	for id: String in _tabs:
		var tab := _tabs[id] as Button
		var on := id == _section
		tab.position.x = PAGE.end.x - 2.0 if on else PAGE.end.x
		tab.size.x = 62.0 if on else 50.0
		tab.modulate = Color.WHITE if on else Color(0.82, 0.82, 0.82)


func _make_tab(i: int) -> Button:
	var id: String = SECTIONS[i][0]
	var label: String = SECTIONS[i][1]
	var color: Color = SECTIONS[i][2]
	var tab := Button.new()
	tab.tooltip_text = label
	tab.position = Vector2(PAGE.end.x, TAB_TOP + i * (TAB_H + TAB_GAP))
	tab.size = Vector2(50, TAB_H)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color if state != "hover" else color.lightened(0.12)
		box.corner_radius_top_right = 10
		box.corner_radius_bottom_right = 10
		if state == "focus":
			box.draw_center = false
			box.border_color = Color(1.0, 0.85, 0.3)
			box.set_border_width_all(2)
		else:
			box.shadow_color = Color(0, 0, 0, 0.35)
			box.shadow_size = 3
			box.shadow_offset = Vector2(2, 2)
		tab.add_theme_stylebox_override(state, box)
	var text := Control.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.draw.connect(func() -> void:
		var font := hand(true)
		var fs := 27
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Written down the tab (top to bottom), centred on the part that sticks out.
		text.draw_set_transform(Vector2(text.size.x - 25.0, text.size.y * 0.5), PI * 0.5)
		text.draw_string(font, Vector2(-w * 0.5, fs * 0.3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.98, 0.94, 0.85)))
	tab.resized.connect(text.queue_redraw)
	tab.add_child(text)
	tab.pressed.connect(func() -> void: _open_section(id))
	add_child(tab)
	return tab


func _draw() -> void:
	# The leather cover, its stitching and the edges of the pages under this one.
	var cover := StyleBoxFlat.new()
	cover.bg_color = LEATHER
	cover.corner_radius_top_left = 10
	cover.corner_radius_bottom_left = 10
	cover.corner_radius_top_right = 18
	cover.corner_radius_bottom_right = 18
	cover.shadow_color = Color(0, 0, 0, 0.6)
	cover.shadow_size = 18
	cover.shadow_offset = Vector2(0, 10)
	cover.border_color = Color(0.14, 0.09, 0.05)
	cover.set_border_width_all(2)
	draw_style_box(cover, COVER)
	draw_dashed_line(Vector2(COVER.position.x + 18, COVER.position.y + 14),
			Vector2(COVER.position.x + 18, COVER.end.y - 14), Color(0.54, 0.42, 0.29, 0.6), 2.0, 8.0)
	draw_rect(Rect2(PAGE.position + Vector2(8, 8), PAGE.size), PAPER.darkened(0.12))
	draw_rect(Rect2(PAGE.position + Vector2(4, 4), PAGE.size), PAPER.darkened(0.06))


# --- Pages ------------------------------------------------------------------------

func _build(id: String, index: int) -> JournalPage:
	var count := _page_count(id)
	index = clampi(index, 0, count - 1)
	var number := 1
	for s: Array in SECTIONS:
		if s[0] == id:
			break
		number += _page_count(s[0])
	var head: String = SECTIONS[_section_order(id)][3]
	var order := _section_order(id)
	var first := order == 0 and index == 0
	var last := order == SECTIONS.size() - 1 and index == count - 1
	var page := JournalPage.new(head, number + index, index, count, _step, not first, not last)
	match id:
		"chapters":
			_fill_chapter(page.body, index)
		"story":
			_fill_story(page.body, index)
		"workshop":
			_fill_workshop(page.body, index)
		"coins":
			_fill_coins(page.body, index)
		"wardrobe":
			_fill_wardrobe(page.body, index)
		"leaderboard":
			_fill_board(page.body, index)
	return page


func _fill_chapter(body: VBoxContainer, page: int) -> void:
	if page == 0:
		# The prologue: Sal's handover, the machine waking, the Journal. Played
		# once on the first visit, and replayable from here (it leads into chapter 1).
		_hand_label(body, "Prologue", 52, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		_hand_label(body, "The machine from Sal's garage", 32, RED_INK, false, HORIZONTAL_ALIGNMENT_CENTER)
		body.add_child(_photo(str(StoryData.chapter(0)["scene"]), -2.0))
		_text(body, "A pinball machine, bought from a man named Sal. No maker's plate, no serial number.", 18, FADED)
		_stamp(body, "Replay Prologue" if Story.intro_seen else "Begin", -1)
		if Story.intro_seen:
			_text(body, "Plays the beginning again, then chapter 1.", 16, FADED)
		return
	var index := page - 1
	var ch := StoryData.chapter(index)
	var beaten := Story.is_beaten(ch["id"])
	_hand_label(body, "Chapter %d" % int(ch["number"]), 52, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	_hand_label(body, str(ch["title"]), 36, RED_INK, false, HORIZONTAL_ALIGNMENT_CENTER)
	# The machine he's met on. The second machine stays a surprise until he's beaten.
	var scene: String = str(ch.get("boss_scene", ch["scene"])) if beaten else str(ch["scene"])
	body.add_child(_photo(scene, 2.0 if index % 2 == 0 else -2.0))
	var best: Dictionary = Story.best.get(ch["id"], {})
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	body.add_child(grid)
	_stat(grid, "Status", "Beaten" if beaten else "Not yet", BLUE_INK if beaten else RED_INK)
	_stat(grid, "Best score", GameManager.format_number(float(best["score"])) if best.has("score") else "-", INK)
	var fastest := float(best.get("fastest_win", 0.0))
	_stat(grid, "Fastest win", Story.clock(fastest) if fastest > 0.0 else "-", INK)
	var bosses := Story.beaten.size()
	if bosses > 0:
		_text(body, "Every boss beaten adds %d%% to your Story scores:" % roundi(StoryData.SCORE_BONUS_PER_BOSS * 100.0), 16, FADED)
		var now := _hand_label(body, "+%d%% now" % roundi(StoryData.SCORE_BONUS_PER_BOSS * 100.0 * bosses), 28, RED_INK, true)
		now.add_theme_constant_override("line_spacing", -8)
	_stamp(body, ("Replay Chapter %d" if beaten else "Play Chapter %d") % int(ch["number"]), index)
	var line: String = StoryData.HUB_LINE_START
	if beaten:
		line = ch["hub_line"]
	elif index > 0:
		line = StoryData.CHAPTERS[index - 1]["hub_line"]
	var hub := StoryData.rich_label("“%s”" % line, 27, BLUE_INK, CONTENT_W, hand(false))
	hub.add_theme_constant_override("line_separation", -4)
	body.add_child(hub)
	_hand_label(body, "the Ghost", 23, FADED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	if Story.next_chapter() < 0 and index == _last_open():
		_text(body, StoryData.MORE_SOON, 16, FADED)


func _fill_story(body: VBoxContainer, index: int) -> void:
	if not Story.intro_seen:
		_hand_label(body, "The pages are blank.", 36, INK, true)
		_text(body, "Start Story Mode and the journal will find you.", 18, FADED)
		return
	if index == 0:
		_hand_label(body, "Page one", 40, RED_INK, true)
		_rich(body, "If you are reading this, {she} has found you. Good. I had hoped somebody would come.", 19, INK)
		_rich(body, "I built {her} and I am, I'm afraid, still in {her}. I don't remember much else. Be my hands, and I'll be your instructions. Help me finish {her}, and perhaps I'll remember what {she} cost me.", 19, INK)
		_rich(body, "The coins {she} pays out are not mine. I never minted them. I would very much like to know who did.", 19, INK)
		if Story.attempts > 0:
			_text(body, "Runs played: %d" % Story.attempts, 16, FADED)
		return
	var ch: Dictionary = StoryData.CHAPTERS[index - 1]
	if not Story.is_beaten(ch["id"]):
		_hand_label(body, "Chapter %d" % int(ch["number"]), 40, RED_INK, true)
		_text(body, "This page hasn't been written yet.", 18, FADED)
		if index == StoryData.CHAPTERS.size():
			_text(body, StoryData.MORE_SOON, 16, FADED)
		return
	_hand_label(body, "Chapter %d: %s" % [int(ch["number"]), ch["title"]], 38, RED_INK, true)
	# Who he was: a pencil sketch of the boss, taped in, and his name.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var sketch_slot := Control.new()
	sketch_slot.custom_minimum_size = Vector2(128, 150)
	var sketch := Sketch.new(str(ch.get("art", "")))
	sketch.position = Vector2(4, 6)
	sketch.rotation = deg_to_rad(-3.0 if index % 2 == 1 else 2.0)
	sketch_slot.add_child(sketch)
	row.add_child(sketch_slot)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var boss := _hand_label(names, str(ch["boss"]), 36, INK, true)
	boss.custom_minimum_size.x = 0
	var person := _hand_label(names, str(ch.get("person", "")), 26, RED_INK)
	person.custom_minimum_size.x = CONTENT_W - 150.0
	_rich(body, str(ch["journal"]), 19, INK)
	body.add_child(StoryData.rich_label(str(ch["machine_change"]), 16, FADED, CONTENT_W))
	var note := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(BLUE_INK, 0.05)
	box.border_color = Color(BLUE_INK, 0.55)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12)
	note.add_theme_stylebox_override("panel", box)
	body.add_child(note)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	note.add_child(inner)
	var how := _hand_label(inner, "How to beat him", 26, BLUE_INK, true)
	how.custom_minimum_size.x = CONTENT_W - 28.0
	var hint := _hand_label(inner, str(ch["hint"]), 25, BLUE_INK)
	hint.custom_minimum_size.x = CONTENT_W - 28.0
	var best: Dictionary = Story.best.get(ch["id"], {})
	if not best.is_empty():
		var line := "Best run: score %s in %s, damage dealt %s." % [
				GameManager.format_number(float(best.get("score", 0.0))),
				Story.clock(float(best.get("time", 0.0))),
				GameManager.format_number(float(best.get("damage", 0.0)))]
		if float(best.get("fastest_win", 0.0)) > 0.0:
			line += " Fastest win: " + Story.clock(float(best["fastest_win"])) + "."
		_text(body, line, 16, FADED)
	if index == StoryData.CHAPTERS.size():
		_text(body, StoryData.MORE_SOON, 16, FADED)


func _fill_workshop(body: VBoxContainer, index: int) -> void:
	var for_sale: Array[Dictionary] = []
	var owned: Array[Dictionary] = []
	for part: Dictionary in PowerupManager.POWERUPS:
		if part.get("disabled", false):
			continue
		if Story.is_unlocked(part["id"]):
			owned.append(part)
		elif Story.price(part["id"]) >= 0:
			for_sale.append(part)
	if index == 0:
		_hand_label(body, "On the shelf", 40, INK, true)
		_text(body, "Coins unlock spare parts for Story runs.", 18, FADED)
		for_sale.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Story.price(a["id"]) < Story.price(b["id"]))
		if for_sale.is_empty():
			_text(body, "Every part is yours. The shelves are empty.", 19, INK)
		for part in for_sale:
			_part_row(body, part, false)
	else:
		_hand_label(body, "In the toolbox", 40, INK, true)
		_text(body, "Parts the machine can offer you in Story runs.", 18, FADED)
		for part in owned:
			_part_row(body, part, true)


func _part_row(body: VBoxContainer, part: Dictionary, owned: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 58
	body.add_child(row)
	var check := Control.new()
	check.custom_minimum_size = Vector2(28, 28)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.draw.connect(func() -> void:
		check.draw_rect(Rect2(2, 2, 24, 24), INK, false, 2.0)
		if owned:
			check.draw_polyline(PackedVector2Array([Vector2(5, 15), Vector2(12, 23), Vector2(29, -2)]), BLUE_INK, 3.5, true))
	row.add_child(check)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := _text(info, "%s  ·  %s" % [part["title"], part["tier"]], 20, INK)
	title.custom_minimum_size.x = CONTENT_W - (170.0 if not owned else 44.0)
	var desc := _text(info, str(part["desc"]), 15, FADED)
	desc.custom_minimum_size.x = title.custom_minimum_size.x
	if not owned:
		var cost := Story.price(part["id"])
		var buy := _ink_button("%d coins" % cost, Vector2(110, 46))
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.disabled = Story.coins < cost
		buy.tooltip_text = "" if not buy.disabled else "%d more coins needed" % (cost - Story.coins)
		var id: String = part["id"]
		buy.pressed.connect(func() -> void:
			if _gesture():
				return
			if Story.buy(id):
				Sfx.play("powerup")
				refresh()
			else:
				Sfx.play("warning"))
		row.add_child(buy)
	body.add_child(_rule())


func _fill_coins(body: VBoxContainer, index: int) -> void:
	if index == 0:
		_hand_label(body, "%d coins to spend" % Story.coins, 38, RED_INK, true)
		_text(body, "%d found in all. None of these should exist." % Story.coins_earned, 17, FADED)
	var tray := Story.coin_tray.duplicate()
	tray.reverse() # newest first
	if tray.is_empty():
		_rich(body, "No coins yet. {She} pays out for every dent you put in whoever is hiding in there, win or lose.", 19, INK)
		return
	for coin: Variant in tray.slice(index * COINS_PER_PAGE, (index + 1) * COINS_PER_PAGE):
		if not coin is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		body.add_child(row)
		var rubbing := Rubbing.new(str((coin as Dictionary).get("year", "")), randf_range(-8.0, 8.0))
		rubbing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rubbing)
		var text := _text(row, str((coin as Dictionary).get("text", "")), 17, INK)
		text.custom_minimum_size.x = CONTENT_W - 112.0
		body.add_child(_rule())


func _fill_wardrobe(body: VBoxContainer, index: int) -> void:
	var group: Array = Cosmetics.GROUPS[index]
	var group_id: String = group[0]
	_hand_label(body, str(group[1]), 40, INK, true)
	if not _wardrobe_pick.has(group_id):
		_wardrobe_pick[group_id] = Cosmetics.equipped(group_id)
	var picked: Dictionary = _wardrobe_pick[group_id]
	# The preview table, taped in, beside what's picked and its button.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	body.add_child(top)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(150, 222)
	var card := Card.new(Vector2(140, 214))
	card.position = Vector2(4, 4)
	card.rotation = deg_to_rad(-2.0)
	slot.add_child(card)
	var preview := CosmeticsPanel.CosmeticsPreview.new()
	preview.position = Vector2(8, 10)
	card.add_child(preview)
	top.add_child(slot)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(side)
	var picked_name := _hand_label(side, str(picked.get("name", "")), 34, INK, true)
	picked_name.custom_minimum_size.x = CONTENT_W - 170.0
	var action := _ink_button("", Vector2(CONTENT_W - 170.0, 50))
	var state := _text(side, "", 16, FADED)
	state.custom_minimum_size.x = CONTENT_W - 170.0
	side.add_child(action)
	if Story.is_equipped(group_id, picked):
		action.text = "In use"
		action.disabled = true
	elif Story.owns_cosmetic(picked):
		action.text = "Use"
		state.text = "Yours. Not in use."
	else:
		var cost := int(picked.get("price", 0))
		action.text = "Buy  ·  %d coins" % cost
		action.disabled = Story.coins < cost
		state.text = "%d more coins needed." % (cost - Story.coins) if action.disabled else "Not yours yet."
	action.pressed.connect(func() -> void:
		if _gesture():
			return
		if Story.owns_cosmetic(picked):
			Story.equip_cosmetic(group_id, picked)
			Sfx.play("click")
		elif Story.buy_cosmetic(group_id, picked):
			Sfx.play("powerup")
		else:
			Sfx.play("warning")
			return
		refresh())
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var items := Cosmetics.items(group_id)
	for it: Dictionary in items:
		grid.add_child(_swatch(group_id, it, picked, preview))
	preview.show_look({group_id: picked}, str(picked.get("name", "")))


func _swatch(group_id: String, it: Dictionary, picked: Dictionary, preview: CosmeticsPanel.CosmeticsPreview) -> Button:
	var owned := Story.owns_cosmetic(it)
	var worn := Story.is_equipped(group_id, it)
	var selected: bool = picked.get("id", "") == it["id"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 108)
	b.clip_contents = true
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.25 if st == "normal" else 0.45)
		box.border_color = RED_INK if selected else Color(INK, 0.25 if st == "normal" else 0.5)
		box.set_border_width_all(3 if selected else 1)
		box.set_corner_radius_all(6)
		if st == "focus":
			box.draw_center = false
			box.border_color = BLUE_INK
			box.set_border_width_all(2)
		b.add_theme_stylebox_override(st, box)
	var texture: Texture2D = null
	if owned and it.has("image") and ResourceLoader.exists(it["image"]):
		texture = load(it["image"]) as Texture2D
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.draw.connect(func() -> void:
		var c := Vector2(44, 32)
		if texture != null:
			face.draw_texture_rect(texture, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false)
		else:
			face.draw_circle(c, 21.0, it.get("color", Color.BLACK) if owned else Color(0.1, 0.08, 0.07))
		face.draw_arc(c, 22.0, 0.0, TAU, 32, Color(INK, 0.6), 2.0, true)
		var font := ThemeDB.fallback_font
		face.draw_string(font, Vector2(2, 74), str(it["name"]), HORIZONTAL_ALIGNMENT_CENTER, 84, 13, INK)
		var note := "In use" if worn else ("Owned" if owned else "%d coins" % int(it["price"]))
		face.draw_string(hand(true), Vector2(2, 98), note, HORIZONTAL_ALIGNMENT_CENTER, 84, 20, RED_INK if worn else FADED))
	b.add_child(face)
	b.pressed.connect(func() -> void:
		if _gesture():
			return
		Sfx.play("click")
		_wardrobe_pick[group_id] = it
		refresh())
	b.mouse_entered.connect(func() -> void: preview.show_look({group_id: it}, str(it["name"])))
	b.focus_entered.connect(func() -> void: preview.show_look({group_id: it}, str(it["name"])))
	b.mouse_exited.connect(func() -> void: preview.show_look({group_id: picked}, str(picked.get("name", ""))))
	return b


func _fill_board(body: VBoxContainer, index: int) -> void:
	var panel := LeaderboardPanel.new(true)
	if index == 0:
		_hand_label(body, "Endless", 44, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		_hand_label(body, "All machines", 30, RED_INK, false, HORIZONTAL_ALIGNMENT_CENTER)
		panel.board = ""
	else:
		var ch: Dictionary = StoryData.CHAPTERS[index - 1]
		_hand_label(body, "Chapter %d" % int(ch["number"]), 44, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		_hand_label(body, str(ch["title"]), 30, RED_INK, false, HORIZONTAL_ALIGNMENT_CENTER)
		panel.board = str(ch["id"])
	var center := CenterContainer.new()
	center.custom_minimum_size.x = CONTENT_W
	center.add_child(panel)
	body.add_child(center)
	panel.refresh.call_deferred() # once it's on the page (it checks it's visible)


# --- Ink on paper -------------------------------------------------------------------

func _text(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CONTENT_W, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


## Like _text, but any {word} (the machine's names) is drawn in StoryData.MACHINE_FONT.
func _rich(parent: Control, text: String, font_size: int, color: Color) -> RichTextLabel:
	var label := StoryData.rich_label(text, font_size, color, CONTENT_W)
	parent.add_child(label)
	return label


func _hand_label(parent: Control, text: String, font_size: int, color: Color, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _text(parent, text, font_size, color)
	label.horizontal_alignment = align
	label.add_theme_font_override("font", hand(bold))
	label.add_theme_constant_override("line_spacing", -4)
	return label


func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(INK, 0.18)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _stat(grid: GridContainer, title: String, value: String, color: Color) -> void:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", -4)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(cell)
	var t := _text(cell, title, 15, FADED)
	t.custom_minimum_size.x = (CONTENT_W - 16.0) / 3.0
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var v := _hand_label(cell, value, 32, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	v.custom_minimum_size.x = t.custom_minimum_size.x


## A button outlined in red ink.
func _ink_button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(RED_INK, {"normal": 0.04, "hover": 0.1, "pressed": 0.18, "disabled": 0.0, "focus": 0.0}[st])
		box.border_color = Color(FADED, 0.5) if st == "disabled" else (BLUE_INK if st == "focus" else RED_INK)
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		if st == "focus":
			box.draw_center = false
			box.set_border_width_all(3)
		b.add_theme_stylebox_override(st, box)
	b.add_theme_font_override("font", hand(true))
	b.add_theme_font_size_override("font_size", 25)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, RED_INK)
	b.add_theme_color_override("font_disabled_color", Color(FADED, 0.75))
	return b


## The chapter's big button, like a rubber stamp: a double red border.
## chapter_index -1 is the prologue.
func _stamp(body: VBoxContainer, text: String, chapter_index: int) -> void:
	var b := _ink_button(text, Vector2(CONTENT_W, 68))
	b.add_theme_font_size_override("font_size", 38)
	var inner := Panel.new()
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = Color(RED_INK, 0.7)
	line.set_border_width_all(1)
	line.set_corner_radius_all(4)
	inner.add_theme_stylebox_override("panel", line)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 5
	inner.offset_top = 5
	inner.offset_right = -5
	inner.offset_bottom = -5
	b.add_child(inner)
	b.pressed.connect(func() -> void:
		if not _gesture():
			play_requested.emit(chapter_index))
	body.add_child(b)
	if _focus_after_build:
		_focus_after_build = false
		b.grab_focus.call_deferred()


## A photo of a machine, taped onto the page.
func _photo(scene_path: String, tilt: float) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CONTENT_W, 386)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := Card.new(Vector2(196, 372))
	card.position = Vector2((CONTENT_W - 196.0) * 0.5, 8)
	card.rotation = deg_to_rad(tilt)
	slot.add_child(card)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.position = Vector2(12, 12)
	frame.size = Vector2(172, 321)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	var view := SubViewport.new()
	view.size = Vector2i(172, 321)
	var cam := Camera2D.new()
	cam.position = Vector2(300, 560)
	cam.zoom = Vector2.ONE * (172.0 / 600.0)
	view.add_child(cam)
	var level := (load(scene_path) as PackedScene).instantiate() as Level
	Cosmetics.apply(level)
	level.process_mode = Node.PROCESS_MODE_DISABLED # just a picture
	view.add_child(level)
	frame.add_child(view)
	var caption := Label.new()
	caption.text = level.level_name
	caption.position = Vector2(0, 334)
	caption.size = Vector2(196, 34)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", hand(false))
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color(0.29, 0.23, 0.17))
	card.add_child(caption)
	return slot


# --- Drawn pieces ------------------------------------------------------------------

## One page of the journal: ruled paper, a margin, the running head and page
## number, a scrolling body, and (in a section of several pages) arrows and dots.
class JournalPage:
	extends Control

	var head: String
	var number: int
	var index: int
	var count: int
	var scroll: ScrollContainer
	var body: VBoxContainer

	var has_prev: bool
	var has_next: bool

	func _init(running_head: String, page_number: int, page_index: int, page_count: int, step: Callable,
			can_go_back: bool, can_go_on: bool) -> void:
		has_prev = can_go_back
		has_next = can_go_on
		head = running_head
		number = page_number
		index = page_index
		count = page_count
		size = PAGE.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		scroll = ScrollContainer.new()
		scroll.position = Vector2(54, 58)
		scroll.size = Vector2(CONTENT_W + 14.0, size.y - 58.0 - 78.0)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		# A thin pencil-grey scrollbar instead of the menu's.
		var bar := scroll.get_v_scroll_bar()
		var track := StyleBoxEmpty.new()
		track.content_margin_left = 3
		track.content_margin_right = 3
		bar.add_theme_stylebox_override("scroll", track)
		for st: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(INK, 0.22 if st == "grabber" else 0.4)
			grab.set_corner_radius_all(3)
			bar.add_theme_stylebox_override(st, grab)
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		body.custom_minimum_size.x = CONTENT_W
		scroll.add_child(body)
		TouchScroll.setup(scroll)
		# Arrows on every page: past either end they go on to the neighbouring section.
		_arrow(Vector2(46, size.y - 66), -1, step)
		_arrow(Vector2(size.x - 70, size.y - 66), 1, step)

	func _arrow(at: Vector2, dir: int, step: Callable) -> void:
		var b := Button.new()
		b.flat = true
		b.position = at
		b.size = Vector2(52, 52)
		b.tooltip_text = "Next page" if dir > 0 else "Previous page"
		b.disabled = not (has_next if dir > 0 else has_prev)
		b.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, empty)
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.draw.connect(func() -> void:
			var c := Vector2(26, 26)
			var a := Color(INK, 0.22 if b.disabled else (1.0 if b.is_hovered() else 0.75))
			var d := float(dir)
			icon.draw_polyline(PackedVector2Array([c + Vector2(-6 * d, -12), c + Vector2(6 * d, 0), c + Vector2(-6 * d, 12)]), a, 3.0, true))
		b.mouse_entered.connect(icon.queue_redraw)
		b.mouse_exited.connect(icon.queue_redraw)
		b.add_child(icon)
		b.pressed.connect(func() -> void: step.call(dir))
		add_child(b)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		var y := 92.0
		while y < h - 20.0:
			draw_line(Vector2(40, y), Vector2(w, y), Color(0.24, 0.36, 0.46, 0.15), 1.0)
			y += 34.0
		draw_line(Vector2(40, 0), Vector2(40, h), Color(0.59, 0.16, 0.12, 0.28), 2.0)
		for i in 18: # the spine's shadow
			var t := 1.0 - i / 18.0
			draw_rect(Rect2(i, 0, 1, h), Color(0.24, 0.14, 0.04, 0.42 * t * t))
		draw_rect(Rect2(w - 2, 0, 2, h), Color(0, 0, 0, 0.12))
		var font := StoryJournal.hand(false)
		draw_string(font, Vector2(54, 40), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, FADED)
		draw_string(font, Vector2(w - 126, 40), "p. %d" % number, HORIZONTAL_ALIGNMENT_RIGHT, 100, 25, FADED)
		if count > 1:
			var foot := h - 40.0
			if count <= 10:
				var gap := 20.0
				var x0 := w * 0.5 + 10.0 - gap * (count - 1) * 0.5
				for i in count:
					var c := Vector2(x0 + gap * i, foot)
					if i == index:
						draw_circle(c, 6.0, INK)
					else:
						draw_arc(c, 5.0, 0.0, TAU, 16, Color(INK, 0.7), 2.0, true)
			else:
				draw_string(font, Vector2(w * 0.5 - 40, foot + 8), "%d / %d" % [index + 1, count], HORIZONTAL_ALIGNMENT_CENTER, 100, 26, INK)


## A piece of card taped onto the page (photos, sketches).
class Card:
	extends Control

	func _init(card_size: Vector2) -> void:
		size = card_size
		pivot_offset = card_size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2(3, 4), size), Color(0.16, 0.1, 0.04, 0.3))
		draw_rect(Rect2(Vector2.ZERO, size), CARD)
		draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.12), false, 1.0)
		draw_set_transform(Vector2(size.x * 0.2, 0), deg_to_rad(-7.0))
		draw_rect(Rect2(-32, -11, 64, 22), TAPE)
		draw_set_transform(Vector2(size.x * 0.8, 0), deg_to_rad(6.0))
		draw_rect(Rect2(-30, -11, 60, 22), TAPE)
		draw_set_transform(Vector2.ZERO)


## A pencil sketch of a boss on a taped card.
class Sketch:
	extends Card

	var art: String

	func _init(boss_art: String) -> void:
		super(Vector2(120, 140))
		art = boss_art

	func _draw() -> void:
		super()
		var c := Vector2(60, 72)
		var ink := Color(0.23, 0.18, 0.14)
		match art:
			"splitter":
				draw_arc(c, 40.0, 0.0, TAU, 40, ink, 2.4, true)
				draw_arc(c, 23.0, 0.0, TAU, 32, ink, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-4, -40), c + Vector2(4, -22), c + Vector2(-6, -8),
						c + Vector2(6, 8), c + Vector2(-4, 24), c + Vector2(2, 40)]), ink, 2.4, true)
			"clock":
				draw_arc(c, 38.0, 0.0, TAU, 40, ink, 2.4, true)
				for k in 12: # hour marks
					var a := TAU * k / 12.0
					draw_line(c + Vector2.from_angle(a) * 33.0, c + Vector2.from_angle(a) * 37.0, ink, 1.6, true)
				draw_set_transform(c + Vector2(-10, -6), 0.0, Vector2(0.75, 1.2))
				draw_circle(Vector2.ZERO, 4.5, ink)
				draw_set_transform(c + Vector2(10, -6), 0.0, Vector2(0.75, 1.2))
				draw_circle(Vector2.ZERO, 4.5, ink)
				draw_set_transform(Vector2.ZERO)
			"collector":
				for i in 24:
					var a := TAU * i / 24.0
					draw_arc(c, 40.0, a, a + TAU / 48.0, 4, ink, 2.4, true)
				draw_arc(c, 31.0, 0.0, TAU, 36, ink, 2.0, true)
				draw_arc(c + Vector2(-4, -4), 12.0, 0.0, TAU, 24, ink, 2.4, true)
				draw_line(c + Vector2(5, 5), c + Vector2(18, 18), ink, 3.0, true)
			_:
				draw_arc(c, 38.0, 0.0, TAU, 40, ink, 2.4, true)
				draw_arc(c, 20.0, 0.0, TAU, 32, ink, 2.0, true)


## A pencil rubbing of a strange coin, with its year.
class Rubbing:
	extends Control

	var year: String

	func _init(coin_year: String, tilt: float) -> void:
		year = coin_year
		custom_minimum_size = Vector2(98, 98)
		size = custom_minimum_size
		pivot_offset = size * 0.5
		rotation = deg_to_rad(tilt)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 46.0
		var lead := Color(0.17, 0.13, 0.1, 0.3)
		var k := -r * 2.0
		while k < r * 2.0: # diagonal pencil strokes, clipped to the coin
			var n := Vector2(1, 1).normalized()
			var off := k / sqrt(2.0)
			var half_sq := r * r - off * off
			if half_sq > 0.0:
				var half := sqrt(half_sq)
				var mid := c + Vector2(-n.y, n.x) * off
				draw_line(mid - n * half, mid + n * half, lead, 1.0)
			k += 4.0
		draw_arc(c, r, 0.0, TAU, 48, Color(0.17, 0.13, 0.1, 0.65), 2.0, true)
		draw_arc(c, r - 7.0, 0.0, TAU, 48, Color(0.17, 0.13, 0.1, 0.35), 1.0, true)
		if year != "":
			var font := StoryJournal.hand(true)
			var w := font.get_string_size(year, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			draw_rect(Rect2(c.x - w * 0.5 - 4, c.y - 16, w + 8, 26), PAPER)
			draw_string(font, Vector2(c.x - w * 0.5, c.y + 6), year, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)


## The journal's front cover, hinged at the spine: tooled leather with a
## gilt border and title. Shown while the journal is closed.
class FrontCover:
	extends Control

	const GILT := Color(0.8, 0.64, 0.34)

	func _init() -> void:
		position = COVER.position
		size = COVER.size
		pivot_offset = Vector2(0, size.y * 0.5)
		mouse_filter = Control.MOUSE_FILTER_STOP # closed: nothing inside can be pressed

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = LEATHER.lightened(0.04)
		box.corner_radius_top_left = 10
		box.corner_radius_bottom_left = 10
		box.corner_radius_top_right = 18
		box.corner_radius_bottom_right = 18
		box.border_color = Color(0.14, 0.09, 0.05)
		box.set_border_width_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		# The spine's crease and stitching.
		draw_rect(Rect2(0, 0, 30, size.y), Color(0, 0, 0, 0.22))
		draw_dashed_line(Vector2(18, 14), Vector2(18, size.y - 14), Color(0.54, 0.42, 0.29, 0.6), 2.0, 8.0)
		# Gilt frame with corner diamonds.
		var outer := Rect2(Vector2(58, 34), size - Vector2(92, 68))
		var inner := outer.grow(-9.0)
		draw_rect(outer, Color(GILT, 0.75), false, 2.0)
		draw_rect(inner, Color(GILT, 0.45), false, 1.0)
		for corner: Vector2 in [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]:
			draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -9), corner + Vector2(9, 0), corner + Vector2(0, 9), corner + Vector2(-9, 0)]), GILT)
		var font := StoryJournal.hand(true)
		var mid := outer.get_center()
		_centered(font, "The Ghost's", 38, mid + Vector2(0, -50), Color(GILT, 0.85))
		_centered(font, "Journal", 92, mid + Vector2(0, 40), GILT)
		draw_line(mid + Vector2(-90, 78), mid + Vector2(90, 78), Color(GILT, 0.6), 2.0)

	func _centered(font: Font, text: String, font_size: int, at: Vector2, color: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, at + Vector2(-w * 0.5 + 1.5, 2.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.45))
		draw_string(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
