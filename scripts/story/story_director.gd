class_name StoryDirector
extends Node
## Runs a story-mode chapter (added by game.gd when GameManager.game_mode is
## "story"). One chapter = one machine, in two phases:
##   1. "plain": a normal game. The center bumper looks ordinary and has a
##      health bar (the first Endless boss's HP).
##   2. "boss":  at 0 the boss reveals itself: new art, battle music, HP scaled
##      from the player's score (StoryData.BOSS_HP_SCORE_FACTOR, or the chapter's
##      "boss_hp_factor") and its gimmick.
## A chapter with a "boss_scene" opens with a "prelude" on the last chapter's
## machine: after "phase_one_hits" hits on its bumper that table drops away and
## the chapter's own rises in its place, where phases 1 and 2 are played.
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
var _collector: CollectorBoss
var _phase_one_max: float = 1.0
var _boss_max: float = 1.0
var _revealed: bool = false
var _whispered: Dictionary = {}
## Coins already announced with a popup this run (see _coins_from_damage).
var _coins_popped: int = 0
## True until the first run of this visit starts: that one opens with the intro.
## (Try again / Restart go straight to play.)
var _fresh_visit: bool = true
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


func _exit_tree() -> void:
	GameManager.popups_hidden = false # leaving mid-switch must not carry over


# --- Run start ----------------------------------------------------------------------

## A new attempt (the level is already loaded: game.gd hears game_started first).
func _on_run_started() -> void:
	_run += 1
	# A chapter that starts on another machine opens with a short "prelude" there.
	phase = "prelude" if chapter.has("phase_one_hits") else "plain"
	_revealed = false
	_coins_popped = 0
	_whispered.clear()
	stats = {"damage": 0.0, "boss_hits": 0, "bumper_hits": 0, "nudges": 0, "tilts": 0,
			"balls_lost": 0, "parts": 0, "time": 0.0, "splits": 0,
			"rearranged": 0, "showpiece_hits": 0, "gallery_hits": 0}
	Engine.time_scale = 1.0
	GameManager.popups_hidden = false # a restart mid-switch
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
	if is_instance_valid(_collector):
		_collector.queue_free()
	_collector = null
	_boss = game.level.boss() if game.level else null
	if _boss:
		# A beaten boss keeps his face: the cap stays cracked on later visits.
		# (Not when the boss lives on another machine: this one is only borrowed.)
		var own_face := Story.is_beaten(chapter["id"]) and not chapter.has("boss_scene")
		_take_boss(_boss, str(chapter["art"]) if own_face else str(chapter.get("phase_one_art", "plain")))
		if chapter.has("phase_one_hits"):
			# Counted in hits: each hit takes one off, whatever the score.
			_boss.fixed_damage = 1.0
			_boss.set_hp(float(chapter["phase_one_hits"]))
		else:
			_boss.set_hp(float(chapter.get("phase_one_hp", StoryData.PHASE_ONE_HP)))
		_phase_one_max = _boss.max_hp
	if Story.is_beaten(chapter["id"]) and game.level:
		game.level.modulate = chapter.get("tint", Color.WHITE)
	var opening := _fresh_visit
	_fresh_visit = false
	if opening and chapter.has("opening") and Story.intro_seen:
		_opening(_run) # the chapter's own opening instead of Sal's handover
	elif opening:
		_intro(_run) # shows the chapter banner when it ends; Skip on the dialogue box
	else:
		_chapter_banner()
		_whisper_later(_run, StoryData.WHISPER_START, "whisper_start")


## Story mode runs this boss: our signals, our art.
func _take_boss(boss: BossBumper, art: String) -> void:
	boss.story_controlled = true
	boss.art = art
	boss.depleted.connect(_on_boss_depleted)
	boss.damaged.connect(_on_boss_damaged)


func _chapter_banner() -> void:
	if "hud" in game:
		game.hud.show_banner("CHAPTER %d  ·  %s" % [int(chapter["number"]), chapter["title"]], 2.0)


