class_name Tutorial
extends CanvasLayer
## Tutorial game mode on the Classic machine, told by Sal, its old owner.
## game.gd adds this node when GameManager.game_mode == "tutorial".
##
## The ball never teleports or vanishes: between the player's turns Sal plays
## the machine himself. He catches the ball by holding the flippers up (a
## "cradle"), lets it roll, and uses flips and nudges to set up each situation.
## From a cradle the physics are repeatable, so his shots land the same way
## every time (numbers below were measured on Classic with a flipper bot).
##
## When the player has to act, the game is paused (the clock runs at 0.05%,
## not 0, which would break the physics) and the keys or touch areas are shown.
## The moment the player does it, the clock runs again and the action lands.
##
## Steps: launch, first flip, gutter save (hold the flipper + nudge up), first
## minor power-up (both inlanes), the boss (score = damage, HP to 0), tilt,
## ball lost, invitation to the other modes, back to the main menu.

signal _advance
signal _prompt_done

const SPEAKER := "SAL"
const CHARS_PER_SEC := 55.0
const GOLD := Color(1.0, 0.85, 0.3)
const BUBBLE_POS := Vector2(30, 52)
const BUBBLE_WIDTH := 540.0
const PAUSED_SCALE := 0.0005

# --- Classic machine, measured -------------------------------------------------
## Where a cradled ball rests (left / right flipper held up).
const CRADLE := {"L": Vector2(200.4321, 957.5539), "R": Vector2(359.5667, 957.5597)}
const FLIPPER_PIVOT := {"L": Vector2(200, 982), "R": Vector2(360, 982)}
## Frames (240/s) between releasing a cradle and flipping, for each shot.
const CROSS_FRAMES := 126 # across the table, into the opposite inlane, back to the other flipper
const TOP_FRAMES := 144 # up to the top of the table (Sal's boss attempt)
const GUTTER_FRAMES := {"L": 120, "R": 116} # from this cradle into the opposite outlane
## Gutter save: nudge when the ball passes this x, giving it this velocity
## (what a well-timed nudge does; mirrored for the right side).
const SAVE_X := {"L": 216.0, "R": 344.0}
const SAVE_VELOCITY := Vector2(227, -888) # the measured velocity plus the nudge's own push

var game: Node

var _token: int = 0
var _touch: bool = false
var _gutter: String = "" # side whose gutter the ball is in, during the save
var _expect_pick: bool = false # the power-up lesson is running
var _pick_seen: bool = false # the picker opened during it

# Dialogue bubble
var _bubble: PanelContainer
var _text: Label
var _hint: Label
var _shown_at: int = 0
var _waiting: bool = false

# Prompt overlay: "", "launch", "flip", "hold", "nudge", "nudge_many"
var _prompt: String = ""
var _prompt_side: String = "L"
var _overlay: Control
var _rings: Array = []
var _skip: Button
var _keycap: StyleBoxFlat


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameManager.game_started.connect(func() -> void: _begin.call_deferred())
	game.nudged.connect(_on_nudged)
	GameManager.powerup_choice_requested.connect(_on_pick_requested)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	GameManager.input_locked = false
	GameManager.unlocked_actions.clear()


# --- Script ---------------------------------------------------------------------

func _begin() -> void:
	_token += 1
	_prompt = ""
	_rings = []
	_waiting = false
	Engine.time_scale = 1.0
	_run(_token)


