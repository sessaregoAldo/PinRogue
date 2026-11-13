class_name WorkshopPanel
extends VBoxContainer
## Story mode's coin shop. Coins (earned from boss damage in story runs) unlock
## spare parts, which can then show up as choices during story runs.
## Prices live in StoryData.PART_PRICES. Call refresh() when shown.

const WIDTH := 480.0
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)
const DIM := Color(0.6, 0.65, 0.8)

var _coins: Label
var _list: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0)
	_coins = Label.new()
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins.add_theme_font_size_override("font_size", 22)
	_coins.add_theme_color_override("font_color", GOLD)
	_coins.visible = false # the menu shows the coins in the corner (CoinBadge)
	add_child(_coins)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, 620)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func refresh() -> void:
	_coins.text = "%d coins" % Story.coins
	for child in _list.get_children():
		child.queue_free()
	var for_sale: Array[Dictionary] = []
	var owned: Array[Dictionary] = []
	for part: Dictionary in PowerupManager.POWERUPS:
		if part.get("disabled", false):
			continue
		if Story.is_unlocked(part["id"]):
			owned.append(part)
		elif Story.price(part["id"]) >= 0:
			for_sale.append(part)
	for_sale.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Story.price(a["id"]) < Story.price(b["id"]))
	if for_sale.is_empty():
		_list.add_child(_text("Every part is yours. The shelves are empty.", 17, SOFT))
	for part in for_sale:
		_list.add_child(_row(part, false))
	if not owned.is_empty():
		_list.add_child(_text("Already in the machine", 15, DIM))
		for part in owned:
			_list.add_child(_row(part, true))


func _row(part: Dictionary, owned: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.16, 0.92)
	style.border_color = Color(part["color"], 0.25 if owned else 0.6)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var tier_color: Color = PowerupManager.TIER_COLORS.get(part["tier"], SOFT)
	info.add_child(_text("%s   %s" % [part["title"], str(part["tier"]).to_upper()], 18, Color(part["color"]) if not owned else SOFT))
	var desc := _text(str(part["desc"]), 13, DIM)
	desc.custom_minimum_size = Vector2(WIDTH - 170.0, 0)
	info.add_child(desc)
	if owned:
		var tag := _text("Owned", 15, Color(tier_color, 0.7))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(tag)
	else:
		var cost := Story.price(part["id"])
		var buy := Button.new()
		buy.text = "%d coins" % cost
		buy.custom_minimum_size = Vector2(104, 44)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.add_theme_font_size_override("font_size", 16)
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = Story.coins < cost
		buy.tooltip_text = "" if not buy.disabled else "%d more coins needed" % (cost - Story.coins)
		buy.pressed.connect(_buy.bind(str(part["id"])))
		row.add_child(buy)
	return card


func _buy(part_id: String) -> void:
	if Story.buy(part_id):
		Sfx.play("powerup")
		refresh()
	else:
		Sfx.play("warning")


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
