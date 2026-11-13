class_name StoryDirector
extends Node
## Runs a story-mode chapter (added by game.gd when GameManager.game_mode is
## "story"). One chapter = one machine, in two phases:
##   1. "plain": a normal game. The center bumper looks ordinary and has a
##      health bar (the first Endless boss's HP).
##   2. "boss":  at 0 the boss reveals itself: new art, battle music, HP scaled
##      from the player's score (StoryData.BOSS_HP_SCORE_FACTOR) and its gimmick.
## Beating the boss plays a slow-motion close-up, then the machine tilts in
## silence and the Journal's Victory page opens. Running out of balls opens the
## Defeat page. Either way the run pays coins (StoryData.COINS_*).
## Content (lines, numbers) lives in StoryData; progress in the Story autoload.

const SLOWMO_SCALE := 0.06
const SLOWMO_SECONDS := 4.0
## The battle music fades to nothing over the end of the slow motion.
const MUSIC_FADE_SECONDS := 3.0
const SILENT_TILT_SECONDS := 2.6
## After the silent tilt a slow, sad song starts; the Victory page follows.
const QUIET_SONG_LEAD_SECONDS := 2.2
const CLOSE_UP_ZOOM := 2.3

var game: Node # game.gd
var chapter: Dictionary = {}
## "plain", "reveal", "boss" or "over".
var phase: String = "plain"
## This run's numbers, shown on the result page.
var stats: Dictionary = {}

var _dialogue: DialogueBox
var _result: StoryResult
var _boss: BossBumper
var _gimmick: SplitterBoss
var _phase_one_max: float = 1.0
var _boss_max: float = 1.0
var _revealed: bool = false
var _whispered: Dictionary = {}
var _run: int = 0 # bumped on every (re)start: stale sequences stop
var _fx_layer: CanvasLayer
var _face: Control
var _face_alpha: float = 0.0
var _face_on: bool = false
var _flash: ColorRect
var _journal_card: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps talking while the game is paused
	chapter = StoryData.chapter(GameManager.story_chapter)
	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_result = StoryResult.new()
	add_child(_result)
	_result.retry_pressed.connect(_on_retry)
	_result.menu_pressed.connect(_on_to_menu)
	_build_fx()
	GameManager.game_started.connect(_on_run_started)
	GameManager.game_over.connect(_on_game_over)
	GameManager.ball_lost.connect(_on_ball_lost)
	GameManager.part_hit.connect(_on_part_hit)
	GameManager.tilted_changed.connect(_on_tilted_changed)
	GameManager.powerup_choice_requested.connect(func(_tier: String) -> void: stats["parts"] = int(stats.get("parts", 0)) + 1)
	if game and game.has_signal("nudged"):
		game.nudged.connect(func(_dir: Vector2) -> void: stats["nudges"] = int(stats.get("nudges", 0)) + 1)


# --- Run start ----------------------------------------------------------------------

## A new attempt (the level is already loaded: game.gd hears game_started first).
func _on_run_started() -> void:
	_run += 1
	phase = "plain"
	_revealed = false
	_whispered.clear()
	stats = {"damage": 0.0, "boss_hits": 0, "bumper_hits": 0, "nudges": 0, "tilts": 0,
			"balls_lost": 0, "parts": 0, "time": 0.0, "splits": 0}
	Engine.time_scale = 1.0
	Sfx.unsilence()
	Sfx.end_battle_music()
	_result.close()
	_face_on = false
	_face.visible = false
	_journal_card.visible = false
	if game.has_method("reset_camera"):
		game.reset_camera(0.0)
	if is_instance_valid(_gimmick):
		_gimmick.queue_free()
	_gimmick = null
	_boss = game.level.boss() if game.level else null
	if _boss:
		_boss.story_controlled = true
		# A beaten boss keeps his face: the cap stays cracked on later visits.
		_boss.art = str(chapter["art"]) if Story.is_beaten(chapter["id"]) else "plain"
		_boss.set_hp(StoryData.PHASE_ONE_HP)
		_phase_one_max = _boss.max_hp
		_boss.depleted.connect(_on_boss_depleted)
		_boss.damaged.connect(_on_boss_damaged)
	if Story.is_beaten(chapter["id"]) and game.level:
		game.level.modulate = chapter.get("tint", Color.WHITE)
	if not Story.intro_seen:
		_intro(_run) # shows the chapter banner when it ends
	else:
		_chapter_banner()
		_whisper_later(_run, StoryData.WHISPER_START, "whisper_start")