func _run(token: int) -> void:
	var tc := game.get_node_or_null("TouchControls")
	_touch = tc != null and tc.enabled
	if tc:
		tc._hint_time = 0.0 # Sal does the explaining
	var ball: Ball = game.ball
	var level: Node = game.level
	# The player only acts when prompted: dialogue keys must not move anything.
	GameManager.input_locked = true
	_lock()
	await _wait(0.4)
	if token != _token: return
	_pause()

	# 1. Hello
	await _say("Well, hello there! Name's Sal. I looked after this old machine for thirty-odd years.")
	if token != _token: return
	await _say("Pull up a stool and I'll show you how she works. I'll tell you exactly when it's your turn.")
	if token != _token: return

	# 2. Launch, then Sal catches the ball
	_rings = [[Vector2(560, 1008), 24.0]]
	await _say("The ball starts in the launcher, down there in the bottom-right corner.")
	if token != _token: return
	_rings = []
	var side: String = await _launch_and_catch(token, false)
	if token != _token: return
	# Start the inlane lights fresh, so lighting both waits for the power-up lesson.
	for lane in ["Rollovers/InlaneLeft", "Rollovers/InlaneRight"]:
		var r: Node2D = level.get_node(lane)
		r.lit = false
		r.queue_redraw()
	await _say("Nice shot! See how I'm holding the %s flipper up? That traps the ball so it sits still. We call it a cradle." % _side_word(side))
	if token != _token: return

	# 3. First flip
	await _say("Now it's your turn. I'll let the ball roll down the flipper, and when I say so, you flip!")
	if token != _token: return
	_resume()
	await _settle(side) # exact cradle before every shot
	if token != _token: return
	_sal(side, false)
	await _frames(CROSS_FRAMES)
	if token != _token: return
	_pause()
	await _ask("flip", side, ("Now! Tap the %s half of the bottom of the screen!" if _touch else "Now! Hit the %s flipper!") % _side_word(side))
	if token != _token: return
	await _frames(30)
	_lock() # the player's turn is over
	side = await _catch(token)
	if token != _token: return
	await _say("Ha! Right across the table, and I caught it on the other side. Time your flip as the ball rolls and you can aim.")
	if token != _token: return
	await _say(("Each half of the bottom of the screen works its flipper." if _touch \
			else "Z or LEFT works the left flipper, M or RIGHT the right one."))
	if token != _token: return

	# 4. Gutter save: hold the flipper on the ball's side, nudge up, land on the other flipper.
	await _say("Now, an old trick. Sometimes the ball slips down an outlane and rolls along the gutter, underneath a flipper. I'll show you.")
	if token != _token: return
	var gutter := _other(side)
	while true:
		_resume()
		await _settle(side) # exact cradle before every shot
		if token != _token: return
		_sal(side, false)
		await _frames(GUTTER_FRAMES[side])
		_sal(side, true)
		await _frames(30)
		_sal(side, false)
		var in_gutter := func() -> bool:
			var p := ball.global_position
			return (p.x < 62.0 and p.y > 900.0) if gutter == "L" else (p.x > 498.0 and p.x < 540.0 and p.y > 900.0)
		var reached: bool = await _wait_until(in_gutter, 4.0)
		if token != _token: return
		if not reached:
			side = await _catch(token)
			if token != _token: return
			gutter = _other(side)
			continue
		_pause()
		await _say("There it goes, down the outlane. Looks lost, doesn't it? It isn't!")
		if token != _token: return
		await _ask("hold", gutter, ("Press and HOLD the %s side of the screen..." if _touch else "Hold the %s flipper up and keep holding it...") % _side_word(gutter))
		if token != _token: return
		var at_window := func() -> bool:
			var x := ball.global_position.x
			return x >= SAVE_X["L"] if gutter == "L" else x <= SAVE_X["R"]
		await _wait_until(at_window, 3.0)
		if token != _token: return
		_pause()
		_gutter = gutter
		await _ask("nudge", gutter, "...keep holding, and swipe UP with another finger!" if _touch else "...keep holding, and nudge UP with W!")
		_gutter = ""
		if token != _token: return
		await _frames(60)
		var catch_side := _other(gutter)
		_sal(catch_side, true)
		await _frames(10)
		_lock() # the player's turn is over (their held flipper drops now)
		side = await _catch(token)
		if token != _token: return
		if side == catch_side:
			break
		await _say("Close one! Let's try that again.")
		if token != _token: return
		gutter = _other(side)
	await _say("Saved! Holding the flipper opens a path, and the nudge pops the ball over onto the other flipper.")
	if token != _token: return
	await _say(("Swipe left, up or right anywhere to nudge the machine that way." if _touch \
			else "A, W and D nudge the machine left, up and right.") + " It works on either side: hold the flipper the ball is rolling under, then nudge up.")
	if token != _token: return

	# 5. First minor power-up: light both inlanes
	var inlane_l: Node2D = level.get_node("Rollovers/InlaneLeft")
	var inlane_r: Node2D = level.get_node("Rollovers/InlaneRight")
	_rings = [[inlane_l.global_position, 16.0], [inlane_r.global_position, 16.0]]
	await _say("See the two orange lights beside the slingshots? Those are the inlanes.")
	if token != _token: return
	await _say("Light both and the machine hands you a spare part: a minor power-up. Watch, I'll send the ball through them.")
	if token != _token: return
	_rings = []
	_pick_seen = false
	_expect_pick = true # _process shows Sal's line while the picker is open
	for attempt in 4:
		_resume()
		await _settle(side) # exact cradle before every shot
		if token != _token: return
		_sal(side, false)
		await _frames(CROSS_FRAMES)
		_sal(side, true)
		await _frames(30)
		_sal(side, false)
		# Catch right away; if the picker opens on the way down the game pauses,
		# and the catch carries on after the pick.
		side = await _catch(token)
		if token != _token: return
		if _pick_seen:
			break
	_expect_pick = false
	await _say("Good pick. The lights up top, near the boss, give MAJOR parts. Those are the really strong ones.")
	if token != _token: return

	# 6. The boss: score = damage, HP to zero
	var boss: Node2D = level.get_node("Bumpers/BossBumper")
	_rings = [[boss.global_position, boss.radius + 10.0]]
	await _say("Now, that big red bumper in the middle? That's the boss.")
	if token != _token: return
	await _say("Every hit on it deals damage equal to your WHOLE score. The more points you have, the harder you hit! Watch this.")
	if token != _token: return
	_rings = []
	# The boss sits between the lift lanes, out of a straight flipper shot's line,
	# so Sal sends the ball up top and keeps it in play until it hits the boss.
	var hp_before: float = boss.hp
	var hit_boss := func() -> bool: return boss.hp < hp_before
	var got := ""
	for attempt in 4:
		_resume()
		await _settle(side)
		if token != _token: return
		_sal(side, false)
		await _frames(TOP_FRAMES)
		_sal(side, true)
		await _frames(30)
		_sal(side, false)
		got = await _catch(token, hit_boss)
		if token != _token: return
		if got == "HIT":
			break
		side = got # back in a cradle without a hit: go again
	_rings = [[boss.global_position, boss.radius + 10.0]]
	if got == "HIT":
		await _wait(0.25)
		if token != _token: return
		_pause()
		await _say("Bang! See its HP drop? That's your score hitting it. Bring the HP down to zero and the boss is beaten.")
	else:
		_pause()
		await _say("Can't hit it today, would you believe it! But every hit takes off as much HP as your score. Bring the HP down to zero and the boss is beaten.")
	if token != _token: return
	await _say("Then it's your call: take on a tougher boss, or end the run and post your score.")
	if token != _token: return
	_rings = []
	if got == "HIT":
		side = await _catch(token)
		if token != _token: return

	# 7. Tilt: the ball sits in the cradle while the player nudges.
	GameManager.balls_left = maxi(GameManager.balls_left, 2) # this ball is lost on purpose
	GameManager.balls_changed.emit(GameManager.balls_left)
	_pause()
	await _say("One more thing about nudging. Shove her too often and she TILTS.")
	if token != _token: return
	_resume() # each nudge really shoves the cradled ball
	await _ask("nudge_many", side, "Go on, nudge a few times in a row and see what happens.")
	if token != _token: return
	_lock()
	_note("TILT! The flippers go dead and nothing scores until the ball drains.")
	var lost := [false]
	var on_lost := func() -> void: lost[0] = true
	GameManager.ball_lost.connect(on_lost)
	await _wait_until(func() -> bool: return lost[0], 15.0)
	GameManager.ball_lost.disconnect(on_lost)
	_sal("L", false)
	_sal("R", false)
	if token != _token: return
	await _wait(0.4)
	if token != _token: return

	# 8. Goodbye
	await _say("And there goes the ball. Use up all your balls and the run is over.")
	if token != _token: return
	await _say("That's all there is to it! This old machine has more to offer: try Endless and see how many bosses you can beat.")
	if token != _token: return
	await _say("More game modes are on the way, so come back and visit. Good luck out there!")
	if token != _token: return
	_finish()


