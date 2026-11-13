extends CanvasLayer
## Score, balls, plunger charge, tilt warnings and game-over text.

var _score_label: Label
var _balls_label: RichTextLabel
var _message: Label
var _charge_bar: ProgressBar
var _warning_tween: Tween


func _ready() -> void:
	layer = 10
	_score_label = _make_label(Vector2(8, 4), Vector2(200, 30), 22, HORIZONTAL_ALIGNMENT_LEFT)
	_balls_label = RichTextLabel.new()
	_balls_label.bbcode_enabled = true
	_balls_label.scroll_active = false
	_balls_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_balls_label.position = Vector2(292, 4)
	_balls_label.size = Vector2(300, 32)
	_balls_label.add_theme_font_size_override("normal_font_size", 22)
	_balls_label.add_theme_constant_override("outline_size", 6)
	_balls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_balls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_balls_label)
	_message = _make_label(Vector2(0, 620), Vector2(600, 160), 44, HORIZONTAL_ALIGNMENT_CENTER)
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_charge_bar = ProgressBar.new()
	_charge_bar.position = Vector2(492, 36)
	_charge_bar.size = Vector2(100, 10)
	_charge_bar.max_value = 1.0
	_charge_bar.step = 0.0
	_charge_bar.show_percentage = false
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge_bar)
	_build_nudge_meter()

	GameManager.score_changed.connect(func(_s: float) -> void: _refresh())
	GameManager.balls_changed.connect(func(_b: int) -> void: _refresh())
	GameManager.round_continued.connect(func(_r: int) -> void: _refresh())
	GameManager.game_started.connect(_refresh)
	GameManager.plunger_charge_changed.connect(func(c: float) -> void: _charge_bar.value = c)
	GameManager.tilt_warning.connect(_on_tilt_warning)
	GameManager.tilted_changed.connect(_on_tilted_changed)
	# Game over / victory are shown by end_screen.gd (with the high-score entry).
	GameManager.game_over.connect(func(_s: float) -> void: _message.text = "")
	GameManager.victory.connect(func(_s: float) -> void: _message.text = "")
	GameManager.game_started.connect(func() -> void: _message.text = "")
	_banner = _make_label(Vector2(0, 470), Vector2(600, 60), 30, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_banner.modulate.a = 0.0
	_refresh()


var _banner: Label
var _banner_tween: Tween


## Big centered announcement that fades in and out (e.g. "ROUND 2 · Crossfire").
func show_banner(text: String, hold: float = 1.6) -> void:
	_banner.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2.ONE
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.35)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)

# --- Tilt meter bar -----------------------------------------------------------
# Fills with each nudge and drains over time. The gold tick marks WARNING;
# the right end is TILT.
const NUDGE_BAR_POS := Vector2(472, 52)
const NUDGE_BAR_SIZE := Vector2(120, 7)
var _nudge_fill: ColorRect
var _nudge_tick: ColorRect


func _build_nudge_meter() -> void:
	var bg := ColorRect.new()
	bg.position = NUDGE_BAR_POS
	bg.size = NUDGE_BAR_SIZE
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_nudge_fill = ColorRect.new()
	_nudge_fill.position = NUDGE_BAR_POS
	_nudge_fill.size = Vector2(0, NUDGE_BAR_SIZE.y)
	_nudge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_nudge_fill)
	_nudge_tick = ColorRect.new()
	_nudge_tick.size = Vector2(2, NUDGE_BAR_SIZE.y + 4)
	_nudge_tick.color = Color(1.0, 0.85, 0.3)
	_nudge_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_nudge_tick)


func _process(_delta: float) -> void:
	_update_nudge_meter()
	_update_ball_save()


var _save_label: Label


## "BALL SAVE 7s" under the score while the Ball Saver protects the current ball.
func _update_ball_save() -> void:
	if _save_label == null:
		_save_label = _make_label(Vector2(8, 30), Vector2(220, 20), 14, HORIZONTAL_ALIGNMENT_LEFT)
		_save_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	var left := GameManager.ball_save_remaining()
	var multi := GameManager.multiball_save_remaining()
	_save_label.visible = left > 0.0 or multi > 0.0
	if multi > 0.0:
		_save_label.text = "MULTIBALL SAVE %ds" % int(ceil(multi))
	elif left > 0.0:
		_save_label.text = "BALL SAVE %ds" % int(ceil(left))


func _update_nudge_meter() -> void:
	var limit := GameManager.TILT_LIMIT + GameManager.tilt_limit_bonus
	var warn := GameManager.TILT_WARN + GameManager.tilt_limit_bonus
	var ratio := 1.0 if GameManager.tilted else clampf(GameManager.tilt_meter / limit, 0.0, 1.0)
	_nudge_fill.size.x = NUDGE_BAR_SIZE.x * ratio
	_nudge_fill.color = Color(0.4, 0.9, 0.5).lerp(Color(1.0, 0.85, 0.3), clampf(ratio * 1.5, 0.0, 1.0)).lerp(Color(1, 0.25, 0.25), clampf((ratio - 0.66) * 3.0, 0.0, 1.0))
	_nudge_tick.position = NUDGE_BAR_POS + Vector2(NUDGE_BAR_SIZE.x * clampf(warn / limit, 0.0, 1.0) - 1.0, -2.0)


func _make_label(pos: Vector2, size: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _refresh() -> void:
	# Full digits up to 999,999,999, then the short form (1.25B) so it fits.
	var s := GameManager.score
	_score_label.text = "SCORE " + (str(int(s)) if s < 1.0e9 else GameManager.format_short(s))
	# Spare balls: the ball on the table doesn't count once it's launched.
	var spare := GameManager.spare_balls()
	var count := str(spare) if spare > 0 else "[color=#ff3b3b]0[/color]"
	if GameManager.game_mode == "story":
		_balls_label.text = "[right]CHAPTER %d   BALLS %s[/right]" % [GameManager.story_chapter + 1, count]
	else:
		_balls_label.text = "[right]ROUND %d   BALLS %s[/right]" % [GameManager.boss_round, count]


func _on_tilt_warning(_level: float) -> void:
	_message.text = "WARNING"
	_message.modulate = Color(1, 0.8, 0.2)
	if _warning_tween:
		_warning_tween.kill()
	_warning_tween = create_tween()
	_warning_tween.tween_interval(0.8)
	_warning_tween.tween_callback(func() -> void:
		if not GameManager.tilted and not GameManager.is_game_over:
			_message.text = "")


func _on_tilted_changed(is_tilted: bool) -> void:
	if _warning_tween:
		_warning_tween.kill()
	if is_tilted:
		_message.text = "TILT"
		_message.modulate = Color(1, 0.2, 0.2)
	elif not GameManager.is_game_over:
		_message.text = ""


