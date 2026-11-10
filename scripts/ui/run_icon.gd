class_name RunIcon
extends Control
## Small icon next to a name on the leaderboard: how the run ended.
##   star  = ended by choosing End Run after beating a boss
##   skull = ran out of balls
## Drawn in code (the default font has no star / skull glyphs).

const STAR := Color(1.0, 0.85, 0.3)
const BONE := Color(0.88, 0.9, 0.95)

var won: bool = false


func _init(is_won: bool = false, px: float = 16.0) -> void:
	won = is_won
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A name followed by its icon, for a leaderboard grid cell.
static func name_cell(player_name: String, is_won: bool, color: Color, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = player_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	row.add_child(RunIcon.new(is_won, font_size * 0.85))
	return row


## "(star) ended after a boss   (skull) out of balls" as two toggle buttons:
## click one to show only that kind of run, click it again for all runs.
## `on_filter` is called with "won", "lost" or "" (all).
static func legend(on_filter: Callable = Callable()) -> CenterContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for item: Array in [[true, "ended after a boss", "won"], [false, "out of balls", "lost"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Show only these runs (click again for all)"
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(1, 1, 1, 0.0 if state == "normal" else (0.06 if state == "hover" else 0.1))
			box.border_color = Color(1.0, 0.85, 0.3, 0.7) if state.contains("pressed") else Color(1, 1, 1, 0.0 if state == "normal" else 0.2)
			box.set_border_width_all(1)
			box.set_corner_radius_all(6)
			b.add_theme_stylebox_override(state, box)
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 5)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.position = Vector2(7, 4)
		inner.add_child(RunIcon.new(item[0], 13.0))
		var label := Label.new()
		label.text = item[1]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(label)
		b.add_child(inner)
		var text_w := ThemeDB.fallback_font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		b.custom_minimum_size = Vector2(13.0 + 5.0 + text_w + 14.0, 26.0)
		var ending: String = item[2]
		b.toggled.connect(func(on: bool) -> void:
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if on else Color(0.7, 0.75, 0.9))
			# Switching straight to the other filter unpresses this one first; only
			# report "all" when nothing is pressed any more.
			if on_filter.is_valid() and (on or group.get_pressed_button() == null):
				on_filter.call(ending if on else ""))
		row.add_child(b)
	var center := CenterContainer.new()
	center.add_child(row)
	return center


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if won:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, STAR)
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.6), 1.0, true)
		return
	# Skull: round cranium, jaw with teeth, dark eyes and nose.
	var dark := Color(0.05, 0.05, 0.1)
	draw_circle(c + Vector2(0, -r * 0.15), r * 0.78, BONE)
	draw_rect(Rect2(c.x - r * 0.45, c.y + r * 0.25, r * 0.9, r * 0.6), BONE)
	draw_circle(c + Vector2(-r * 0.33, -r * 0.12), r * 0.22, dark)
	draw_circle(c + Vector2(r * 0.33, -r * 0.12), r * 0.22, dark)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.12), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.1, r * 0.32)]), dark)
	for k in [-1, 0, 1]:
		var x: float = c.x + k * r * 0.2
		draw_line(Vector2(x, c.y + r * 0.5), Vector2(x, c.y + r * 0.85), dark, maxf(1.0, r * 0.08))