## The player launches; Sal catches the ball in a cradle. Returns "L" or "R".
## If the ball drains, a new one comes up in the launcher and we try again.
func _launch_and_catch(token: int, again: bool) -> String:
	var ball: Ball = game.ball
	var plunger: Node = game.level.get_node("Plunger")
	var tries := 0
	while true:
		var caption := "Drag the launcher down, then let go. Pull further for more power!" if _touch \
				else "Hold SPACE to pull the plunger back, then let go. Hold longer for more power!"
		if tries > 0:
			caption = "A bit more oomph this time! " + caption
		elif again:
			caption = "Here's another ball. " + caption
		await _ask("launch", "R", caption)
		if token != _token: return ""
		var left_lane: bool = await _wait_until(func() -> bool: return ball.global_position.x < 532.0 or ball.global_position.y < 280.0, 3.5)
		if token != _token: return ""
		if left_lane:
			_lock()
			break
		tries += 1
		await _wait_until(func() -> bool: return plunger.has_ball(), 3.0)
		_pause()
	_note("Off she goes! Let me catch it for you...")
	var side: String = await _catch(token)
	return side


## Sal plays the ball until it settles in a cradle. Returns "L" or "R", "" if
## the tutorial restarted, or "HIT" as soon as `stop_when` is true (ball still
## in play).
func _catch(token: int, stop_when: Callable = Callable()) -> String:
	var ball: Ball = game.ball
	_resume()
	while true:
		var lost := [false]
		var on_lost := func() -> void: lost[0] = true
		GameManager.ball_lost.connect(on_lost)
		# Play it like a person would, every physics frame: raise a flipper early
		# when the ball comes down over its body (it lands and rolls into the
		# cradle), flip when it heads for a flipper tip or the middle gap.
		var still := 0
		var flip_left := {"L": 0, "R": 0}
		var ok := false
		var start := Time.get_ticks_msec()
		var plunger: Node = game.level.get_node("Plunger")
		var nudged_this_drop := false
		while (Time.get_ticks_msec() - start) < 16000:
			await get_tree().physics_frame
			if token != _token or lost[0]:
				break
			if get_tree().paused:
				start = Time.get_ticks_msec() # the picker is open: don't time out
				continue
			if not ball.in_play or plunger.has_ball():
				lost[0] = true # it drained (maybe while we weren't looking)
				break
			if stop_when.is_valid() and stop_when.call():
				GameManager.ball_lost.disconnect(on_lost)
				return "HIT"
			# Heading down a side wall into an outlane? One nudge toward the
			# middle drops it into the inlane instead (never enough to tilt).
			var bp := ball.global_position
			if bp.y < 600.0:
				nudged_this_drop = false
			elif not nudged_this_drop and ball.linear_velocity.y > 0.0 and bp.y > 740.0 and bp.y < 805.0 \
					and GameManager.tilt_meter < 1.0:
				var dir := Vector2.ZERO
				if bp.x > 494.0 and bp.x < 540.0:
					dir = Vector2.LEFT
				elif bp.x < 66.0:
					dir = Vector2.RIGHT
				if dir != Vector2.ZERO:
					game._nudge_timer = 0.0
					game.nudge_direction(dir)
					nudged_this_drop = true
			var p := ball.global_position
			var v := ball.linear_velocity
			for s in ["L", "R"]:
				var rel: Vector2 = p - FLIPPER_PIVOT[s]
				var along: float = rel.x if s == "L" else -rel.x
				var want := false
				if flip_left[s] > 0:
					flip_left[s] -= 1
					want = true
				elif rel.y > -110.0 and rel.y < 30.0 and along > -20.0 and along < 100.0:
					if along < 58.0 or v.length() < 60.0:
						want = true # over the flipper's body: hold it up to catch
					elif v.y > 0.0 and rel.y > -50.0:
						flip_left[s] = 24 # heading for the tip / gap: flip it back up
						want = true
				if want:
					_sal(s, true)
				else:
					_sal(s, false)
			still = still + 1 if v.length() < 5.0 else 0
			if still > 60 and _near_cradle():
				ok = true
				break
		GameManager.ball_lost.disconnect(on_lost)
		if token != _token: return ""
		if ok and not lost[0]:
			var side := "L" if ball.global_position.x < 280.0 else "R"
			_sal(_other(side), false)
			# Settle it exactly (sub-pixel), so the next shot plays out the same way.
			ball.teleport(CRADLE[side])
			ball.set_velocity_safe(Vector2.ZERO)
			await _frames(20)
			return side
		_sal("L", false)
		_sal("R", false)
		if not lost[0]:
			# Stuck somewhere odd: give the cabinet a shove and keep going.
			game.nudge_direction(Vector2.UP)
			continue
		# The ball got past Sal: a new one comes up in the launcher.
		GameManager.balls_left = maxi(GameManager.balls_left, 2)
		GameManager.balls_changed.emit(GameManager.balls_left)
		await _wait_until(func() -> bool: return ball.in_play and game.level.get_node("Plunger").has_ball(), 4.0)
		_pause()
		await _say("Whoops, that one got away from me. Let's have another go.")
		if token != _token: return ""
		return await _launch_and_catch(token, true)
	return ""


