class_name DialogueBox
extends CanvasLayer
## Story dialogue. Two ways to talk:
##  - say(speaker, lines): a box the player taps / clicks / presses a key to
##    advance. Await it. The caller pauses the game around it.
##  - whisper(text): a short journal note that fades by itself and never stops play.
## The ghost writes on journal paper (ink on parchment); everyone else gets a
## plain dark box.

signal advanced

const PAPER := Color(0.93, 0.88, 0.74)
const INK := Color(0.17, 0.13, 0.1)
const DARK := Color(0.07, 0.08, 0.14, 0.95)
const GOLD := Color(1.0, 0.85, 0.3)
## Presses are ignored for this long after a line appears (no accidental skips).
const MIN_SHOW := 0.3
const BOX_WIDTH := 540.0
## Places a whisper note may sit (top edge y). It takes the one furthest from
## where the ball is and where it is heading, and hops away if the ball comes close.
const NOTE_SLOTS: Array[float] = [118.0, 300.0, 470.0, 640.0, 800.0]
const NOTE_WIDTH := 430.0
const GRAVITY := 1100.0

var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _hint: Label
var _note: PanelContainer
var _note_text: Label
var _note_tween: Tween
var _waiting: bool = false
## Set by the Skip button: every say() returns at once until the caller starts
## a new scene (begin_scene).
var skipping: bool = false
var _skip: Label
var _shown_at_ms: int = 0
var _voice: AudioStreamPlayer
var _note_slot: float = 640.0


func _ready() -> void:
	layer = 17 # above the HUD and spare-part picker, below the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.position = Vector2((600.0 - BOX_WIDTH) * 0.5, 700)
	_panel.custom_minimum_size = Vector2(BOX_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	box.add_child(_speaker)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BOX_WIDTH - 44.0, 0)
	_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_text)
	# Bottom row: Skip (for players who have read it all before) and the hint.
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_skip = Label.new()
	_skip.text = "  Skip  >>  "
	_skip.mouse_filter = Control.MOUSE_FILTER_IGNORE # presses are read in _input
	_skip.add_theme_font_size_override("font_size", 14)
	bottom.add_child(_skip)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	bottom.add_child(_hint)

	_voice = StoryVoice.make_player()
	add_child(_voice)

	_note = PanelContainer.new()
	_note.position = Vector2((600.0 - NOTE_WIDTH) * 0.5, _note_slot)
	_note.custom_minimum_size = Vector2(NOTE_WIDTH, 0)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_theme_stylebox_override("panel", _style(Color(PAPER, 0.85), Color(INK, 0.5), 10.0))
	_note.modulate.a = 0.0
	add_child(_note)
	_note_text = Label.new()
	_note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_text.custom_minimum_size = Vector2(NOTE_WIDTH - 30.0, 0)
	_note_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_text.add_theme_font_size_override("font_size", 15)
	_note_text.add_theme_color_override("font_color", INK)
	_note.add_child(_note_text)


## Show each line in turn; the player advances. Use with await.
## Voice-over: line n plays assets/voice/<voice_prefix>_<n>.mp3 if it exists
## (n counts from `first_number`).
func say(speaker: String, lines: Array, voice_prefix: String = "", first_number: int = 1) -> void:
	if skipping:
		return
	var ghost := speaker == StoryData.GHOST or speaker == StoryData.GHOST_UNKNOWN or speaker == ""
	_panel.add_theme_stylebox_override("panel", _style(PAPER, INK) if ghost else _style(DARK, Color(1, 1, 1, 0.35)))
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_speaker.add_theme_color_override("font_color", Color(0.45, 0.2, 0.12) if ghost else GOLD)
	_text.add_theme_color_override("font_color", INK if ghost else Color.WHITE)
	_hint.add_theme_color_override("font_color", Color(INK, 0.6) if ghost else Color(1, 1, 1, 0.55))
	_skip.add_theme_color_override("font_color", Color(0.45, 0.2, 0.12) if ghost else GOLD)
	_hint.text = "tap to continue" if _is_touch() else "click or press any key"
	_note.modulate.a = 0.0
	for i in lines.size():
		_text.text = str(lines[i])
		_panel.visible = true
		_panel.modulate.a = 0.0
		_panel.reset_size()
		# Just above the flippers, growing upward with longer lines; or at the
		# top when that would cover the ball.
		var height := _panel.get_combined_minimum_size().y
		var low := Rect2(_panel.position.x, 930.0 - height, BOX_WIDTH, height)
		var top := Rect2(low.position.x, 96.0, BOX_WIDTH, height)
		var use_top := _clearance(low) < 40.0 and _clearance(top) > _clearance(low)
		_panel.position.y = top.position.y if use_top else low.position.y
		_speak(("%s_%d" % [voice_prefix, first_number + i]) if voice_prefix != "" else "")
		var tween := create_tween()
		tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
		_shown_at_ms = Time.get_ticks_msec()
		_waiting = true
		await advanced
		_voice.stop()
		if skipping:
			break
	_waiting = false
	_panel.visible = false


