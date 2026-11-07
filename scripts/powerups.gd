class_name PowerupManager
extends Node2D
## Roguelike power-ups.
##
## When a rollover group is completed (see Rollover.grants_powerup), the game
## pauses and offers 3 random power-ups. The pick lasts for the rest of the run
## and stacks with earlier picks. Everything resets on restart.
##
## To add a power-up: add an entry to POWERUPS, handle its id in _apply(),
## and (optionally) in _is_available() and _status_lines().

const POWERUPS := [
	{"id": "extra_ball", "title": "Extra Ball", "icon": "+1",
		"desc": "One more ball for this run.", "color": Color(0.4, 1.0, 0.5), "weight": 0.8},
	{"id": "multiplier", "title": "x2 Multiplier", "icon": "x2",
		"desc": "Place it on a bumper or kicker. Hitting that part doubles your total score. 20 s cooldown.",
		"color": Color(0.45, 1.0, 0.9), "weight": 1.2},
	{"id": "gap_guard", "title": "Gap Guard", "icon": "==",
		"desc": "A barrier below the flipper gap pops the ball back up. Breaks after 2 saves.",
		"color": Color(0.4, 0.8, 1.0), "weight": 1.0},
	{"id": "outlane_guards", "title": "Outlane Guards", "icon": "| |",
		"desc": "Barriers across both outlanes. Each one saves the ball once.",
		"color": Color(0.6, 0.7, 1.0), "weight": 1.0},
	{"id": "steady_hands", "title": "Steady Hands", "icon": "~",
		"desc": "One more nudge allowed before TILT.", "color": Color(1.0, 0.85, 0.4), "weight": 0.7},
	{"id": "boss_crusher", "title": "Boss Crusher", "icon": "!!",
		"desc": "Boss hits deal +50% damage.", "color": Color(1.0, 0.4, 0.5), "weight": 0.8},
]

@export_group("Multiplier")
@export var multiplier_value: float = 2.0
@export var multiplier_cooldown: float = 20.0
@export_group("Gap Guard")
@export var gap_guard_a: Vector2 = Vector2(262, 1030)
@export var gap_guard_b: Vector2 = Vector2(298, 1030)
@export var gap_guard_saves: int = 2
@export var gap_guard_max: int = 4
@export_group("Outlane Guards")
@export var left_outlane_a: Vector2 = Vector2(26, 806)
@export var left_outlane_b: Vector2 = Vector2(55, 806)
@export var right_outlane_a: Vector2 = Vector2(505, 806)
@export var right_outlane_b: Vector2 = Vector2(534, 806)
@export var outlane_guard_saves: int = 1
@export var outlane_guard_max: int = 3

var _multipliers: Dictionary = {} # part (Node2D) -> {"mult": float, "ready_at": float}
var _clock: float = 0.0 # game time; doesn't advance while paused
var _pulse: float = 0.0
var _pending_choices: int = 0
var _gap_guard: Guard
var _left_guard: Guard
var _right_guard: Guard
var _steady_stacks: int = 0
var _crusher_stacks: int = 0

# Picker / placement state
var _offer: Array = []
var _placing: bool = false
var _place_targets: Array[Node2D] = []
var _place_index: int = 0

# UI
var _ui: CanvasLayer
var _choice_root: Control
var _cards_box: HBoxContainer
var _banner: Label
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the picker runs while the game is paused
	z_as_relative = false
	z_index = 45 # multiplier rings draw above tunnels
	_build_ui()
	GameManager.powerup_choice_requested.connect(_on_choice_requested)
	GameManager.part_hit.connect(_on_part_hit)
	GameManager.game_started.connect(_reset_run)
	_update_status()


func _process(delta: float) -> void:
	if not get_tree().paused:
		_clock += delta
	_pulse += delta
	if _placing or not _multipliers.is_empty():
		queue_redraw()


# --- Run lifecycle ------------------------------------------------------------

func _reset_run() -> void:
	_multipliers.clear()
	for guard in [_gap_guard, _left_guard, _right_guard]:
		if is_instance_valid(guard):
			guard.queue_free()
	_gap_guard = null
	_left_guard = null
	_right_guard = null
	_steady_stacks = 0
	_crusher_stacks = 0
	_pending_choices = 0
	_placing = false
	_choice_root.visible = false
	_banner.visible = false
	if get_tree().paused and not _pause_menu_open():
		get_tree().paused = false
	_update_status()
	queue_redraw()


