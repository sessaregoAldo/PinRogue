extends CanvasLayer
## Esc pause menu: Resume, Settings, Scoring legend, High Scores, Restart and
## Main Menu (both confirmed), Exit (desktop only). Also owns the R restart key
## so it can confirm first. Runs while the tree is paused (process_mode ALWAYS).

const BUTTON_SIZE := Vector2(260, 48)

var _pages: Array[VBoxContainer] = []
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _scoring_page: VBoxContainer
var _highscores_page: VBoxContainer
var _confirm_page: VBoxContainer
var _feedback_page: VBoxContainer
var _feedback: FeedbackPanel
var _resume_button: Button
var _confirm_yes_button: Button
var _confirm_title: Label
var _confirm_note: Label
var _confirm_hint: Label
var _settings: SettingsPanel
var _leaderboard: LeaderboardPanel
var _scoring_grid: GridContainer
var _scoring_footer: Label
## True when R opened the menu straight to the confirmation (Esc / Cancel then closes it).
var _opened_for_confirm: bool = false
## What the confirmation page confirms: "restart" or "menu".
var _confirm_mode: String = "restart"


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.choosing or GameManager.entering_name:
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		if GameManager.is_game_over:
			_set_open(false)
			GameManager.restart() # nothing to lose, no need to confirm
		elif not visible:
			_set_open(true)
			_opened_for_confirm = true
			_ask_confirm("restart")
		elif _confirm_page.visible and _confirm_mode == "restart":
			_do_confirm() # R again = confirm
		else:
			_ask_confirm("restart")
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not visible:
			_set_open(true)
		else:
			_back()


func _set_open(open: bool) -> void:
	visible = open
	get_tree().paused = open
	_opened_for_confirm = false
	if open:
		_show_page(_main_page)
	else:
		Sfx.save_settings()


func _show_page(page: VBoxContainer) -> void:
	for p in _pages:
		p.visible = p == page
	if page == _main_page:
		_resume_button.grab_focus()
	elif page == _settings_page:
		_settings.refresh()
		_settings.focus_first()
	elif page == _feedback_page:
		_feedback.refresh()
	elif page == _highscores_page:
		_leaderboard.refresh()
	elif page == _scoring_page:
		_fill_scoring()
	elif page == _confirm_page:
		_confirm_yes_button.grab_focus()


func _ask_confirm(mode: String) -> void:
	_confirm_mode = mode
	if mode == "menu":
		_confirm_title.text = "MAIN MENU?"
		_confirm_note.text = "Your current run will be lost."
		_confirm_yes_button.text = "Yes, leave"
		_confirm_hint.text = "Esc = cancel"
	else:
		_confirm_title.text = "RESTART?"
		_confirm_note.text = "Your current game will be lost."
		_confirm_yes_button.text = "Yes, restart"
		_confirm_hint.text = "R = confirm   ·   Esc = cancel"
	_show_page(_confirm_page)


## Esc / Back / Cancel: sub-page -> main page; main page -> close.
func _back() -> void:
	if _main_page.visible or (_confirm_page.visible and _opened_for_confirm):
		_set_open(false)
	else:
		if _settings_page.visible:
			Sfx.save_settings()
		_show_page(_main_page)


func _do_confirm() -> void:
	Sfx.play("click")
	_set_open(false)
	if _confirm_mode == "menu":
		var game := get_parent()
		if game and game.has_method("go_to_main_menu"):
			game.go_to_main_menu()
	else:
		GameManager.restart()


func _on_button(action: Callable) -> Callable:
	return func() -> void:
		Sfx.play("click")
		action.call()


# --- Scoring legend -----------------------------------------------------------