func _chapter_banner() -> void:
	if "hud" in game:
		game.hud.show_banner("CHAPTER %d  ·  %s" % [int(chapter["number"]), chapter["title"]], 2.0)


func _whisper_later(run: int, text: String, voice_id: String) -> void:
	await get_tree().create_timer(2.6, true, false, true).timeout
	if run == _run and phase == "plain":
		_dialogue.whisper(text, 4.0, voice_id)


## First ever story run: Sal hands the machine over, the face, the Journal.
func _intro(run: int) -> void:
	# Let the scene's fade-in finish before pausing (the fade would freeze black),
	# with the controls locked meanwhile.
	GameManager.choosing = true
	GameManager.input_locked = true
	await get_tree().create_timer(0.9, true, false, true).timeout
	if run != _run:
		return
	GameManager.input_locked = false
	_hold()
	await _dialogue.say(StoryData.SAL, StoryData.INTRO_SAL, "intro_sal")
	if run != _run:
		return
	# Power on: a face flickers in the glass.
	Sfx.play("warning", -4.0, 0.5)
	_face.visible = true
	_face_on = true
	await get_tree().create_timer(2.4, true, false, true).timeout
	if run != _run:
		return
	_face_on = false
	# The Journal slides out.
	_journal_card.visible = true
	_journal_card.modulate.a = 1.0
	_journal_card.position = Vector2(150, 1150)
	Sfx.play("ramp_complete", -6.0, 0.7)
	var slide := create_tween()
	slide.tween_property(_journal_card, "position:y", 250.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.1, true, false, true).timeout
	if run != _run:
		return
	await _dialogue.say("", StoryData.INTRO_JOURNAL, "intro_narration")
	if run != _run:
		return
	await _dialogue.say(StoryData.GHOST_UNKNOWN, StoryData.INTRO_GHOST.slice(0, 1), "intro_ghost")
	if run != _run:
		return
	await _dialogue.say(StoryData.GHOST, StoryData.INTRO_GHOST.slice(1), "intro_ghost", 2)
	if run != _run:
		return
	var fade := create_tween()
	fade.tween_property(_journal_card, "modulate:a", 0.0, 0.5)
	fade.parallel().tween_property(_face, "modulate:a", 0.0, 0.5)
	fade.tween_callback(func() -> void:
		_journal_card.visible = false
		_face.visible = false
		_face.modulate.a = 1.0)
	Story.intro_seen = true
	Story.save()
	_release(false)
	_chapter_banner()


## Stop the game for a scene (also blocks the pause menu and restart key).
func _hold() -> void:
	GameManager.choosing = true
	get_tree().paused = true


func _release(countdown: bool) -> void:
	GameManager.choosing = false
	if countdown:
		GameManager.resume_play()
	else:
		get_tree().paused = false


# --- During play --------------------------------------------------------------------

func _process(delta: float) -> void:
	if _face.visible:
		# Flicker: mostly faint, with sudden brighter frames.
		var target := (0.55 if randf() < 0.12 else randf_range(0.05, 0.3)) if _face_on else 0.12
		_face_alpha = lerpf(_face_alpha, target, 0.35)
		_face.queue_redraw()
	if get_tree().paused or phase == "over":
		return
	stats["time"] = float(stats.get("time", 0.0)) + delta
	if GameManager.ball_launched:
		_whisper_once("first_launch")
	if _boss and phase == "plain" and _boss.hp <= _phase_one_max * 0.5:
		_whisper_once("half_hp")
	if _boss and phase == "boss" and _current_boss_hp() <= _boss_max * 0.5:
		_whisper_once("boss_half")


func _whisper_once(key: String) -> void:
	if _whispered.has(key) or not StoryData.WHISPERS.has(key) or _dialogue.is_talking():
		return
	_whispered[key] = true
	_dialogue.whisper(StoryData.WHISPERS[key], 4.0, "whisper_" + key)


func _on_part_hit(part: Node) -> void:
	if phase == "over":
		return
	if part is SplitHalf:
		return # counted through the gimmick's damage
	if part is Bumper and not part is BossBumper:
		stats["bumper_hits"] = int(stats["bumper_hits"]) + 1
		_whisper_once("first_bumper")


func _on_ball_lost() -> void:
	if phase == "over":
		return
	stats["balls_lost"] = int(stats["balls_lost"]) + 1
	_whisper_once("ball_lost")


