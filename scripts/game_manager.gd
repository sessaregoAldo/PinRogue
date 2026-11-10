extends Node
## Global game state (autoload "GameManager"): score, balls, tilt, and input setup.

signal score_changed(score: float)
signal balls_changed(balls: int)
signal ball_lost
signal game_over(final_score: float)
signal game_started
signal tilt_warning(level: float)
signal tilted_changed(is_tilted: bool)
signal plunger_charge_changed(charge: float)
## A floating text should appear at `world_pos` (see score_popups.gd).
signal popup_requested(text: String, world_pos: Vector2, color: Color, big: bool)
signal victory(final_score: float)
## The boss reached 0 HP: the player picks Continue or End Run (boss_menu.gd).
signal boss_beaten(info: Dictionary)
## The player chose Continue: a new round starts with all progress kept.
signal round_continued(round_number: int)
## A scoring part (bumper, slingshot, kicker) registered a hit. Used by power-ups.
@warning_ignore("unused_signal")
signal part_hit(part: Node)
## A lane set was completed: offer the player a power-up pick.
## tier: "minor" (inlane lights) or "major" (the machine's lights near the boss).
signal powerup_choice_requested(tier: String)
## A new table layout was loaded (game.gd). Power-ups move their multipliers onto it.
@warning_ignore("unused_signal")
signal level_changed(level: Node)
## A drained ball was rescued by the Ball Saver power-up (no ball lost).
signal ball_saved
## Touch and nudge control settings changed (Options > Controls).
signal controls_changed

const STARTING_BALLS := 3
const TILT_WARN := 2.0
const TILT_LIMIT := 3.0
const TILT_DECAY := 0.5 # tilt meter drained per second

## Default key bindings. Actions already defined in Project Settings > Input Map
## (with at least one event) are left alone, so you can rebind there.
const DEFAULT_INPUT := {
	"flipper_left": [KEY_Z, KEY_LEFT],
	"flipper_right": [KEY_M, KEY_SLASH, KEY_RIGHT],
	"launch": [KEY_SPACE, KEY_DOWN],
	"nudge_left": [KEY_A],
	"nudge_right": [KEY_D],
	"nudge_up": [KEY_W],
	"restart": [KEY_R],
	"pause": [KEY_ESCAPE],
}

## Score and boss HP are floats (64-bit), not ints: an int tops out at about
## 9.2 quintillion, a float at about 1.8e308. Above ~1e15 small additions stop
## registering, which doesn't matter at that size (labels show 3 digits).
var score: float = 0.0
var balls_left: int = STARTING_BALLS
## True once the current ball has been fired from the launcher (until it drains).
var ball_launched: bool = false
var tilted: bool = false
var tilt_meter: float = 0.0
var is_game_over: bool = false
## True when the game ended because the level was won (boss defeated).
var won: bool = false
## Current boss round (1 = first boss) and how many bosses were beaten this run.
var boss_round: int = 1
var bosses_defeated: int = 0
## Boss progression lives here so it carries across levels.
const BOSS_BASE_HP := 100000
## Next boss's max HP = previous max HP x BOSS_HP_GROWTH x overkill ratio
##                    + score when the boss fell x BOSS_HP_SCORE_FACTOR.
## A boss hit deals the player's whole score, so the score part means the next
## boss always takes about a dozen full-score hits, however fast the score grows.
const BOSS_HP_GROWTH := 8.0
const BOSS_HP_SCORE_FACTOR := 12.0
## Keeps the next boss's HP a finite number (floats overflow to "inf" past ~1.8e308).
const BOSS_HP_CAP := 1.0e300
var boss_max_hp: float = BOSS_BASE_HP
var boss_color: Color = Palette.BOSS_START
var next_boss_hp: float = BOSS_BASE_HP
## Level the run starts on, and the level being played (indexes into LevelRegistry).
var start_level: int = 0
## True when the player picked "Random": each new run starts on a random machine.
var start_random: bool = false
var current_level: int = 0
## Incremented on every restart so delayed callbacks from an old game can bail out.
var round_id: int = 0
## Option: show floating "+points" text where points are earned.
var show_score_popups: bool = true
## Touch and mobile controls (Options > Controls).
## nudge_mode: "swipe" (swipe the upper screen) or "tilt" (jolt the phone).
var nudge_mode: String = "swipe"
## touch_controls: "auto" (shown on touch screens), "on" or "off".
var touch_controls: String = "auto"
## Game mode picked in the main menu. Only "endless" exists so far.
var game_mode: String = "endless"

