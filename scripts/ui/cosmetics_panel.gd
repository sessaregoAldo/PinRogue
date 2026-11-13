class_name CosmeticsPanel
extends VBoxContainer
## Story menu > Cosmetics: buy and equip flipper colors, bumper colors and
## table backgrounds with story coins (data in Cosmetics, ownership in Story).
##
## Items are grouped by part and sorted with the owned ones first. An item's
## icon is filled black until it is owned. Pointing at (or selecting) an item
## shows how the table would look in `preview`, a small table the menu puts in
## a corner of the screen. Click an item to select it, then Buy / Equip below.

const WIDTH := 480.0
const GOLD := Color(1.0, 0.85, 0.3)
const SOFT := Color(0.75, 0.8, 0.95)
const DIM := Color(0.6, 0.65, 0.8)
const TILE := Vector2(86, 104)
const SWATCH := 56.0

## The corner preview (a Control the menu positions; see CosmeticsPreview below).
var preview: CosmeticsPreview

var _scroll: ScrollContainer
var _list: VBoxContainer
var _selected_name: Label
var _action: Button
var _selected_group: String = ""
var _selected: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	preview = CosmeticsPreview.new()
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, 560)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_selected_name = Label.new()
	_selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_name.add_theme_font_size_override("font_size", 17)
	_selected_name.add_theme_color_override("font_color", SOFT)
	add_child(_selected_name)
	_action = Button.new()
	_action.custom_minimum_size = Vector2(240, 48)
	_action.add_theme_font_size_override("font_size", 20)
	_action.pressed.connect(_on_action)
	var row := CenterContainer.new()
	row.add_child(_action)
	add_child(row)


## Call when the page is shown.
func refresh() -> void:
	var keep_scroll := _scroll.scroll_vertical
	for child in _list.get_children():
		child.queue_free()
	for group: Array in Cosmetics.GROUPS:
		var group_id: String = group[0]
		var title := Label.new()
		title.text = group[1]
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", GOLD)
		_list.add_child(title)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_list.add_child(grid)
		var items := Cosmetics.items(group_id).duplicate()
		# Owned first (the one in use leading), then the rest by price.
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(group_id, a) < _rank(group_id, b))
		for it: Dictionary in items:
			grid.add_child(_tile(group_id, it))
	if _selected.is_empty():
		_selected_group = "flippers"
		_selected = Cosmetics.equipped("flippers")
	_update_action()
	preview.show_look({})
	_scroll.set_deferred("scroll_vertical", keep_scroll)


func _rank(group: String, it: Dictionary) -> float:
	if Story.is_equipped(group, it):
		return -2.0
	if Story.owns_cosmetic(it):
		return -1.0
	return float(it.get("price", 0))


func _tile(group: String, it: Dictionary) -> Button:
	var owned := Story.owns_cosmetic(it)
	var equipped := Story.is_equipped(group, it)
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.toggle_mode = false
	b.clip_contents = true
	var selected: bool = _selected_group == group and _selected.get("id", "") == it["id"]
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.09, 0.16, 0.92) if state == "normal" else Color(0.14, 0.16, 0.26, 0.95)
		box.border_color = GOLD if selected else (Color(1, 1, 1, 0.35) if state != "normal" else Color(1, 1, 1, 0.12))
		box.set_border_width_all(2 if selected else 1)
		box.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, box)
	# Icon: the item's color or picture when owned; black when not.
	var swatch := Control.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.position = Vector2((TILE.x - SWATCH) * 0.5, 8)
	swatch.size = Vector2(SWATCH, SWATCH)
	var texture: Texture2D = null
	if owned and it.has("image") and ResourceLoader.exists(it["image"]):
		texture = load(it["image"]) as Texture2D
	swatch.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, swatch.size)
		if not owned:
			swatch.draw_rect(rect, Color.BLACK)
		elif texture != null:
			swatch.draw_texture_rect(texture, rect, false)
		else:
			swatch.draw_rect(rect, it.get("color", Color.BLACK))
		swatch.draw_rect(rect, GOLD if equipped else Color(1, 1, 1, 0.45), false, 2.0))
	b.add_child(swatch)
	var name_label := _tile_label(str(it["name"]), 12, SOFT if owned else DIM, 68)
	b.add_child(name_label)
	var state_text := "In use" if equipped else ("Owned" if owned else "%d coins" % int(it["price"]))
	b.add_child(_tile_label(state_text, 11, GOLD if equipped or not owned else DIM, 84))
	b.pressed.connect(_select.bind(group, it))
	# Pointing at it (mouse) or moving onto it (keys) previews it.
	b.mouse_entered.connect(func() -> void: preview.show_look({group: it}, str(it["name"])))
	b.focus_entered.connect(func() -> void: preview.show_look({group: it}, str(it["name"])))
	b.mouse_exited.connect(_preview_selected)
	return b