## Put the cradled ball exactly on its rest point with no speed or spin (a
## sub-pixel correction nobody can see), so Sal's shots play out the same way.
func _settle(side: String) -> void:
	game.ball.teleport(CRADLE[side])
	game.ball.set_velocity_safe(Vector2.ZERO)
	await _frames(30)


func _near_cradle() -> bool:
	var p: Vector2 = game.ball.global_position
	return p.distance_to(CRADLE["L"]) < 30.0 or p.distance_to(CRADLE["R"]) < 30.0


## Leave the tutorial and return to the main menu.
func _finish() -> void:
	_token += 1
	_prompt = ""
	_waiting = false
	_bubble.visible = false
	Engine.time_scale = 1.0
	_sal("L", false)
	_sal("R", false)
	_lock() # stays locked through the fade-out; _exit_tree unlocks
	game.go_to_main_menu()


# --- Helpers ----------------------------------------------------------------------

func _pause() -> void:
	Engine.time_scale = PAUSED_SCALE


func _resume() -> void:
	Engine.time_scale = 1.0


## Sal holds a flipper up (or lets it go) without touching the player's input.
func _sal(side: String, on: bool) -> void:
	var level: Node = game.level if is_instance_valid(game) else null
	if level == null:
		return
	var flipper := level.get_node_or_null("FlipperLeft" if side == "L" else "FlipperRight")
	if flipper:
		flipper.auto_pressed = on


