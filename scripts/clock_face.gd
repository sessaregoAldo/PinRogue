class_name ClockFace
extends Node2D
## The Clock Tower's clock: drives two MovingBumpers as its hands, starting at
## 12:00 every run. The minute hand sweeps round once an hour; the hour hand
## stays put and swings to the next hour (quickly, but visibly) when the minute
## hand reaches 12.
##
## Two speeds: while the table's boss is still the ordinary blue bumper, an hour
## takes `seconds_per_hour` (30 s: twelve hours in six minutes). When the boss
## shows itself, the game stops for the reveal's dialogue; meanwhile the hands
## turn back to the hour it last struck (2:40 -> 2:00) and the pendulum settles
## at an end, so the boss picks the clock up in step, from that hour. Once play resumes it runs at
## `boss_seconds_per_hour`
## (25 s: twelve hours in five minutes). The pendulum keeps in step throughout.
##
## Striking the hour: the bell chimes once per hour (once at 1:00, twice at
## 2:00 ...), and each chime shoves the table in a random direction (never the
## same one twice in a row). Each shove pushes like a full player nudge and adds
## 0.72 of a nudge's tilt, one second apart: the bar creeps up chime by chime,
## so the twelve chimes of 12:00 tilt the machine (11 stop just short). After
## 12:00 the count starts over at 1.
## The clock starts with the first launch of the run and then keeps going,
## ball in play or not; it stops whenever the game is paused. Its rhythm is the
## pendulum's tick (a half swing), which the music's beat divides evenly: when
## the game resumes, the 3-2-1 countdown stretches so play lands back on that
## tick (resume_after), and clock and music stay in step.

signal hour_struck(hour: int)

@export var minute_hand: NodePath
@export var hour_hand: NodePath
## A sliding MovingBumper (`travel`) kept in step with the clock: it makes
## `swings_per_hour` round trips each hour, so it is at an end on every hour's
## first bell.
@export var pendulum: NodePath
@export var swings_per_hour: int = 7
## Seconds per clock hour while the boss is hidden (30: twelve hours in 6 min)...
@export var seconds_per_hour: float = 30.0
## ...and once it has shown itself (25: twelve hours in 5 min).
@export var boss_seconds_per_hour: float = 25.0
## Extra seconds the clock stands still after the boss shows itself (the
## reveal's dialogue already pauses the whole game).
@export var reveal_pause: float = 0.0
## How long the hour hand takes to swing to the next hour (seconds).
@export var hour_swing_time: float = 0.7
## Share of a player's nudge: push on the ball, and tilt added (1 = a full nudge).
@export var jolt_strength: float = 1.0
@export var jolt_tilt_share: float = 0.72
## Seconds between chimes.
@export var chime_gap: float = 1.0

var _clock_hours: float = 0.0 # clock hours gone by since 12:00 (fractional)
var _hours: int = 0 # whole hours gone by since 12:00
var _last_dir: Vector2 = Vector2.ZERO
var _striking: bool = false
var _started: bool = false
var _boss_shown: bool = false
var _pause_left: float = 0.0
## Rewinding to 12:00 at the reveal (real time, also while the game is paused).
const REWIND_TIME := 1.6
var _rewinding: bool = false
var _rw_t: float = 0.0
var _rw_from: float = 0.0
var _rw_to: float = 0.0
var _rw_pendulum_from: float = 0.0
var _strike_run: int = 0 # bumped to stop a striking in progress
## When the clock last stopped (real ms), so the countdown can land back on its
## tick; -1 while it runs. After the reveal: when the boss music began.
var _stopped_ms: int = -1
var _was_running: bool = true
var _boss_shown_just: bool = false


func _ready() -> void:
	# Runs while the game is paused too (the rewind plays during the reveal),
	# but the clock's time only moves while play is running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("clock_face") # the resume countdown asks it for its beat
	_set_hands()


## Seconds per clock hour right now.
func current_seconds_per_hour() -> float:
	return boss_seconds_per_hour if _boss_shown else seconds_per_hour


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or GameManager.is_game_over:
		return
	if _boss_shown and _boss_beaten():
		return # the boss is down: the clock stops with it
	if not _boss_shown and _boss_revealed():
		_boss_shown = true
		_pause_left = reveal_pause
		_start_rewind()
	if _rewinding:
		_rw_t += delta
		var k := smoothstep(0.0, 1.0, minf(_rw_t / REWIND_TIME, 1.0))
		_clock_hours = lerpf(_rw_from, _rw_to, k)
		_hours = int(floor(_clock_hours))
		if _rw_t >= REWIND_TIME:
			_rewinding = false
			_clock_hours = _rw_to
			_hours = int(_rw_to) # that hour counts as struck: the next chime is the one after
		_set_hands()
		return
	var running := _running()
	if running != _was_running:
		_was_running = running
		if not running and not _boss_shown_just:
			_stopped_ms = Time.get_ticks_msec()
		elif running:
			_stopped_ms = -1
	_boss_shown_just = false
	if not running:
		return
	if not _started:
		if not GameManager.ball_launched:
			return
		_started = true
	if _pause_left > 0.0:
		_pause_left -= delta
		return # the clock holds its breath
	_clock_hours += delta / current_seconds_per_hour()
	var hours := int(floor(_clock_hours))
	if hours > _hours:
		_hours = hours
		_strike(((_hours - 1) % 12) + 1)
	_set_hands()