func _whisper_later(run: int, text: String, voice_id: String) -> void:
	await get_tree().create_timer(2.6, true, false, true).timeout
	if run == _run and phase in ["plain", "prelude"]:
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
	_dialogue.begin_scene()
	await _dialogue.say(StoryData.SAL, StoryData.INTRO_SAL, "intro_sal")
	if run != _run:
		return
	if not _dialogue.skipping: # Skip also skips the face and the Journal sliding out
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


## A later chapter's start: the ghost sets the scene.
func _opening(run: int) -> void:
	GameManager.choosing = true
	GameManager.input_locked = true
	await get_tree().create_timer(0.9, true, false, true).timeout
	if run != _run:
		return
	GameManager.input_locked = false
	_hold()
	_dialogue.begin_scene()
	await _dialogue.say(StoryData.GHOST, chapter["opening"], str(chapter["id"]) + "_opening")
	if run != _run:
		return
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
	var own: Dictionary = chapter.get("whispers", {})
	if _whispered.has(key) or _dialogue.is_talking():
		return
	if own.has(key):
		_whispered[key] = true
		_dialogue.whisper(own[key], 4.0, "%s_whisper_%s" % [chapter["id"], key])
	elif StoryData.WHISPERS.has(key):
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
	stats["boss_hits"] = int(stats["boss_hits"]) + 1
	if phase == "prelude" and is_instance_valid(_boss) and _boss.fixed_damage > 0.0:
		var done := roundi(_phase_one_max - _boss.hp)
		GameManager.popup("%d / %d" % [done, roundi(_phase_one_max)],
				_boss.global_position + Vector2(0, -_boss.radius - 40.0), Color(1.0, 0.82, 0.3), true)
		_pop_coins.call_deferred()
		return # hits, not damage
	stats["damage"] = float(stats["damage"]) + amount
	_pop_coins.call_deferred() # after the hit has been taken off the HP


## Coins earned so far from damage alone: whole coins for the share of the
## first bumper's HP and of the boss's HP that is gone.
func _coins_from_damage(boss_beaten: bool = false) -> int:
	var phase_one_share := 1.0
	if phase in ["prelude", "switch"]:
		phase_one_share = 0.0 # the borrowed machine's hits pay nothing
	elif not _revealed and is_instance_valid(_boss):
		phase_one_share = clampf(1.0 - _boss.hp / _phase_one_max, 0.0, 1.0)
	var boss_share := 0.0
	if boss_beaten:
		boss_share = 1.0
	elif _revealed and phase != "reveal":
		boss_share = clampf(1.0 - _current_boss_hp() / _boss_max, 0.0, 1.0)
	return floori(StoryData.COINS_PHASE_ONE * phase_one_share + 0.0001) + floori(StoryData.COINS_BOSS * boss_share + 0.0001)


## A small "+1 coin" above the boss each time the damage earns another coin.
func _pop_coins() -> void:
	if phase == "over" or not is_instance_valid(_boss):
		return
	var earned := _coins_from_damage()
	if earned <= _coins_popped:
		return
	var gained := earned - _coins_popped
	_coins_popped = earned
	var at := _boss.global_position
	if is_instance_valid(_gimmick) and _gimmick.is_split():
		at = _gimmick.halves_center()
	GameManager.popup("+%d coin%s" % [gained, "" if gained == 1 else "s"], at + Vector2(0, -_boss.radius - 44.0), Color(1.0, 0.82, 0.25), false)
	Sfx.play("click", -6.0, 2.0, 60)


func _on_boss_depleted(_info: Dictionary) -> void:
	# Called from inside a physics callback: act on the next idle frame.
	if phase == "prelude":
		phase = "switch"
		_switch_table.call_deferred(_run)
	elif phase == "plain":
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
	var factor := float(chapter.get("boss_hp_factor", StoryData.BOSS_HP_SCORE_FACTOR))
	_boss_max = maxf(roundf(GameManager.score * factor), StoryData.BOSS_HP_MIN)
	_boss.set_hp(_boss_max)
	Sfx.play_battle_music()
	if "hud" in game:
		game.hud.show_banner(str(chapter["boss"]).to_upper(), 2.2)
	await get_tree().create_timer(0.8, true, false, true).timeout
	if run != _run:
		return
	_dialogue.begin_scene()
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


