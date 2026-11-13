class_name JournalPanel
extends VBoxContainer
## The Journal the ghost writes in (story mode). Tabs: Story (pages revealed so
## far), Bosses (the people from his past), Parts (spare parts owned / still in
## the Workshop) and Coins (the strange coins collected).
## Shared by the main menu's Story page and the pause menu. Call refresh() when shown.

const PAPER := Color(0.93, 0.88, 0.74)
const INK := Color(0.17, 0.13, 0.1)
const FADED := Color(0.17, 0.13, 0.1, 0.6)
const RED_INK := Color(0.5, 0.16, 0.1)
const WIDTH := 480.0
const TABS: Array[String] = ["Story", "Bosses", "Parts", "Coins"]

var _tab: String = "Story"
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _page: VBoxContainer


## Parchment panel style used by everything journal-like.
static func paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color(0.4, 0.3, 0.2)
	style.set_border_width_all(2)
	style.border_width_left = 8 # the spine
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	return style


## An ink-on-paper label.
static func ink_label(text: String, font_size: int, color: Color = INK, width: float = WIDTH - 60.0) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(INK, 0.25)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	var group := ButtonGroup.new()
	for tab_name in TABS:
		var b := Button.new()
		b.text = tab_name
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(108, 38)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.3))
		b.pressed.connect(_show_tab.bind(tab_name))
		tabs.add_child(b)
		_tab_buttons[tab_name] = b
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", paper_style())
	add_child(paper)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH - 40.0, 560)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 10)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page)


func refresh() -> void:
	_show_tab(_tab, false)


func _show_tab(tab_name: String, click: bool = true) -> void:
	if click:
		Sfx.play("click")
	_tab = tab_name
	(_tab_buttons[tab_name] as Button).button_pressed = true
	for child in _page.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	match tab_name:
		"Story":
			_fill_story()
		"Bosses":
			_fill_bosses()
		"Parts":
			_fill_parts()
		"Coins":
			_fill_coins()


func _add(text: String, font_size: int, color: Color = INK) -> Label:
	var label := ink_label(text, font_size, color)
	_page.add_child(label)
	return label


func _fill_story() -> void:
	if not Story.intro_seen:
		_add("The pages are blank.", 20)
		_add("Start Story Mode and the journal will find you.", 16, FADED)
		return
	_add("Page one", 22, RED_INK)
	_add("If you are reading this, she has found you. Good. I had hoped somebody would come.", 17)
	_add("I built her and I am, I'm afraid, still in her. Be my hands. I'll be your instructions. Help me finish her, and perhaps she lets me go.", 17)
	_add("The coins she pays out are not mine. I never minted them. I would very much like to know who did.", 17)
	for i in StoryData.CHAPTERS.size():
		var ch: Dictionary = StoryData.CHAPTERS[i]
		_page.add_child(rule())
		if Story.is_beaten(ch["id"]):
			_add("Chapter %d: %s" % [int(ch["number"]), ch["title"]], 22, RED_INK)
			_add(str(ch["journal"]), 17)
			_add(str(ch["machine_change"]), 15, FADED)
		else:
			_add("Chapter %d" % int(ch["number"]), 22, RED_INK)
			_add("This page hasn't been written yet.", 16, FADED)
	_page.add_child(rule())
	_add(StoryData.MORE_SOON, 15, FADED)


func _fill_bosses() -> void:
	for ch: Dictionary in StoryData.CHAPTERS:
		if Story.is_beaten(ch["id"]):
			_add(str(ch["boss"]), 24, RED_INK)
			_add(str(ch["hint"]), 15, FADED)
			_add(str(ch["journal"]), 17)
			var best: Dictionary = Story.best.get(ch["id"], {})
			if not best.is_empty():
				_add("Best run: score %s, damage dealt %s" % [
						GameManager.format_number(float(best.get("score", 0.0))),
						GameManager.format_number(float(best.get("damage", 0.0)))], 15, FADED)
		else:
			_add("? ? ?", 24, RED_INK)
			_add("Someone from his past, still inside the machine.", 16, FADED)
		_page.add_child(rule())
	_add("Runs played: %d" % Story.attempts, 15, FADED)


func _fill_parts() -> void:
	_add("Spare parts the machine can offer in Story runs.", 15, FADED)
	var locked: Array[Dictionary] = []
	for part: Dictionary in PowerupManager.POWERUPS:
		if part.get("disabled", false):
			continue
		if Story.is_unlocked(part["id"]):
			_add("%s  (%s)" % [part["title"], part["tier"]], 19)
			_add(str(part["desc"]), 14, FADED)
		elif Story.price(part["id"]) >= 0:
			locked.append(part)
	if not locked.is_empty():
		_page.add_child(rule())
		_add("Still in the Workshop", 20, RED_INK)
		for part in locked:
			_add("%s  (%s)  ·  %d coins" % [part["title"], part["tier"], Story.price(part["id"])], 17, FADED)


func _fill_coins() -> void:
	_add("%d coins to spend  ·  %d found in all" % [Story.coins, Story.coins_earned], 19, RED_INK)
	if Story.coin_tray.is_empty():
		_add("No coins yet. She pays out for every dent you put in whoever is hiding in there, win or lose.", 16, FADED)
		return
	_add("None of these should exist.", 15, FADED)
	var tray := Story.coin_tray.duplicate()
	tray.reverse()
	for coin: Variant in tray:
		if coin is Dictionary:
			_page.add_child(rule())
			_add(str(coin.get("text", "")), 16)