# --- Run modifiers (set by power-ups, reset on restart) ---
## True while the high-score name entry is focused (blocks the pause menu / restart key).
var entering_name: bool = false
## True while the power-up picker is open (blocks the pause menu / restart key).
var choosing: bool = false
## Extra nudges allowed before TILT.
var tilt_limit_bonus: float = 0.0
## Tilt meter added per nudge (set by main.gd from its nudge_tilt_cost).
var nudge_cost: float = 1.0
## Multiplier applied to boss damage.
var boss_damage_mult: float = 1.0
## Ball Saver: seconds after each launch during which a drain is forgiven.
var ball_save_seconds: float = 0.0
## Turbo Ramps stacks: boosters fire from the entrance; ramps score +100% each.
var ramp_turbo: int = 0
## Boss Magnet stacks: the boss pulls nearby balls in.
var boss_magnet: int = 0
## Combo Master: extra share of the score added by a button combination.
var combo_bonus_extra: float = 0.0
## Tutorial: the player's flippers, plunger and nudges are locked, except the
## actions in unlocked_actions ("flipper_left", "flipper_right", "launch", "nudge").
var input_locked: bool = false
var unlocked_actions: Array[String] = []
## Bouncy Ball: how bouncy the ball is (1.0 = normal, +0.1 per stack).
var ball_bounce_mult: float = 1.0
var _save_timer: float = 0.0

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		show_score_popups = bool(cfg.get_value("gameplay", "score_popups", true))
		nudge_mode = str(cfg.get_value("controls", "nudge_mode", nudge_mode))
		touch_controls = str(cfg.get_value("controls", "touch_controls", touch_controls))


func set_show_score_popups(on: bool) -> void:
	show_score_popups = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep the audio section
	cfg.set_value("gameplay", "score_popups", on)
	cfg.save(SETTINGS_PATH)


func _process(delta: float) -> void:
	if not tilted and tilt_meter > 0.0 and not get_tree().paused:
		tilt_meter = maxf(0.0, tilt_meter - TILT_DECAY * delta)
	if _save_timer > 0.0 and not get_tree().paused:
		_save_timer = maxf(0.0, _save_timer - delta)


## Award points. Pass `at` (a world position) to show a "+points" popup there.
func add_score(points: float, at: Variant = null) -> void:
	if tilted or is_game_over:
		return
	score = minf(score + points, BOSS_HP_CAP)
	score_changed.emit(score)
	if at is Vector2:
		popup("+" + format_number(points), at, Color(1.0, 0.9, 0.4), points >= 1000)


## Show a floating text at a world position (only if the option is on;
## score_popups.gd checks that).
func popup(text: String, at: Vector2, color: Color = Color.WHITE, big: bool = false) -> void:
	popup_requested.emit(text, at, color, big)


## Multiply the player's total score (power-up multipliers).
func multiply_score(mult: float, at: Variant = null) -> void:
	if tilted or is_game_over:
		return
	score = minf(roundf(score * mult), BOSS_HP_CAP)
	score_changed.emit(score)
	if at is Vector2:
		var label := ("x%d" % int(mult)) if is_equal_approx(mult, roundf(mult)) else ("x" + String.num(mult, 2))
		popup(label + " SCORE!", at, Color(0.45, 1.0, 0.9), true)


func add_extra_ball() -> void:
	balls_left += 1
	balls_changed.emit(balls_left)


## Ask for a power-up pick (ignored once the game is over).
func request_powerup_choice(tier: String = "major") -> void:
	if not is_game_over:
		powerup_choice_requested.emit(tier)


## The boss is down: count it and let the player choose what happens next.
func boss_defeated(info: Dictionary) -> void:
	if is_game_over:
		return
	bosses_defeated += 1
	next_boss_hp = minf(roundf(float(info["max_hp"]) * BOSS_HP_GROWTH * float(info["ratio"]) \
			+ score * BOSS_HP_SCORE_FACTOR), BOSS_HP_CAP)
	info["next_max_hp"] = next_boss_hp
	Sfx.play("victory")
	boss_beaten.emit(info)


## Continue the run: keep score, balls and power-ups; the boss returns stronger.
func continue_run() -> void:
	boss_round += 1
	boss_max_hp = next_boss_hp
	boss_color = Palette.random_boss_color(boss_color)
	round_continued.emit(boss_round)