func _pause_menu_open() -> bool:
	var menu := get_parent().get_node_or_null("PauseMenu") as CanvasLayer
	return menu != null and menu.visible


# --- Picking ------------------------------------------------------------------

func _on_choice_requested() -> void:
	if GameManager.is_game_over:
		return
	_pending_choices += 1
	if not GameManager.choosing:
		call_deferred("_open_choice") # not from inside a physics callback


func _open_choice() -> void:
	if _pending_choices <= 0 or GameManager.is_game_over:
		return
	_pending_choices -= 1
	_offer = _roll_offer(3)
	if _offer.is_empty():
		return
	GameManager.choosing = true
	get_tree().paused = true
	_fill_cards()
	_choice_root.visible = true
	Sfx.play("powerup")


func _roll_offer(count: int) -> Array:
	var pool := POWERUPS.filter(func(p: Dictionary) -> bool: return _is_available(p["id"]))
	var picked := []
	while picked.size() < count and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += float(p["weight"])
		var roll := randf() * total
		for i in pool.size():
			roll -= float(pool[i]["weight"])
			if roll <= 0.0 or i == pool.size() - 1:
				picked.append(pool[i])
				pool.remove_at(i)
				break
	return picked


func _is_available(id: String) -> bool:
	match id:
		"multiplier":
			return not _free_targets().is_empty()
		"gap_guard":
			return not is_instance_valid(_gap_guard) or _gap_guard.saves < gap_guard_max
		"outlane_guards":
			return not is_instance_valid(_left_guard) or not is_instance_valid(_right_guard) \
					or _left_guard.saves < outlane_guard_max or _right_guard.saves < outlane_guard_max
	return true


func _choose(index: int) -> void:
	if index < 0 or index >= _offer.size() or not _choice_root.visible:
		return
	_choice_root.visible = false
	Sfx.play("click")
	_apply(_offer[index]["id"])


func _apply(id: String) -> void:
	match id:
		"extra_ball":
			GameManager.add_extra_ball()
		"multiplier":
			_start_placement()
			return # finishes after the player places it
		"gap_guard":
			_gap_guard = _grow_guard(_gap_guard, gap_guard_a, gap_guard_b, Vector2.UP, 450.0, 8.0, 16.0, gap_guard_saves, gap_guard_max)
		"outlane_guards":
			_left_guard = _grow_guard(_left_guard, left_outlane_a, left_outlane_b, Vector2(0.35, -1.0), 620.0, 0.0, 0.0, outlane_guard_saves, outlane_guard_max)
			_right_guard = _grow_guard(_right_guard, right_outlane_a, right_outlane_b, Vector2(-0.35, -1.0), 620.0, 0.0, 0.0, outlane_guard_saves, outlane_guard_max)
		"steady_hands":
			_steady_stacks += 1
			GameManager.tilt_limit_bonus += 1.0
		"boss_crusher":
			_crusher_stacks += 1
			GameManager.boss_damage_mult += 0.5
	_finish_choice()


func _finish_choice() -> void:
	_placing = false
	_banner.visible = false
	_update_status()
	queue_redraw()
	if _pending_choices > 0 and not GameManager.is_game_over:
		_open_choice() # another lane set was completed meanwhile
		return
	GameManager.choosing = false
	get_tree().paused = false


# --- Guards -------------------------------------------------------------------

func _grow_guard(existing: Guard, a: Vector2, b: Vector2, kick_dir: Vector2, kick: float,
		side_min: float, side_max: float, saves: int, max_saves: int) -> Guard:
	if is_instance_valid(existing) and not existing.is_queued_for_deletion():
		existing.add_saves(saves, max_saves)
		return existing
	var guard := Guard.new()
	guard.point_a = a
	guard.point_b = b
	guard.kick_direction = kick_dir
	guard.kick_speed = kick
	guard.side_angle_min_deg = side_min
	guard.side_angle_max_deg = side_max
	guard.saves = mini(saves, max_saves)
	guard.process_mode = Node.PROCESS_MODE_PAUSABLE
	guard.changed.connect(_update_status)
	guard.broken.connect(_update_status.call_deferred)
	get_parent().add_child.call_deferred(guard)
	return guard


