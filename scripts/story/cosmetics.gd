class_name Cosmetics
extends RefCounted
## Cosmetics bought with story coins (Story menu > Cosmetics): flipper colors,
## bumper colors and table backgrounds. Looks only: nothing here changes how
## the game plays, so they apply in every mode.
##
## Background pictures: any .png / .jpg / .webp placed in assets/backgrounds/
## shows up in the shop as a background (see the README in that folder).
## What the player owns and has equipped is saved by the Story autoload.

const BACKGROUND_DIR := "res://assets/backgrounds/"
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const IMAGE_PRICE := 60
## Shop sections, in order: [group id, title].
const GROUPS: Array[Array] = [["flippers", "Flippers"], ["bumpers", "Bumpers"], ["background", "Table backgrounds"]]

## The first item of each group is the stock look: free and always owned.
const FLIPPERS: Array[Dictionary] = [
	{"id": "flipper_azure", "name": "Azure", "color": Color(0.28, 0.56, 1.0), "price": 0},
	{"id": "flipper_crimson", "name": "Crimson", "color": Color(0.92, 0.22, 0.28), "price": 25},
	{"id": "flipper_gold", "name": "Gold", "color": Color(1.0, 0.8, 0.25), "price": 25},
	{"id": "flipper_emerald", "name": "Emerald", "color": Color(0.25, 0.85, 0.5), "price": 25},
	{"id": "flipper_violet", "name": "Violet", "color": Color(0.7, 0.45, 1.0), "price": 25},
	{"id": "flipper_bone", "name": "Bone", "color": Color(0.92, 0.9, 0.82), "price": 35},
]
const BUMPERS: Array[Dictionary] = [
	{"id": "bumper_cyan", "name": "Cyan", "color": Color(0.2, 0.8, 1.0), "price": 0},
	{"id": "bumper_magenta", "name": "Magenta", "color": Color(1.0, 0.35, 0.8), "price": 25},
	{"id": "bumper_lime", "name": "Lime", "color": Color(0.65, 1.0, 0.3), "price": 25},
	{"id": "bumper_amber", "name": "Amber", "color": Color(1.0, 0.65, 0.2), "price": 25},
	{"id": "bumper_ice", "name": "Ice", "color": Color(0.8, 0.95, 1.0), "price": 35},
]
const BACKGROUNDS: Array[Dictionary] = [
	{"id": "bg_midnight", "name": "Midnight", "color": Color(0.07, 0.08, 0.16), "price": 0},
	{"id": "bg_felt", "name": "Green felt", "color": Color(0.05, 0.16, 0.11), "price": 40},
	{"id": "bg_burgundy", "name": "Burgundy", "color": Color(0.17, 0.05, 0.08), "price": 40},
	{"id": "bg_charcoal", "name": "Charcoal", "color": Color(0.1, 0.1, 0.11), "price": 40},
	{"id": "bg_royal", "name": "Royal purple", "color": Color(0.12, 0.06, 0.2), "price": 40},
]

static var _image_items: Array[Dictionary] = []
static var _images_scanned: bool = false


## All items of a group. Each: {id, name, price, color} or, for a picture
## background, {id, name, price, image (path)}.
static func items(group: String) -> Array[Dictionary]:
	match group:
		"flippers":
			return FLIPPERS
		"bumpers":
			return BUMPERS
		"background":
			var out: Array[Dictionary] = []
			out.append_array(BACKGROUNDS)
			out.append_array(_background_images())
			return out
	return []


static func item(group: String, id: String) -> Dictionary:
	for it in items(group):
		if it["id"] == id:
			return it
	return items(group)[0]


static func default_id(group: String) -> String:
	return str(items(group)[0]["id"])


## Pictures found in assets/backgrounds/ (scanned once).
static func _background_images() -> Array[Dictionary]:
	if _images_scanned:
		return _image_items
	_images_scanned = true
	var dir := DirAccess.open(BACKGROUND_DIR)
	if dir == null:
		return _image_items
	var seen := {}
	for file in dir.get_files():
		# Exported builds list "name.png.import" in place of the picture itself.
		var file_name := file.trim_suffix(".import").trim_suffix(".remap")
		if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()) or seen.has(file_name):
			continue
		seen[file_name] = true
		_image_items.append({
			"id": "bg_image_" + file_name.get_basename().to_lower().replace(" ", "_"),
			"name": file_name.get_basename().replace("_", " ").replace("-", " ").capitalize(),
			"image": BACKGROUND_DIR + file_name,
			"price": IMAGE_PRICE,
		})
	_image_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return _image_items


# --- What is equipped ---------------------------------------------------------------

static func equipped(group: String) -> Dictionary:
	var story := _story()
	var id := default_id(group)
	if story != null:
		id = str(story.cosmetics_equipped.get(group, id))
	return item(group, id)


static func flipper_color() -> Color:
	return equipped("flippers").get("color", Palette.FLIPPER)


static func bumper_color() -> Color:
	return equipped("bumpers").get("color", Palette.BUMPER)


static func _story() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Story") if tree else null


## Dress a table: `look` maps group -> item (missing groups use what is equipped).
## Only parts in the stock colors are recolored, so special parts keep theirs.
static func apply(level: Node, look: Dictionary = {}) -> void:
	if level == null:
		return
	var flipper: Dictionary = look.get("flippers", equipped("flippers"))
	var bumper: Dictionary = look.get("bumpers", equipped("bumpers"))
	var background: Dictionary = look.get("background", equipped("background"))
	_dress(level, flipper.get("color", Palette.FLIPPER), bumper.get("color", Palette.BUMPER))
	if level is Level:
		var table := level as Level
		if background.has("image") and ResourceLoader.exists(background["image"]):
			table.background_texture = load(background["image"]) as Texture2D
		else:
			table.background_texture = null
			table.background_color = background.get("color", BACKGROUNDS[0]["color"])


static func _dress(node: Node, flipper_c: Color, bumper_c: Color) -> void:
	for child in node.get_children():
		if child is Flipper:
			if child.has_meta("stock_color") or child.color.is_equal_approx(Palette.FLIPPER):
				child.set_meta("stock_color", true)
				child.color = flipper_c
				child.queue_redraw()
		elif child is Bumper and not child is BossBumper:
			if child.has_meta("stock_color") or child.color.is_equal_approx(Palette.BUMPER):
				child.set_meta("stock_color", true)
				child.color = bumper_c
				child.queue_redraw()
		_dress(child, flipper_c, bumper_c)