func _on_tilted_changed(is_tilted: bool) -> void:
	if is_tilted and phase != "over":
		stats["tilts"] = int(stats["tilts"]) + 1


func _on_boss_damaged(amount: float) -> void:
	if phase == "over":
		return
	stats["damage"] = float(stats["damage"]) + amount
	stats["boss_hits"] = int(stats["boss_hits"]) + 1


func _on_boss_depleted(_info: Dictionary) -> void:
	# Called from inside a physics callback: act on the next idle frame.
	if phase == "plain":
		phase = "reveal"
		_reveal.call_deferred(_run)
	elif phase == "boss":
		_victory.call_deferred(_run)


## The boss's HP right now, whether he is whole or in two halves.
func _current_boss_hp() -> float:
	if is_instance_valid(_gimmick) and _gimmick.is_split():
		return _gimmick.halves_hp()
	return _boss.hp if is_instance_valid(_boss) else 0.0


# --- The reveal ---------------------------------------------------------------------

func _reveal(run: int) -> void:
	if run != _run or not is_instance_valid(_boss):
		return
	_hold()
	var again := Story.is_beaten(chapter["id"])
	_revealed = true
	Sfx.play("guard_break")
	_flash.modulate.a = 0.9
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.7)
	_boss.art = str(chapter["art"])
	_boss_max = maxf(roundf(GameManager.score * StoryData.BOSS_HP_SCORE_FACTOR), StoryData.BOSS_HP_MIN)
	_boss.set_hp(_boss_max)
	Sfx.play_battle_music()
	if "hud" in game:
		game.hud.show_banner(str(chapter["boss"]).to_upper(), 2.2)
	await get_tree().create_timer(0.8, true, false, true).timeout
	if run != _run:
		return
	if again:
		await _dialogue.say(StoryData.GHOST, [StoryData.REMATCH_LINE, chapter["hint"]], str(chapter["id"]) + "_again")
	else:
		await _dialogue.say("", [chapter["reveal"]], str(chapter["id"]) + "_reveal")
		if run != _run:
			return
		await _dialogue.say(StoryData.GHOST, chapter["briefing"], str(chapter["id"]) + "_briefing")
	if run != _run:
		return
	_start_gimmick()
	phase = "boss"
	_release(true)


func _start_gimmick() -> void:
	match str(chapter.get("gimmick", "")):
		"splitter":
			_gimmick = SplitterBoss.new()
			_gimmick.boss = _boss
			add_child(_gimmick)
			_gimmick.process_mode = Node.PROCESS_MODE_PAUSABLE
			_gimmick.active = true
			_gimmick.damaged.connect(_on_boss_damaged)
			_gimmick.defeated.connect(func(_info: Dictionary) -> void: _victory.call_deferred(_run))
			_gimmick.split_started.connect(func() -> void:
				stats["splits"] = int(stats["splits"]) + 1
				_whisper_once("split"))


# --- Endings ------------------------------------------------------------------------

## Boss at 0: slow-motion close-up, then a silent tilt, then the Victory page.
func _victory(run: int) -> void:
	if run != _run or phase == "over":
		return
	phase = "over"
	GameManager.choosing = true # no pause menu or restart key during the ending
	if is_instance_valid(_gimmick):
		_gimmick.active = false
	var at := _boss.global_position if is_instance_valid(_boss) else Vector2(300, 400)
	Engine.time_scale = SLOWMO_SCALE
	if game.has_method("focus_camera"):
		game.focus_camera(at, CLOSE_UP_ZOOM, 0.7)
	await get_tree().create_timer(SLOWMO_SECONDS - MUSIC_FADE_SECONDS, true, false, true).timeout
	if run != _run:
		return
	Sfx.fade_to_silence(MUSIC_FADE_SECONDS) # no hard cut: the music drains away
	await get_tree().create_timer(MUSIC_FADE_SECONDS, true, false, true).timeout
	if run != _run:
		return
	# The machine tilts, in complete silence.
	Engine.time_scale = 1.0
	Sfx.silence()
	if game.has_method("reset_camera"):
		game.reset_camera(0.5)
	GameManager.is_game_over = true # flippers and nudges go dead; drains don't count
	GameManager.tilted = true
	GameManager.tilted_changed.emit(true) # the HUD shows TILT
	await get_tree().create_timer(SILENT_TILT_SECONDS, true, false, true).timeout
	if run != _run:
		return
	# A sad sort of win: the quiet song comes in before the page does.
	Sfx.play_theme(Sfx.QUIET_WIN_TRACK)
	await get_tree().create_timer(QUIET_SONG_LEAD_SECONDS, true, false, true).timeout
	if run != _run:
		return
	_finish(true)