## End the level as a win.
func declare_victory() -> void:
	if is_game_over:
		return
	is_game_over = true
	won = true
	victory.emit(score)


## 123456 -> "123,456". Beyond what a float stores exactly (~1e15) it switches
## to the short form ("1.25Q"), since the extra digits would be noise anyway.
func format_number(n: float) -> String:
	if absf(n) >= 1.0e15:
		return format_short(n)
	var digits := str(absi(int(n)))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0.0 else "") + digits + out


func add_tilt(amount: float) -> void:
	if tilted or is_game_over:
		return
	tilt_meter += amount
	if tilt_meter >= TILT_LIMIT + tilt_limit_bonus:
		tilted = true
		tilted_changed.emit(true)
		Sfx.play("tilt")
	elif tilt_meter >= TILT_WARN + tilt_limit_bonus:
		tilt_warning.emit(tilt_meter)
		Sfx.play("warning")


func ball_drained() -> void:
	if is_game_over:
		return
	ball_launched = false
	if _save_timer > 0.0: # Ball Saver: this ball comes back
		_save_timer = 0.0
		Sfx.play("ramp_complete")
		ball_saved.emit()
		return
	Sfx.play("drain")
	balls_left -= 1
	balls_changed.emit(balls_left)
	tilt_meter = 0.0
	if tilted:
		tilted = false
		tilted_changed.emit(false)
	if balls_left <= 0:
		is_game_over = true
		game_over.emit(score)
	else:
		ball_lost.emit()


func set_plunger_charge(charge: float) -> void:
	plunger_charge_changed.emit(charge)


func restart() -> void:
	round_id += 1
	score = 0.0
	balls_left = STARTING_BALLS
	ball_launched = false
	tilt_meter = 0.0
	tilted = false
	is_game_over = false
	won = false
	boss_round = 1
	bosses_defeated = 0
	boss_max_hp = float(BOSS_BASE_HP)
	boss_color = Palette.BOSS_START
	next_boss_hp = float(BOSS_BASE_HP)
	if start_random:
		start_level = randi() % LevelRegistry.count()
	current_level = start_level
	choosing = false
	input_locked = false
	unlocked_actions.clear()
	entering_name = false
	tilt_limit_bonus = 0.0
	boss_damage_mult = 1.0
	ball_save_seconds = 0.0
	ramp_turbo = 0
	boss_magnet = 0
	combo_bonus_extra = 0.0
	ball_bounce_mult = 1.0
	_save_timer = 0.0
	score_changed.emit(score)
	balls_changed.emit(balls_left)
	tilted_changed.emit(false)
	game_started.emit()