func _tile_label(text: String, font_size: int, color: Color, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(2, y)
	label.size = Vector2(TILE.x - 4, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _select(group: String, it: Dictionary) -> void:
	Sfx.play("click")
	_selected_group = group
	_selected = it
	refresh()
	_preview_selected()


func _preview_selected() -> void:
	if _selected.is_empty():
		preview.show_look({})
	else:
		preview.show_look({_selected_group: _selected}, str(_selected["name"]))


func _update_action() -> void:
	if _selected.is_empty():
		_selected_name.text = ""
		_action.visible = false
		return
	_action.visible = true
	var group_title := ""
	for group: Array in Cosmetics.GROUPS:
		if group[0] == _selected_group:
			group_title = group[1]
	_selected_name.text = "%s  ·  %s" % [group_title, _selected["name"]]
	if Story.is_equipped(_selected_group, _selected):
		_action.text = "In use"
		_action.disabled = true
	elif Story.owns_cosmetic(_selected):
		_action.text = "Use"
		_action.disabled = false
	else:
		var cost := int(_selected["price"])
		_action.text = "Buy  ·  %d coins" % cost
		_action.disabled = Story.coins < cost
		if _action.disabled:
			_selected_name.text += "   (%d more coins needed)" % (cost - Story.coins)


func _on_action() -> void:
	if _selected.is_empty():
		return
	if Story.owns_cosmetic(_selected):
		Story.equip_cosmetic(_selected_group, _selected)
		Sfx.play("click")
	elif Story.buy_cosmetic(_selected_group, _selected):
		Sfx.play("powerup")
	else:
		Sfx.play("warning")
		return
	refresh()
	_preview_selected()


## A small table showing a look: what is equipped, with the items in `look`
## (group -> item) swapped in.
class CosmeticsPreview:
	extends Control

	## Drawn at SIZE, shown scaled by SCALE (small enough to clear the page).
	const SIZE := Vector2(150, 236)
	const SCALE := 0.82
	var _look: Dictionary = {}
	var _caption: String = ""
	var _texture: Texture2D = null

	func _init() -> void:
		custom_minimum_size = SIZE * SCALE
		size = SIZE * SCALE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_look(look: Dictionary, caption: String = "") -> void:
		_look = look
		_caption = caption
		var background: Dictionary = _look.get("background", Cosmetics.equipped("background"))
		_texture = null
		if background.has("image") and ResourceLoader.exists(background["image"]):
			_texture = load(background["image"]) as Texture2D
		queue_redraw()

	func _draw() -> void:
		var flipper_c: Color = (_look.get("flippers", Cosmetics.equipped("flippers")) as Dictionary).get("color", Palette.FLIPPER)
		var bumper_c: Color = (_look.get("bumpers", Cosmetics.equipped("bumpers")) as Dictionary).get("color", Palette.BUMPER)
		var background: Dictionary = _look.get("background", Cosmetics.equipped("background"))
		var field := Rect2(4, 4, SIZE.x - 8, SIZE.y - 30)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SCALE)
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.02, 0.02, 0.05, 0.95))
		if _texture != null:
			var tex_size := _texture.get_size()
			var scale_by := maxf(field.size.x / tex_size.x, field.size.y / tex_size.y)
			var shown := field.size / scale_by
			draw_texture_rect_region(_texture, field, Rect2((tex_size - shown) * 0.5, shown))
			draw_rect(field, Color(0.02, 0.02, 0.05, 0.45))
		else:
			draw_rect(field, background.get("color", Color(0.07, 0.08, 0.16)))
		# Walls
		var wall := Color(0.72, 0.78, 0.95)
		draw_rect(field, wall, false, 2.0)
		# Two bumpers and the boss
		for p: Vector2 in [Vector2(46, 58), Vector2(104, 58)]:
			draw_circle(p, 13.0, bumper_c.darkened(0.5))
			draw_circle(p, 11.0, bumper_c)
			draw_circle(p, 6.0, bumper_c.darkened(0.3))
			draw_arc(p, 11.0, 0.0, TAU, 24, Color.WHITE, 1.2, true)
		draw_circle(Vector2(75, 100), 15.0, Palette.BOSS_START.darkened(0.4))
		draw_circle(Vector2(75, 100), 13.0, Palette.BOSS_START)
		draw_arc(Vector2(75, 100), 13.0, 0.0, TAU, 24, Color.WHITE, 1.2, true)
		# Flippers (left at rest, right raised) and a ball
		_flipper(Vector2(40, 176), deg_to_rad(28.0), flipper_c)
		_flipper(Vector2(110, 176), PI + deg_to_rad(28.0), flipper_c)
		draw_circle(Vector2(84, 150), 5.0, Color(0.85, 0.87, 0.92))
		# Caption
		var font := ThemeDB.fallback_font
		var text := _caption if _caption != "" else "Your table"
		draw_string(font, Vector2(0, SIZE.y - 8), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 13, Color(1.0, 0.85, 0.3))
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(1.0, 0.85, 0.3, 0.7), false, 1.5)

	func _flipper(pivot: Vector2, angle: float, c: Color) -> void:
		var tip := pivot + Vector2.from_angle(angle) * 30.0
		draw_line(pivot, tip, c.darkened(0.4), 10.0, true)
		draw_line(pivot, tip, c, 7.0, true)
		draw_circle(pivot, 5.5, c)
		draw_circle(tip, 3.5, c)
		draw_circle(pivot, 2.0, Color(0, 0, 0, 0.5))
