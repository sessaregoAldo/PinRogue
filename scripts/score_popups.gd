extends Node2D
## Floating, fading text (e.g. "+100") where points are earned.
## Listens to GameManager.popup_requested; toggled by GameManager.show_score_popups
## (Settings page of the pause menu).

const LIFETIME := 0.9 # seconds
const RISE := 42.0 # pixels the text floats up over its life

var _items: Array[Dictionary] = []


func _ready() -> void:
	z_as_relative = false
	z_index = 60 # above tunnels and the boss health bar
	GameManager.popup_requested.connect(_on_popup_requested)
	GameManager.game_started.connect(func() -> void:
		_items.clear()
		queue_redraw())


func _on_popup_requested(text: String, world_pos: Vector2, color: Color, big: bool) -> void:
	if not GameManager.show_score_popups:
		return
	_items.append({"text": text, "pos": world_pos, "color": color, "size": 24 if big else 17, "age": 0.0})
	if _items.size() > 40:
		_items.pop_front()


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	for item in _items:
		item["age"] += delta
	_items = _items.filter(func(item: Dictionary) -> bool: return item["age"] < LIFETIME)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for item in _items:
		var t: float = item["age"] / LIFETIME
		var alpha := 1.0 - t * t
		var font_size: int = item["size"]
		var text: String = item["text"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var rise := RISE * (1.0 - pow(1.0 - t, 2.0)) # ease out
		var pos: Vector2 = item["pos"] + Vector2(-width * 0.5, -12.0 - rise)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8 * alpha))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(item["color"], alpha))