func _on_game_over(_score: float) -> void:
	if phase == "over":
		return
	phase = "over"
	stats["balls_lost"] = int(stats["balls_lost"]) + 1 # the last one
	GameManager.choosing = true
	var run := _run
	Sfx.end_battle_music()
	await get_tree().create_timer(1.0, true, false, true).timeout
	if run == _run:
		_finish(false)


## Pay the coins, save, and open the Journal's result page.
func _finish(won: bool) -> void:
	var phase_one_share := 1.0
	if not _revealed and is_instance_valid(_boss):
		phase_one_share = clampf(1.0 - _boss.hp / _phase_one_max, 0.0, 1.0)
	var boss_share := 0.0
	if won:
		boss_share = 1.0
	elif _revealed:
		boss_share = clampf(1.0 - _current_boss_hp() / _boss_max, 0.0, 1.0)
	var first := false
	var coins := roundi(StoryData.COINS_PHASE_ONE * phase_one_share) + roundi(StoryData.COINS_BOSS * boss_share)
	if won:
		first = Story.beat_chapter(chapter["id"])
		coins += StoryData.COINS_FIRST_DEFEAT if first else StoryData.COINS_REPEAT_DEFEAT
	Story.record_run(chapter["id"], GameManager.score, float(stats["damage"]))
	var coin := Story.add_coins(coins)
	Story.save()
	_result.open({
		"won": won,
		"first": first,
		"chapter": chapter,
		"coins": coins,
		"coin": coin,
		"score": GameManager.score,
		"stats": stats,
		"boss_share": boss_share,
		"revealed": _revealed,
	})


func _on_retry() -> void:
	GameManager.choosing = false
	GameManager.restart()


func _on_to_menu() -> void:
	Story.return_to_hub = true
	Sfx.unsilence()
	GameManager.choosing = false
	if game and game.has_method("go_to_main_menu"):
		game.go_to_main_menu()


# --- Effects ------------------------------------------------------------------------

func _build_fx() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 16 # over the table and HUD, under the dialogue
	add_child(_fx_layer)
	_face = Control.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.visible = false
	_face.draw.connect(_draw_face)
	_fx_layer.add_child(_face)
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_fx_layer.add_child(_flash)
	_journal_card = PanelContainer.new()
	_journal_card.custom_minimum_size = Vector2(300, 380)
	_journal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal_card.add_theme_stylebox_override("panel", JournalPanel.paper_style())
	_journal_card.visible = false
	_fx_layer.add_child(_journal_card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	_journal_card.add_child(page)
	for item: Array in [["JOURNAL", 30], ["page one", 16],
			["\"If you are reading this, she has found you. Good. I had hoped somebody would come.\"", 17]]:
		var label := Label.new()
		label.text = item[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(260, 0)
		label.add_theme_font_size_override("font_size", item[1])
		label.add_theme_color_override("font_color", JournalPanel.INK)
		page.add_child(label)


## A face in the playfield glass: pale, unsteady, mostly eyes.
func _draw_face() -> void:
	var c := Color(0.75, 0.92, 1.0, _face_alpha)
	var center := Vector2(300, 420)
	var jitter := Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	# Head outline
	_face.draw_arc(center + jitter, 150.0, PI * 0.08, PI * 0.92, 40, Color(c, c.a * 0.5), 3.0, true)
	_face.draw_arc(center + jitter + Vector2(0, -30), 165.0, PI * 1.08, PI * 1.92, 40, Color(c, c.a * 0.5), 3.0, true)
	# Eyes
	for side: float in [-1.0, 1.0]:
		var eye := center + jitter + Vector2(side * 62.0, -40.0)
		_face.draw_set_transform(eye, 0.0, Vector2(1.0, 0.62))
		_face.draw_circle(Vector2.ZERO, 30.0, Color(c, c.a * 0.9))
		_face.draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, c.a))
		_face.draw_set_transform(Vector2.ZERO)
		_face.draw_arc(eye + Vector2(0, -8), 44.0, PI * 1.2, PI * 1.8, 16, Color(c, c.a * 0.7), 3.0, true)
	# Mouth: a tired half smile
	_face.draw_arc(center + jitter + Vector2(0, 40), 60.0, PI * 0.2, PI * 0.8, 20, Color(c, c.a * 0.8), 4.0, true)