# --- Multipliers --------------------------------------------------------------

func _free_targets() -> Array[Node2D]:
	var all: Array[Node2D] = []
	_collect_targets(get_parent(), all)
	var out: Array[Node2D] = []
	for n in all:
		if not _multipliers.has(n):
			out.append(n)
	return out


func _collect_targets(node: Node, out: Array[Node2D]) -> void:
	if node is Bumper or node is Slingshot:
		out.append(node)
	for child in node.get_children():
		_collect_targets(child, out)


func _start_placement() -> void:
	_place_targets = _free_targets()
	if _place_targets.is_empty():
		_finish_choice()
		return
	# Start on the target closest to the table's center for a predictable cursor.
	_place_targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _target_center(a).x < _target_center(b).x)
	_place_index = 0
	var best := INF
	for i in _place_targets.size():
		var d := _target_center(_place_targets[i]).distance_to(Vector2(280, 400))
		if d < best:
			best = d
			_place_index = i
	_placing = true
	_banner.text = "Place your x%d multiplier\n<- / -> choose   ·   Enter / Space place   ·   or click a part" % int(multiplier_value)
	_banner.visible = true


func _confirm_placement() -> void:
	var target := _place_targets[_place_index]
	_multipliers[target] = {"mult": multiplier_value, "ready_at": 0.0}
	Sfx.play("multiplier")
	GameManager.popup("x%d placed" % int(multiplier_value), _target_center(target), Color(0.45, 1.0, 0.9), true)
	_finish_choice()


func _on_part_hit(part: Node) -> void:
	if not _multipliers.has(part):
		return
	var m: Dictionary = _multipliers[part]
	if _clock < float(m["ready_at"]):
		return
	m["ready_at"] = _clock + multiplier_cooldown
	GameManager.multiply_score(float(m["mult"]), _target_center(part))
	Sfx.play("multiplier")


func _target_center(node: Node2D) -> Vector2:
	if node is Slingshot:
		var s := node as Slingshot
		return s.to_global((s.corner_a + s.corner_b + s.corner_c) / 3.0)
	return node.global_position


func _target_radius(node: Node2D) -> float:
	if node is Bumper:
		return (node as Bumper).radius
	if node is Slingshot:
		var s := node as Slingshot
		var c := (s.corner_a + s.corner_b + s.corner_c) / 3.0
		return maxf(c.distance_to(s.corner_a), maxf(c.distance_to(s.corner_b), c.distance_to(s.corner_c))) * 0.75
	return 20.0


# --- Input (works while paused) -----------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _choice_root.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_1: _choose(0)
				KEY_2: _choose(1)
				KEY_3: _choose(2)
				_: return
			get_viewport().set_input_as_handled()
		return
	if not _placing:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("flipper_left"):
		_place_index = (_place_index - 1 + _place_targets.size()) % _place_targets.size()
		Sfx.play("click")
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("flipper_right"):
		_place_index = (_place_index + 1) % _place_targets.size()
		Sfx.play("click")
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("launch"):
		_confirm_placement()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := get_global_mouse_position()
		var best := -1
		var best_d := 60.0
		for i in _place_targets.size():
			var d := _target_center(_place_targets[i]).distance_to(mouse) - _target_radius(_place_targets[i])
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			_place_index = best
			_confirm_placement()
	else:
		return
	get_viewport().set_input_as_handled()