## Lock all the player's controls again (only dialogue keys work).
func _lock() -> void:
	GameManager.unlocked_actions.clear()


func _action(side: String) -> String:
	return "flipper_left" if side == "L" else "flipper_right"


func _other(side: String) -> String:
	return "R" if side == "L" else "L"


func _side_word(side: String) -> String:
	return "left" if side == "L" else "right"


## Real-time wait (works while the game is paused).
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Wait for `n` physics frames of game time.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait (in real time) until `cond` is true. Returns false on timeout; a negative
## timeout waits forever.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().process_frame
		if timeout >= 0.0 and (Time.get_ticks_msec() - start) / 1000.0 > timeout:
			return false
	return true


## Like _wait_until, but checks once per physics frame (for counting frames).
func _wait_until_physics(cond: Callable, timeout: float) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().physics_frame
		if timeout >= 0.0 and (Time.get_ticks_msec() - start) / 1000.0 > timeout:
			return false
	return true


func _say(text: String) -> void:
	_show_text(text, true)
	await _advance


func _note(text: String) -> void:
	_show_text(text, false)


func _show_text(text: String, wait_for_continue: bool) -> void:
	_bubble.visible = true
	_text.text = text
	_text.visible_characters = 0
	_shown_at = Time.get_ticks_msec()
	_waiting = wait_for_continue
	_hint.visible = false


## Show a prompt (keys / touch area) and wait until the player does it.
func _ask(kind: String, side: String, caption: String) -> void:
	_note(caption)
	_prompt = kind
	_prompt_side = side
	var action: String = {"launch": "launch", "flip": _action(side), "hold": _action(side)}.get(kind, "nudge")
	if not GameManager.unlocked_actions.has(action):
		GameManager.unlocked_actions.append(action)
	await _prompt_done


func _finish_prompt() -> void:
	_prompt = ""
	_resume()
	_prompt_done.emit()