## The prelude's bumper broke: the table is swapped for the chapter's own
## machine, whose center bumper is phase 1 proper: an ordinary-looking bumper,
## even on a replay (the reveal turns it into the boss).
func _switch_table(run: int) -> void:
	if run != _run or not is_instance_valid(_boss):
		return
	_hold()
	var again := Story.is_beaten(chapter["id"])
	Sfx.play("guard_break")
	await _morph(run, again)
	if run != _run or not is_instance_valid(_boss):
		return
	_boss.art = str(chapter.get("plain_art", "plain"))
	_boss.set_hp(float(chapter.get("phase_one_hp", StoryData.PHASE_ONE_HP)))
	_phase_one_max = _boss.max_hp
	phase = "plain"
	await get_tree().create_timer(0.6, true, false, true).timeout
	if run != _run:
		return
	if not again:
		_dialogue.begin_scene()
		await _dialogue.say(StoryData.GHOST, chapter.get("arrival", []), str(chapter["id"]) + "_arrival")
		if run != _run:
			return
		await _deck_tour(run)
		if run != _run:
			return
	_release(true)


const FALL_SECONDS := 0.75
const DARK_SECONDS := 0.6 # the empty, dark cabinet between the two tables
const RISE_SECONDS := 1.0
const DROP_DISTANCE := 1300.0 # past the bottom of the screen