# --- World drawing (multiplier rings, placement cursor) -----------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for part in _multipliers:
		if not is_instance_valid(part):
			continue
		var m: Dictionary = _multipliers[part]
		var center := _target_center(part)
		var r := _target_radius(part) + 7.0
		var remaining := clampf((float(m["ready_at"]) - _clock) / multiplier_cooldown, 0.0, 1.0)
		var label := "x%d" % int(m["mult"])
		if remaining <= 0.0:
			var glow := 0.6 + 0.4 * sin(_pulse * 5.0)
			draw_arc(center, r, 0.0, TAU, 48, Color(0.45, 1.0, 0.9, glow), 3.0, true)
		else:
			draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 3.0, true)
			draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - remaining), 48, Color(0.45, 1.0, 0.9, 0.6), 3.0, true)
		var pos := center + Vector2(-r, -r - 4.0)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, Color(0.45, 1.0, 0.9) if remaining <= 0.0 else Color(0.7, 0.8, 0.85))
	if _placing:
		for i in _place_targets.size():
			var target := _place_targets[i]
			var center := _target_center(target)
			var r := _target_radius(target) + 8.0
			if i == _place_index:
				var grow := 3.0 * sin(_pulse * 8.0)
				draw_arc(center, r + grow, 0.0, TAU, 48, Color(1.0, 0.9, 0.3), 4.0, true)
				draw_string_outline(font, center + Vector2(-40, -r - 8.0), "x%d here" % int(multiplier_value), HORIZONTAL_ALIGNMENT_CENTER, 80, 15, 4, Color.BLACK)
				draw_string(font, center + Vector2(-40, -r - 8.0), "x%d here" % int(multiplier_value), HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(1.0, 0.9, 0.3))
			else:
				draw_arc(center, r, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)


# --- Status list --------------------------------------------------------------

func _update_status() -> void:
	if _status:
		_status.text = "\n".join(_status_lines())


func _status_lines() -> Array[String]:
	var lines: Array[String] = []
	for part in _multipliers:
		if is_instance_valid(part):
			var name_text: String = part.legend_name if "legend_name" in part else str(part.name)
			lines.append("x%d on %s" % [int(_multipliers[part]["mult"]), name_text])
	if is_instance_valid(_gap_guard) and not _gap_guard.is_queued_for_deletion() and _gap_guard.saves > 0:
		lines.append("Gap Guard  %s" % "o".repeat(_gap_guard.saves))
	var l := _left_guard.saves if is_instance_valid(_left_guard) and not _left_guard.is_queued_for_deletion() else 0
	var r := _right_guard.saves if is_instance_valid(_right_guard) and not _right_guard.is_queued_for_deletion() else 0
	if l > 0 or r > 0:
		lines.append("Outlane Guards  L%s R%s" % ["o".repeat(l) if l > 0 else "-", "o".repeat(r) if r > 0 else "-"])
	if _steady_stacks > 0:
		lines.append("Steady Hands +%d" % _steady_stacks)
	if _crusher_stacks > 0:
		lines.append("Boss Crusher +%d%%" % (_crusher_stacks * 50))
	return lines


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 15 # above the HUD, below the pause menu
	add_child(_ui)

	_status = Label.new()
	_status.position = Vector2(8, 34)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_status.add_theme_constant_override("outline_size", 4)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_status)

	_banner = Label.new()
	_banner.position = Vector2(0, 720)
	_banner.size = Vector2(600, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_ui.add_child(_banner)

	_choice_root = Control.new()
	_choice_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_root.visible = false
	_ui.add_child(_choice_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var title := Label.new()
	title.text = "CHOOSE A POWER-UP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	column.add_child(title)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 10)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards_box)
	var hint := Label.new()
	hint.text = "1 / 2 / 3, arrows + Enter, or click.\nIt lasts for the rest of the run."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	column.add_child(hint)


func _fill_cards() -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	var first: Button = null
	for i in _offer.size():
		var p: Dictionary = _offer[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(178, 240)
		card.focus_mode = Control.FOCUS_ALL
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.1, 0.11, 0.2, 0.97) if state != "hover" else Color(0.15, 0.17, 0.3, 0.97)
			style.border_color = (p["color"] as Color) if state != "normal" else (p["color"] as Color).darkened(0.4)
			style.set_border_width_all(4 if state == "focus" else 2)
			style.set_corner_radius_all(12)
			card.add_theme_stylebox_override(state, style)
		card.pressed.connect(_choose.bind(i))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12
		box.offset_right = -12
		box.offset_top = 12
		box.offset_bottom = -12
		box.add_theme_constant_override("separation", 10)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		_card_label(box, "[%d]" % (i + 1), 13, Color(0.6, 0.65, 0.8))
		_card_label(box, p["icon"], 34, p["color"])
		_card_label(box, p["title"], 19, Color.WHITE)
		var desc := _card_label(box, p["desc"], 13, Color(0.8, 0.85, 0.95))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(150, 0)
		_cards_box.add_child(card)
		if first == null:
			first = card
	if first:
		first.grab_focus.call_deferred()


func _card_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