func _setup_input() -> void:
	for action: String in DEFAULT_INPUT:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if not InputMap.action_get_events(action).is_empty():
			continue
		for key: int in DEFAULT_INPUT[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
	_load_key_bindings()


# --- Key bindings (Settings > Controls) -------------------------------------------

## Actions the player can rebind, in menu order, with their names.
const BINDABLE: Array[String] = ["flipper_left", "flipper_right", "launch", "nudge_left", "nudge_up", "nudge_right", "pause", "restart"]
const ACTION_NAMES := {
	"flipper_left": "Left flipper", "flipper_right": "Right flipper", "launch": "Launch",
	"nudge_left": "Nudge left", "nudge_up": "Nudge up", "nudge_right": "Nudge right",
	"pause": "Pause", "restart": "Restart",
}
const KEY_SYMBOLS := {"Slash": "/", "Backslash": "\\", "Comma": ",", "Period": ".", "Semicolon": ";",
	"Apostrophe": "'", "Bracketleft": "[", "Bracketright": "]", "Minus": "-", "Equal": "=", "Quoteleft": "`"}


func _load_key_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK or not cfg.has_section("keys"):
		return
	for action in BINDABLE:
		var codes: Array = cfg.get_value("keys", action, [])
		if not codes.is_empty():
			_set_keys(action, codes)


## Replace an action's keyboard keys (physical key codes).
func _set_keys(action: String, codes: Array) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for code in codes:
		var ev := InputEventKey.new()
		ev.physical_keycode = int(code) as Key
		InputMap.action_add_event(action, ev)


## The physical key codes bound to an action.
func key_codes(action: String) -> Array[int]:
	var out: Array[int] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(int(ev.physical_keycode) if ev.physical_keycode != KEY_NONE else int(ev.keycode))
	return out


## Bind `action` to one key. The key is taken off any other action that had it.
func bind_key(action: String, code: int) -> void:
	for other in BINDABLE:
		if other != action and key_codes(other).has(code):
			var rest := key_codes(other)
			rest.erase(code)
			_set_keys(other, rest)
	_set_keys(action, [code])
	_save_keys()


func reset_keys() -> void:
	for action in BINDABLE:
		_set_keys(action, DEFAULT_INPUT[action])
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	cfg.save(SETTINGS_PATH)


func _save_keys() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep the other sections
	for action in BINDABLE:
		cfg.set_value("keys", action, key_codes(action))
	cfg.save(SETTINGS_PATH)


## Readable names of an action's keys, e.g. ["Z", "Left"].
func key_names(action: String) -> Array[String]:
	var out: Array[String] = []
	for code in key_codes(action):
		out.append(key_name(code))
	return out


## "Z or Left" (or "unbound").
func key_label(action: String, joiner: String = " or ") -> String:
	var names := key_names(action)
	return joiner.join(names) if not names.is_empty() else "unbound"


## Name of a physical key on the player's keyboard layout.
func key_name(code: int) -> String:
	var mapped := code
	if not OS.has_feature("web"):
		var k := DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		if k != KEY_NONE:
			mapped = k
	var s := OS.get_keycode_string(mapped as Key)
	return KEY_SYMBOLS.get(s, s)


## Called when the plunger fires: starts the Ball Saver window (if owned).
func mark_launch() -> void:
	_save_timer = ball_save_seconds
	if not ball_launched:
		ball_launched = true
		balls_changed.emit(balls_left)


## Balls left to come after the one on the table: the HUD counter. A ball
## waiting in the launcher still counts; it stops counting once it is fired.
func spare_balls() -> int:
	return maxi(0, balls_left - (1 if ball_launched else 0))


## A fresh ball was put in the launcher (new run, new machine, ball saved).
func ball_reset_to_launcher() -> void:
	if ball_launched:
		ball_launched = false
		balls_changed.emit(balls_left)


## Seconds left on the Ball Saver for the current ball (0 = not protected).
func ball_save_remaining() -> float:
	return _save_timer


## Compact number for small labels, never more than 3 digits:
## 950 -> "950", 1000 -> "1.0K", 69900 -> "69.9K", 999499 -> "999K",
## 999999 -> "1.0M", 1250000 -> "1.25M", 12500000 -> "12.5M", then B, T, Q,
## then letter pairs: Aa, Ab ... Az, Ba ... (each one 1000x the last).
func format_short(n: float) -> String:
	var prefix := "-" if n < 0.0 else ""
	var v := absf(n)
	if v < 1000.0:
		return prefix + str(int(v))
	var u := 0
	v /= 1000.0
	while v >= 999.5: # would round to 1000: move up a unit (999.6K -> 1.0M)
		v /= 1000.0
		u += 1
	return prefix + _three_digits(v) + _unit_name(u)


## 0 = K, 1 = M, 2 = B, 3 = T, 4 = Q, then 5 = Aa, 6 = Ab ... 30 = Az, 31 = Ba ...
func _unit_name(index: int) -> String:
	const NAMED := ["K", "M", "B", "T", "Q"]
	if index < NAMED.size():
		return NAMED[index]
	var i := index - NAMED.size()
	return char(65 + (i / 26) % 26) + char(97 + i % 26)


## 1.0 -> "1.0", 1.25 -> "1.25", 12.5 -> "12.5", 999.4 -> "999".
func _three_digits(v: float) -> String:
	if v >= 99.95:
		return str(int(round(v)))
	if v >= 9.995:
		return "%.1f" % v
	var text := "%.2f" % v
	return text.trim_suffix("0") if text.ends_with("0") else text


## May the player use this action right now? (Always, outside the tutorial.)
func player_can(action: String) -> bool:
	return not input_locked or unlocked_actions.has(action)


func set_nudge_mode(mode: String) -> void:
	nudge_mode = mode
	_save_controls()


func set_touch_controls(mode: String) -> void:
	touch_controls = mode
	_save_controls()


func _save_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep the other sections
	cfg.set_value("controls", "nudge_mode", nudge_mode)
	cfg.set_value("controls", "touch_controls", touch_controls)
	cfg.save(SETTINGS_PATH)
	controls_changed.emit()