func _typing_done() -> bool:
	return _text.visible_characters < 0 or _text.visible_characters >= _text.text.length()


# --- Input --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return # the pause menu or the power-up picker has the input
	if event is InputEventKey and event.is_action_pressed("pause"):
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return # a touch also arrives as a fake click: count it once
	var pos: Variant = event.position if (event is InputEventMouseButton or event is InputEventScreenTouch) else null
	if pos is Vector2 and _skip.visible and _skip.get_global_rect().has_point(pos):
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed)
	if _waiting and press:
		get_viewport().set_input_as_handled()
		if not _typing_done():
			_text.visible_characters = -1
		else:
			_waiting = false
			_hint.visible = false
			_advance.emit()
		return
	if _prompt == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match _prompt:
		"launch":
			if event.is_action_pressed("launch"):
				_finish_prompt() # keep holding: the plunger charges now
		"flip", "hold":
			if event.is_action_pressed(_action(_prompt_side)):
				_finish_prompt()
	# Nudges are read by the game itself (the clock still ticks, just slowly);
	# _on_nudged finishes the prompt.


## The power-up lesson's pick was triggered (the picker opens right after).
func _on_pick_requested(_tier: String) -> void:
	if not _expect_pick or _pick_seen:
		return
	_pick_seen = true
	_note("Pick one! Minor parts are small helpers that last the whole run.")
	# One pick is the lesson: no light gives parts for the rest of the tutorial
	# (Sal's play up top could otherwise light a set mid-explanation).
	for r in game.level.find_children("*", "Area2D", true, false):
		if "grants_powerup" in r:
			r.grants_powerup = false


func _on_nudged(_dir: Vector2) -> void:
	if _prompt != "nudge":
		return
	if _gutter != "":
		# The well-timed nudge: pop the ball over onto the other flipper.
		var v := SAVE_VELOCITY if _gutter == "L" else Vector2(-SAVE_VELOCITY.x, SAVE_VELOCITY.y)
		game.ball.set_velocity_safe(v)
		game.ball._pending_impulse = Vector2.ZERO
	_finish_prompt()


func _process(_delta: float) -> void:
	if _bubble.visible:
		var n := int((Time.get_ticks_msec() - _shown_at) / 1000.0 * CHARS_PER_SEC)
		if _text.visible_characters >= 0:
			_text.visible_characters = mini(n, _text.text.length())
		_hint.visible = _waiting and _typing_done()
		if _hint.visible:
			_hint.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 250.0)
	if _touch and not get_tree().paused:
		match _prompt:
			"launch":
				var plunger: Node = game.level.get_node_or_null("Plunger")
				if plunger and plunger._touch_active:
					_finish_prompt()
			"flip", "hold":
				if Input.is_action_pressed(_action(_prompt_side)):
					_finish_prompt()
	if _prompt == "nudge_many" and GameManager.tilted:
		_finish_prompt()
	_overlay.queue_redraw()


# --- Drawing ------------------------------------------------------------------------

func _draw_overlay() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	var font := ThemeDB.fallback_font
	for ring: Array in _rings:
		_overlay.draw_arc(ring[0], float(ring[1]) + 4.0 * pulse, 0.0, TAU, 48, Color(GOLD, 0.85), 3.0, true)
	var left := _prompt_side == "L"
	var half := Rect2(0, 975, 300, 145) if left else Rect2(300, 975, 222, 145)
	var keys: Array = ["Z", "LEFT"] if left else ["M", "RIGHT"]
	var key_x := 160.0 if left else 400.0
	match _prompt:
		"launch":
			if _touch:
				_zone(Rect2(524, 640, 72, 470), pulse)
				_swipe_arrow(Vector2(560, 760), Vector2(560, 900), t)
				_caption(font, Vector2(300, 640), "Drag down, let go")
			else:
				_keycaps(font, ["SPACE"], Vector2(430, 960), pulse)
				_caption(font, Vector2(430, 900), "Hold, then let go")
		"flip", "hold":
			var verb := "Press!" if _prompt == "flip" else "Hold!"
			if _touch:
				_zone(half, pulse)
				_caption(font, Vector2(half.get_center().x, 940), "Tap here!" if _prompt == "flip" else "Hold here!")
			else:
				_keycaps(font, keys, Vector2(key_x, 870), pulse)
				_caption(font, Vector2(key_x, 815), verb)
		"nudge", "nudge_many":
			# Gutter save: remind the player to keep that flipper up while nudging.
			if _prompt == "nudge" and _gutter != "" and Input.is_action_pressed(_action(_gutter)):
				if _touch:
					_zone(half, 0.3)
					_caption(font, Vector2(half.get_center().x, 940), "Keep holding")
				else:
					_keycaps(font, [keys[0]], Vector2(110.0 if left else 450.0, 900), 0.0)
					_caption(font, Vector2(110.0 if left else 450.0, 860), "Keep holding")
			if _touch:
				_swipe_arrow(Vector2(300, 880), Vector2(300, 740), t)
				_caption(font, Vector2(300, 700), "Swipe up!")
			else:
				_keycaps(font, ["A", "W", "D"] if _prompt == "nudge_many" else ["W"], Vector2(300, 800), pulse)
				_caption(font, Vector2(300, 745), "Nudge!" if _prompt == "nudge" else "Nudge again and again!")


