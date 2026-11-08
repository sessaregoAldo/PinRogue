extends Node
## Global game state (autoload "GameManager"): score, balls, tilt, and input setup.

signal score_changed(score: int)
signal balls_changed(balls: int)
signal ball_lost
signal game_over(final_score: int)
signal game_started
signal tilt_warning(level: float)
signal tilted_changed(is_tilted: bool)
signal plunger_charge_changed(charge: float)
## A floating text should appear at `world_pos` (see score_popups.gd).
signal popup_requested(text: String, world_pos: Vector2, color: Color, big: bool)
signal victory(final_score: int)
## The boss reached 0 HP: the player picks Continue or End Run (boss_menu.gd).
signal boss_beaten(info: Dictionary)
## The player chose Continue: a new round starts with all progress kept.
signal round_continued(round_number: int)
## A scoring part (bumper, slingshot, kicker) registered a hit. Used by power-ups.
@warning_ignore("unused_signal")
signal part_hit(part: Node)
## A lane set was completed: offer the player a power-up pick.
signal powerup_choice_requested
## A new table layout was loaded (game.gd). Power-ups move their multipliers onto it.
@warning_ignore("unused_signal")
signal level_changed(level: Node)

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

var score: int = 0
var balls_left: int = STARTING_BALLS
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
const BOSS_HP_GROWTH := 5.0 # next max HP = max HP x growth x overkill ratio
var boss_max_hp: int = BOSS_BASE_HP
var boss_color: Color = Palette.BOSS_START
var next_boss_hp: int = BOSS_BASE_HP
## Level the run starts on, and the level being played (indexes into LevelRegistry).
var start_level: int = 0
var current_level: int = 0
## Incremented on every restart so delayed callbacks from an old game can bail out.
var round_id: int = 0
## Option: show floating "+points" text where points are earned.
var show_score_popups: bool = true

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

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		show_score_popups = bool(cfg.get_value("gameplay", "score_popups", true))


func set_show_score_popups(on: bool) -> void:
	show_score_popups = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep the audio section
	cfg.set_value("gameplay", "score_popups", on)
	cfg.save(SETTINGS_PATH)


func _process(delta: float) -> void:
	if not tilted and tilt_meter > 0.0 and not get_tree().paused:
		tilt_meter = maxf(0.0, tilt_meter - TILT_DECAY * delta)


## Award points. Pass `at` (a world position) to show a "+points" popup there.
func add_score(points: int, at: Variant = null) -> void:
	if tilted or is_game_over:
		return
	score += points
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
	score = int(round(score * mult))
	score_changed.emit(score)
	if at is Vector2:
		var label := ("x%d" % int(mult)) if is_equal_approx(mult, roundf(mult)) else ("x" + String.num(mult, 2))
		popup(label + " SCORE!", at, Color(0.45, 1.0, 0.9), true)


func add_extra_ball() -> void:
	balls_left += 1
	balls_changed.emit(balls_left)


## Ask for a power-up pick (ignored once the game is over).
func request_powerup_choice() -> void:
	if not is_game_over:
		powerup_choice_requested.emit()


## The boss is down: count it and let the player choose what happens next.
func boss_defeated(info: Dictionary) -> void:
	if is_game_over:
		return
	bosses_defeated += 1
	next_boss_hp = int(round(float(info["max_hp"]) * BOSS_HP_GROWTH * float(info["ratio"])))
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


## 123456 -> "123,456"
func format_number(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


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
	score = 0
	balls_left = STARTING_BALLS
	tilt_meter = 0.0
	tilted = false
	is_game_over = false
	won = false
	boss_round = 1
	bosses_defeated = 0
	boss_max_hp = BOSS_BASE_HP
	boss_color = Palette.BOSS_START
	next_boss_hp = BOSS_BASE_HP
	current_level = start_level
	choosing = false
	entering_name = false
	tilt_limit_bonus = 0.0
	boss_damage_mult = 1.0
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