## The table is swapped for the chapter's boss machine: it shakes while the
## reveal is told, then drops out of sight, and after a moment of darkness the
## new one rises from the bottom of the screen. The ball is put in the new
## table's Till (if it has one), which serves it once the fight starts.
func _morph(run: int, again: bool) -> void:
	var old: Level = game.level
	var holder := old.get_parent()
	# Shaking, under the reveal's line (a rematch just shakes for a moment).
	Sfx.play("warning", -4.0, 0.45)
	_dialogue.hush()
	GameManager.popups_hidden = true # no floating scores over the switch
	var shaking := [true]
	_shake_while(shaking)
	if again:
		await get_tree().create_timer(1.2, true, false, true).timeout
	else:
		_dialogue.begin_scene()
		await _dialogue.say("", [chapter["switch"]], str(chapter["id"]) + "_switch")
	shaking[0] = false
	if run != _run:
		return
	# Behind the table: an empty, dark cabinet.
	var dark := ColorRect.new()
	dark.color = Color(0.01, 0.01, 0.02)
	dark.position = Vector2(-200, -200)
	dark.size = Vector2(1000, 1600)
	dark.z_index = -50
	holder.add_child(dark)
	holder.move_child(dark, 0)
	# The table falls, the balls with it. The real balls stay where they are,
	# hidden (out of the table they would count as drained); painted stand-ins
	# on the table fall in their place.
	for b: Ball in _balls_in_play():
		if b.visible:
			var stand_in := Node2D.new()
			stand_in.position = old.to_local(b.global_position)
			stand_in.z_index = 20
			var r := b.radius
			stand_in.draw.connect(func() -> void:
				stand_in.draw_circle(Vector2.ZERO, r, Color(0.85, 0.87, 0.92))
				stand_in.draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.9)))
			old.add_child(stand_in)
			b.visible = false
	Sfx.play("guard_break", -2.0, 0.6)
	var fall := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fall.tween_property(old, "position:y", DROP_DISTANCE, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if fall.is_running():
		await fall.finished
	old.visible = false # kept until the new table is in: the game still points at it
	await get_tree().create_timer(DARK_SECONDS, true, false, true).timeout
	if run != _run:
		dark.queue_free()
		return
	# The new table rises from the bottom, the ball already in its Till.
	var fresh := (load(str(chapter["boss_scene"])) as PackedScene).instantiate() as Level
	var tint: Color = chapter.get("tint", Color.WHITE) if Story.is_beaten(chapter["id"]) else Color.WHITE
	fresh.modulate = tint
	fresh.position.y = DROP_DISTANCE
	holder.add_child(fresh)
	Cosmetics.apply(fresh)
	game.level = fresh
	holder.remove_child(old)
	old.queue_free()
	_boss = fresh.boss()
	if _boss:
		# Rises already looking as it will be fought: the plain blue bumper, even on a
		# replay (the reveal still flips it), with no health bar flashing by.
		_take_boss(_boss, str(chapter.get("plain_art", "plain")))
		_boss.set_hp(float(chapter.get("phase_one_hp", StoryData.PHASE_ONE_HP)))
	Sfx.play("ramp_complete", -4.0, 0.5)
	var rise := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	rise.tween_property(fresh, "position:y", 0.0, RISE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if rise.is_running():
		await rise.finished
	dark.queue_free()
	if run != _run:
		return
	_seat_balls(fresh)
	GameManager.level_changed.emit(fresh) # spare parts rebuild on the new table
	GameManager.popups_hidden = false
	if game.has_method("_shake"):
		game._shake(Vector2.DOWN)
	Sfx.play("guard_break", -2.0, 0.8)


## The ghost points out the table's second floor: it (and the ramps up to it)
## show while he talks about it, then go back to hiding until a ball goes up.
func _deck_tour(run: int) -> void:
	var lines: Array = chapter.get("deck_tour", [])
	var decks: Array = game.level.find_children("*", "UpperDeck", true, false)
	if lines.is_empty() or decks.is_empty():
		return
	var shown := []
	for deck: UpperDeck in decks:
		shown.append(deck)
		shown.append_array(deck.ramps())
	for part in shown:
		part.set_forced(true)
	await get_tree().create_timer(0.35, true, false, true).timeout
	if run == _run:
		await _dialogue.say(StoryData.GHOST, lines, str(chapter["id"]) + "_deck")
	for part in shown:
		if is_instance_valid(part):
			part.set_forced(false)


## Keeps the table shaking while flag[0] is true.
func _shake_while(flag: Array) -> void:
	while flag[0] and is_inside_tree():
		if game.has_method("_shake"):
			game._shake(Vector2.RIGHT.rotated(randf() * TAU))
		await get_tree().create_timer(0.22, true, false, true).timeout


func _balls_in_play() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball and ball.in_play:
			out.append(ball)
	return out


## Put the balls on the new table: the first in its Till, any others in the lane.
func _seat_balls(table: Level) -> void:
	var till := table.find_child("Till", true, false) as BallTrap
	var first := true
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null or not ball.in_play:
			continue
		ball.leave_ramp()
		ball.deck = null
		if first and till:
			till.hold(ball) # hidden in there until it is served
		else:
			ball.place(table.spawn_point + Vector2(0, -30.0 if not first else 0.0))
			ball.visible = true
		first = false


func _start_gimmick() -> void:
	match str(chapter.get("gimmick", "")):
		"collector":
			_collector = CollectorBoss.new()
			_collector.boss = _boss
			_collector.level = game.level
			_collector.game = game
			add_child(_collector)
			_collector.process_mode = Node.PROCESS_MODE_PAUSABLE
			_collector.active = true
			_collector.rearranged.connect(func() -> void:
				stats["rearranged"] = int(stats["rearranged"]) + 1
				_whisper_once("rearrange"))
			_collector.marked.connect(func(kind: String) -> void: _whisper_once(kind))
			_collector.bonus_hit.connect(func(kind: String) -> void:
				var key := "showpiece_hits" if kind == "showpiece" else "gallery_hits"
				stats[key] = int(stats[key]) + 1)
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
	if is_instance_valid(_collector):
		_collector.active = false
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
	var boss_share := 0.0
	if won:
		boss_share = 1.0
	elif _revealed:
		boss_share = clampf(1.0 - _current_boss_hp() / _boss_max, 0.0, 1.0)
	var first := false
	# The same whole coins the popups counted during play, plus the win bonus.
	var coins := _coins_from_damage(won)
	if won:
		first = Story.beat_chapter(chapter["id"])
		coins += StoryData.COINS_FIRST_DEFEAT if first else StoryData.COINS_REPEAT_DEFEAT
	var records: Dictionary = Story.record_run(chapter["id"], GameManager.score, float(stats["damage"]), float(stats["time"]), won)
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
		"records": records,
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