func _zone(rect: Rect2, pulse: float) -> void:
	_overlay.draw_rect(rect, Color(GOLD, 0.1 + 0.12 * pulse))
	_overlay.draw_rect(rect, Color(GOLD, 0.6 + 0.3 * pulse), false, 3.0)


func _swipe_arrow(a: Vector2, b: Vector2, t: float) -> void:
	var k := fmod(t * 1.2, 1.0)
	var head := a.lerp(b, k)
	_overlay.draw_line(a, head, Color(GOLD, 0.35), 6.0, true)
	var dir := (b - a).normalized()
	var side := dir.orthogonal() * 14.0
	_overlay.draw_colored_polygon(PackedVector2Array([head + dir * 18.0, head + side, head - side]), Color(GOLD, 0.95))
	_overlay.draw_circle(head - dir * 6.0, 9.0, Color(1, 1, 1, 0.8))


func _keycaps(font: Font, keys: Array, center: Vector2, pulse: float) -> void:
	var sizes := []
	var total := 0.0
	for k: String in keys:
		var w := maxf(44.0, font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0)
		sizes.append(w)
		total += w
	total += 12.0 * (keys.size() - 1)
	var x := center.x - total * 0.5
	var grow := 2.0 * pulse
	for i in keys.size():
		var rect := Rect2(x - grow, center.y - 22.0 - grow, sizes[i] + grow * 2.0, 44.0 + grow * 2.0)
		_overlay.draw_style_box(_keycap, rect)
		_overlay.draw_string(font, Vector2(rect.position.x, center.y + 7.0), keys[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color(0.1, 0.1, 0.15))
		x += sizes[i] + 12.0


func _caption(font: Font, center: Vector2, text: String) -> void:
	var pos := Vector2(center.x - 150.0, center.y)
	_overlay.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 20, 6, Color.BLACK)
	_overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 20, GOLD)


# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_keycap = StyleBoxFlat.new()
	_keycap.bg_color = Color(0.95, 0.93, 0.85)
	_keycap.border_color = GOLD
	_keycap.set_border_width_all(3)
	_keycap.border_width_bottom = 6
	_keycap.set_corner_radius_all(8)

	_bubble = PanelContainer.new()
	_bubble.position = BUBBLE_POS
	_bubble.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.16, 0.96)
	style.border_color = Color(GOLD, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble.visible = false
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(box)
	var name_label := Label.new()
	name_label.text = SPEAKER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", GOLD)
	box.add_child(name_label)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BUBBLE_WIDTH - 28.0, 0)
	_text.add_theme_font_size_override("font_size", 19)
	_text.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	box.add_child(_text)
	_hint = Label.new()
	_hint.text = "tap or press any key"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	_hint.visible = false
	box.add_child(_hint)

	_skip = Button.new()
	_skip.text = "Skip tutorial"
	_skip.position = Vector2(BUBBLE_POS.x + BUBBLE_WIDTH - 112.0, BUBBLE_POS.y + 6.0)
	_skip.size = Vector2(106, 26)
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(_finish)
	add_child(_skip)