## Builds the legend from the parts actually on the table, so it stays correct
## when points are tuned in the inspector.
func _fill_scoring() -> void:
	for child in _scoring_grid.get_children():
		child.queue_free()
	for row in _legend_rows():
		_grid_label(row["label"], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_grid_label(row["note"], 14, Color(0.7, 0.75, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_grid_label(GameManager.format_number(row["points"]), 18, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	var table := _table()
	var boss := _find_boss(table)
	if boss:
		var how := "your current score" if boss.damage_mode == BossBumper.DamageMode.CURRENT_SCORE \
				else "%s" % GameManager.format_number(boss.score_value)
		_scoring_footer.text = "Boss bumper: %s HP left.\nEach hit deals damage equal to %s.\n" \
				% [GameManager.format_number(boss.hp), how]
	else:
		_scoring_footer.text = ""
	var bank := _find_bank(table)
	if bank:
		_scoring_footer.text += "\nButtons: light exactly the ones marked with a diamond\nfor +%d%% of your score.\nHit the gold button: it moves on. Clear all %d (%d left)\nfor score x%s.\n" \
				% [int(round(bank.match_bonus_ratio * 100.0)), bank.button_count(), bank.chase_remaining(), String.num(bank.chase_multiplier, 2)]
	_scoring_footer.text += "\nNothing scores while TILTed."


func _table() -> Node:
	return get_parent() if get_parent() else get_tree().current_scene


func _find_bank(node: Node) -> ButtonBank:
	if node is ButtonBank:
		return node
	for child in node.get_children():
		var found := _find_bank(child)
		if found:
			return found
	return null


func _find_boss(node: Node) -> BossBumper:
	if node is BossBumper:
		return node
	for child in node.get_children():
		var found := _find_boss(child)
		if found:
			return found
	return null


func _legend_rows() -> Array:
	var rows := {}
	var groups := {}
	_collect(_table(), rows, groups)
	var out := []
	for key in rows:
		var r: Dictionary = rows[key]
		var label: String = r["label"]
		if r["count"] > 1:
			label += "  ×%d" % r["count"]
		out.append({"label": label, "points": r["points"], "note": r["note"]})
	for key in groups:
		var g: Dictionary = groups[key]
		var noun: String = (g["name"] as String).to_lower() + "s"
		var label := ("Both %s lit" % noun) if g["count"] == 2 else ("All %d %s lit" % [g["count"], noun])
		out.append({"label": label, "points": g["bonus"], "note": "bonus"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["points"] > b["points"])
	return out


func _collect(node: Node, rows: Dictionary, groups: Dictionary) -> void:
	if node is Bumper:
		_add_row(rows, node.legend_name, node.score_value, "per hit")
	elif node is Slingshot:
		_add_row(rows, node.legend_name, node.score_value, "per kick")
	elif node is Tunnel:
		_add_row(rows, node.legend_name, node.score_value, "full ride")
	elif node is TargetButton:
		var owner_bank := node.get_parent() as ButtonBank
		_add_row(rows, owner_bank.legend_name if owner_bank else "Button", owner_bank.hit_points if owner_bank else 0, "per hit")
	elif node is Rollover:
		_add_row(rows, node.legend_name, node.score_value, "per pass")
		var g: Dictionary = groups.get(node.group_name, {"name": node.legend_name, "bonus": node.group_bonus, "count": 0})
		g["count"] += 1
		groups[node.group_name] = g
	for child in node.get_children():
		_collect(child, rows, groups)


func _add_row(rows: Dictionary, label: String, points: int, note: String) -> void:
	var key := "%s|%d|%s" % [label, points, note]
	if rows.has(key):
		rows[key]["count"] += 1
	else:
		rows[key] = {"label": label, "points": points, "note": note, "count": 1}


func _grid_label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if align == HORIZONTAL_ALIGNMENT_LEFT else Control.SIZE_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_scoring_grid.add_child(label)


# --- UI construction ----------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.2, 0.95)
	style.border_color = Color(0.72, 0.78, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var holder := VBoxContainer.new()
	panel.add_child(holder)

	# Main page
	_main_page = _make_page(holder, "PAUSED")
	_resume_button = _make_button(_main_page, "Resume", _on_button(func() -> void: _set_open(false)))
	_make_button(_main_page, "Settings", _on_button(func() -> void: _show_page(_settings_page)))
	_make_button(_main_page, "Scoring", _on_button(func() -> void: _show_page(_scoring_page)))
	_make_button(_main_page, "High Scores", _on_button(func() -> void: _show_page(_highscores_page)))
	_make_button(_main_page, "Feedback", _on_button(func() -> void: _show_page(_feedback_page)))
	_make_button(_main_page, "Restart", _on_button(func() -> void: _ask_confirm("restart")))
	_make_button(_main_page, "Main Menu", _on_button(func() -> void: _ask_confirm("menu")))
	if not OS.has_feature("web"): # a browser tab cannot be closed by the game
		_make_button(_main_page, "Exit", func() -> void:
			Sfx.quit_game())

	# High scores page
	_highscores_page = _make_page(holder, "HIGH SCORES")
	_leaderboard = LeaderboardPanel.new()
	_highscores_page.add_child(_leaderboard)
	_make_button(_highscores_page, "Back", _on_button(_back))

	# Settings page
	_feedback_page = _make_page(holder, "FEEDBACK")
	_feedback = FeedbackPanel.new()
	_feedback_page.add_child(_feedback)
	_make_button(_feedback_page, "Back", _on_button(_back))

	_settings_page = _make_page(holder, "SETTINGS")
	_settings = SettingsPanel.new()
	_settings_page.add_child(_settings)
	_make_button(_settings_page, "Back", _on_button(_back))

	# Scoring page
	_scoring_page = _make_page(holder, "SCORING")
	_scoring_grid = GridContainer.new()
	_scoring_grid.columns = 3
	_scoring_grid.add_theme_constant_override("h_separation", 16)
	_scoring_grid.add_theme_constant_override("v_separation", 6)
	_scoring_grid.custom_minimum_size = Vector2(380, 0)
	_scoring_page.add_child(_scoring_grid)
	_scoring_footer = Label.new()
	_scoring_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoring_footer.add_theme_font_size_override("font_size", 15)
	_scoring_footer.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	_scoring_page.add_child(_scoring_footer)
	_make_button(_scoring_page, "Back", _on_button(_back))

	# Confirmation page (restart or main menu)
	_confirm_page = _make_page(holder, "RESTART?")
	_confirm_title = _confirm_page.get_child(0)
	_confirm_note = _make_note(_confirm_page, "")
	_confirm_yes_button = _make_button(_confirm_page, "Yes", _do_confirm)
	_make_button(_confirm_page, "Cancel", _on_button(_back))
	_confirm_hint = _make_note(_confirm_page, "")


func _make_page(holder: Control, title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	page.add_child(label)
	holder.add_child(page)
	_pages.append(page)
	return page


func _make_note(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	parent.add_child(label)
	return label


func _make_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button