## Call at the start of a conversation: Skip applies to one scene at a time.
func begin_scene() -> void:
	skipping = false


func is_talking() -> bool:
	return _waiting


## A short journal note over the table that fades by itself. It keeps out of
## the ball's way. Voice-over: assets/voice/<voice_id>.mp3 if it exists.
func whisper(text: String, hold: float = 4.0, voice_id: String = "") -> void:
	if _waiting:
		return
	_note_text.text = text
	_note.reset_size()
	_note_slot = _best_slot()
	_note.position.y = _note_slot
	var length := _speak(voice_id)
	hold = maxf(hold, length + 0.4) # stays up while the line is being spoken
	if _note_tween:
		_note_tween.kill()
	_note_tween = create_tween()
	_note_tween.tween_property(_note, "modulate:a", 1.0, 0.3)
	_note_tween.tween_interval(hold)
	_note_tween.tween_property(_note, "modulate:a", 0.0, 0.8)


func _process(_delta: float) -> void:
	# A visible note hops to a clearer spot when a ball gets close to it.
	if _note.modulate.a > 0.05 and not get_tree().paused:
		if _clearance(Rect2(_note.position, _note.size)) < 26.0:
			var slot := _best_slot()
			if not is_equal_approx(slot, _note_slot):
				_note_slot = slot
				_note.position.y = slot


## Plays a line's recording (if there is one). Returns its length in seconds.
func _speak(voice_id: String) -> float:
	_voice.stop()
	var stream := StoryVoice.stream_for(voice_id)
	if stream == null:
		return 0.0
	_voice.stream = stream
	_voice.play()
	return stream.get_length()


## Balls on the table: [position, velocity] each.
func _balls() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball != null and ball.in_play and ball.visible:
			out.append([ball.global_position, ball.linear_velocity])
	return out


## Distance from `rect` to the nearest point a ball is at now or will be in the
## next second (simple gravity arc). Large when no ball is in play.
func _clearance(rect: Rect2) -> float:
	var best := 9999.0
	for ball: Array in _balls():
		var pos: Vector2 = ball[0]
		var vel: Vector2 = ball[1]
		for step in 9:
			var t := step * 0.125
			var p := pos + vel * t + Vector2(0, 0.5 * GRAVITY * t * t)
			var nearest := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
			# Later points count a little less: the ball may well bounce before then.
			best = minf(best, p.distance_to(nearest) + t * 60.0)
	return best


## The note slot with the most room around the ball's path.
func _best_slot() -> float:
	var best_slot := _note_slot
	var best_room := -1.0
	var size := Vector2(NOTE_WIDTH, maxf(_note.get_combined_minimum_size().y, 50.0))
	for slot in NOTE_SLOTS:
		var room := _clearance(Rect2(Vector2(_note.position.x, slot), size))
		if is_equal_approx(slot, _note_slot):
			room += 20.0 # don't hop for a marginal gain
		if room > best_room:
			best_room = room
			best_slot = slot
	return best_slot


func _input(event: InputEvent) -> void:
	if not _waiting:
		return
	var press := false
	if event is InputEventKey:
		press = event.pressed and not event.echo
	elif event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventJoypadButton:
		press = event.pressed
	if not press:
		return
	get_viewport().set_input_as_handled() # a dialogue press never reaches the game
	# A click / tap on Skip ends the whole conversation.
	if (event is InputEventScreenTouch or event is InputEventMouseButton) \
			and _skip.get_global_rect().grow(8.0).has_point(event.position):
		Sfx.play("click")
		skipping = true
		advanced.emit()
		return
	if Time.get_ticks_msec() - _shown_at_ms < int(MIN_SHOW * 1000.0):
		return
	Sfx.play("click")
	advanced.emit()


func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() and (OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"))


func _style(bg: Color, border: Color, margin: float = 20.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.7
	style.content_margin_bottom = margin * 0.6
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	return style