## The clock's time moves (the game isn't paused).
func _running() -> bool:
	return not get_tree().paused


## Seconds of one tick of the clock's rhythm: the pendulum's half swing.
func tick_seconds() -> float:
	return current_seconds_per_hour() / (2.0 * maxf(swings_per_hour, 1))


## The countdown is about to run `base` seconds before play resumes: how long it
## should really take so play lands on the clock's tick, as if the clock had
## never stopped (or, after the reveal, on the boss music's beat). At least `base`,
## at most one tick more.
func resume_after(base: float) -> float:
	if not _started or _stopped_ms < 0:
		return base
	var tick := tick_seconds() * 1000.0
	var now := Time.get_ticks_msec()
	var since := float(now - _stopped_ms) + base * 1000.0
	var extra := fposmod(-since, tick)
	return base + extra / 1000.0


## The boss is here: the hands turn back to the last whole hour (the pendulum
## settles at an end, as it is on every hour), and any striking stops.
func _start_rewind() -> void:
	# The boss's music starts now: the clock picks up from its hour on that beat.
	_stopped_ms = Sfx.track_started_ms() if Sfx.has_method("track_started_ms") else Time.get_ticks_msec()
	_was_running = false
	_boss_shown_just = true
	_strike_run += 1
	_striking = false
	_rewinding = true
	_rw_t = 0.0
	_rw_from = _clock_hours
	_rw_to = floorf(_clock_hours) # always back, never forward
	_rw_pendulum_from = fposmod(_clock_hours * swings_per_hour, 1.0)


## The revealed boss is beaten.
func _boss_beaten() -> bool:
	var level := get_parent() as Level
	var boss := level.boss() if level else null
	return boss == null or boss.hp <= 0.0


## The table's boss has shown itself (it isn't the ordinary bumper any more).
func _boss_revealed() -> bool:
	var level := get_parent() as Level
	var boss := level.boss() if level else null
	return boss != null and not (boss.art in ["", "plain", "plain_dial", "splitter"])


func _set_hands() -> void:
	var bob := get_node_or_null(pendulum) as MovingBumper
	if bob and swings_per_hour > 0:
		bob.period = 0.0
		var phase := fposmod(_clock_hours * swings_per_hour, 1.0)
		if _rewinding: # straight back to the starting end, not through every swing
			var k := smoothstep(0.0, 1.0, minf(_rw_t / REWIND_TIME, 1.0))
			phase = lerpf(_rw_pendulum_from, 1.0 if _rw_pendulum_from > 0.5 else 0.0, k)
		bob.start_angle_deg = 360.0 * phase
	var minute := get_node_or_null(minute_hand) as MovingBumper
	var hour := get_node_or_null(hour_hand) as MovingBumper
	if minute:
		minute.period = 0.0
		minute.start_angle_deg = -90.0 + 360.0 * fposmod(_clock_hours, 1.0)
	if hour:
		hour.period = 0.0
		var since := (_clock_hours - _hours) * current_seconds_per_hour() # seconds into this hour
		var swing := 1.0
		if _hours > 0 and since < hour_swing_time and not _rewinding:
			swing = smoothstep(0.0, 1.0, since / hour_swing_time)
		hour.start_angle_deg = -90.0 + 30.0 * (_hours - 1 + swing) if _hours > 0 else -90.0


## Chime `hour` times, shoving the table with each chime.
func _strike(hour: int) -> void:
	if _striking:
		return
	_striking = true
	var run := _strike_run
	hour_struck.emit(hour)
	var game := get_tree().current_scene
	for i in hour:
		if not is_inside_tree() or GameManager.is_game_over or run != _strike_run:
			break
		Sfx.play("chime", -2.0, randf_range(0.97, 1.03), 0)
		if game and game.has_method("jolt"):
			game.jolt(_next_direction(), jolt_strength, jolt_tilt_share)
		if GameManager.tilted:
			break # (the game fires a ball waiting in the launcher)
		var waited := 0.0 # the gap runs whenever the clock does
		while waited < chime_gap:
			await get_tree().physics_frame
			if not is_inside_tree() or run != _strike_run:
				break
			if _running() and not _rewinding:
				waited += get_physics_process_delta_time()
	if run == _strike_run:
		_striking = false


## Left, right or up, never the same as last time.
func _next_direction() -> Vector2:
	var options: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	options.erase(_last_dir)
	_last_dir = options[randi() % options.size()]
	return _last_dir
