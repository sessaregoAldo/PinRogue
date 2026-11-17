@tool
class_name BossBumper
extends Bumper
## A big bumper whose inner disc is a round health dial. Every hit deals damage;
## at 0 HP the level is won.
## The colored slice is the remaining health, starting at 12 o'clock. The lost
## share is left uncolored, as a wedge proportional to the percentage lost.
## By default a hit deals damage equal to the player's current total score,
## so building score elsewhere on the table makes each boss hit stronger.
##
## Rounds: at 0 HP the player chooses Continue or End Run (see boss_menu.gd).
## The boss's max HP and color come from the run (GameManager.boss_max_hp /
## boss_color), so they carry over when Continue loads a different level. On
## Continue the next boss gets
##     previous max HP x 8 x (total damage dealt / previous max HP)
##     + the player's score x 12
## (GameManager.BOSS_HP_GROWTH / BOSS_HP_SCORE_FACTOR), plus a new red-family color.

enum DamageMode {
	CURRENT_SCORE, ## damage = player's total score at the moment of the hit
	HIT_POINTS, ## damage = this bumper's score_value
}

@export var max_hp: float = 100000.0
@export var damage_mode: DamageMode = DamageMode.CURRENT_SCORE
## Size of the health dial as a fraction of the bumper radius.
@export_range(0.3, 0.95) var dial_ratio: float = 0.68
## Show the remaining HP as a number in the middle of the dial.
@export var show_hp_number: bool = true

## Story mode: emitted at 0 HP instead of opening the Endless boss menu.
signal depleted(info: Dictionary)
## Emitted on every damaging hit (story mode statistics).
signal damaged(amount: float)

## Story mode: the StoryDirector decides what happens at 0 HP.
var story_controlled: bool = false
## Story mode: (ball) -> damage multiplier for this hit (a boss gimmick's bonus).
var hit_multiplier: Callable = Callable()
## Story mode: when above 0, every hit deals exactly this (a phase counted in hits).
## The health bar then shows one segment per hit.
var fixed_damage: float = 0.0
## Look: "" = the health dial; "plain" = an ordinary bumper with a health bar
## above it (story phase 1); "splitter" = the dial, cracked down the middle;
## "collector" = the dial in a gold, coin-milled rim with a jeweller's loupe;
## "clock" = a white face with two dots (its hands' tips) that turn to watch the ball.
## A table can pick it in the scene (story mode may change it).
@export var art: String = "":
	set(value):
		art = value
		queue_redraw()

## "clock": the hands' angles, and how fast each turns toward the ball (rad/s).
var _minute_angle: float = -PI * 0.5
var _hour_angle: float = -PI * 0.5
const MINUTE_HAND_SPEED := 3.5
const HOUR_HAND_SPEED := 1.1
const CLOCK_WHITE := Color(0.95, 0.94, 0.9)
const CLOCK_INK := Color(0.12, 0.11, 0.14)
const CRACKS := 9

## Outside story mode: start as an ordinary blue bumper (health dial as usual);
## when that is beaten, the boss shows itself in this art with a new, bigger
## health pool, and beating that ends the round. "" = the boss from the start.
@export var reveal_art: String = ""
## The revealed boss's health: at least this many times the bumper's, and at
## least the score at the reveal times `reveal_score_factor`.
@export var reveal_hp_ratio: float = 2.0
@export var reveal_score_factor: float = 96.0
## The ordinary bumper's own health (0 = the round's usual boss health), and a
## floor for the revealed boss's.
@export var plain_hp: float = 0.0
@export var reveal_min_hp: float = 0.0
## What is said at the reveal (outside story mode): a narration, then the
## Ghost's lines. The game waits for them, then counts down 3-2-1.
@export var reveal_lines: PackedStringArray = PackedStringArray()
@export var reveal_reply: PackedStringArray = PackedStringArray()
var _hidden_art: String = ""

## Drawing size during the reveal's pop-in (the body itself never scales).
var _pop: float = 1.0

var hp: float = 0.0
var _shown_hp: float = 0.0 # animated value the dial draws
var _hurt: float = 0.0 # white flash on the dial when damaged
## The ramp-loop strike (begin_strike / land_strike): spinning, the moment
## the strike lands and its damage factor, and the shake.
const STRIKE_TURNS_PER_SECOND := 2.5
const STRIKE_SETTLE := 0.35
## A strike that never lands (the ball left the loop some other way) gives up.
const STRIKE_GIVE_UP := 5.0
var _striking: bool = false
var _strike_age: float = 0.0
var _landing: float = 0.0
var _land_from: float = 0.0
var _land_to: float = 0.0
var _strike_factor: float = 0.0
var _spin: float = 0.0
var _shake: Vector2 = Vector2.ZERO
## What _draw draws through (pop-in scale, the strike's spin and shake).
var _base_xform: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		max_hp = GameManager.boss_max_hp
		color = GameManager.boss_color
		if reveal_art != "" and GameManager.game_mode != "story":
			_hidden_art = reveal_art
			art = "plain_dial" # the ordinary bumper comes first
			if plain_hp > 0.0:
				max_hp = plain_hp
	hp = max_hp
	_shown_hp = hp


## The ordinary bumper (blue, or the cracked one before a story table switch)
## is still up: the boss hasn't shown itself yet.
func is_plain() -> bool:
	return art in ["plain", "plain_dial"] or (art == "splitter" and fixed_damage > 0.0) or _hidden_art != ""


## Developer testing: beat it at once, as if one hit took all its health (a
## phase counted in hits takes those hits): the ordinary bumper (on to the
## reveal) or the boss itself (the round / the chapter is won).
func debug_beat() -> void:
	if hp <= 0.0:
		return
	if fixed_damage > 0.0:
		while hp > 0.0:
			_apply_damage(fixed_damage)
	else:
		_apply_damage(hp)


func _after_hit(ball: Ball) -> void:
	if hp <= 0:
		return
	var damage: float = GameManager.score if damage_mode == DamageMode.CURRENT_SCORE else float(score_value)
	if fixed_damage > 0.0:
		damage = fixed_damage
	else:
		var bonus := 1.0
		if hit_multiplier.is_valid():
			bonus = float(hit_multiplier.call(ball))
		damage = maxf(roundf(damage * GameManager.boss_damage_mult * GameManager.story_damage_bonus * bonus), 1.0)
	_apply_damage(damage)


func _apply_damage(damage: float) -> void:
	var total_damage := (max_hp - hp) + damage # includes the overkill of this hit
	hp = maxf(0.0, hp - damage)
	_hurt = 1.0
	if fixed_damage <= 0.0:
		GameManager.popup("-%s HP" % GameManager.format_short(damage),
				global_position + Vector2(0, -radius - 16), Color(1.0, 0.35, 0.3), true)
	damaged.emit(damage)
	if hp <= 0.0:
		var info := { # GameManager adds "next_max_hp"
			"max_hp": max_hp,
			"total_damage": total_damage,
			"ratio": float(total_damage) / float(max_hp),
		}
		if story_controlled:
			depleted.emit(info) # (the StoryDirector shatters it where it fits)
		elif _hidden_art != "":
			_reveal()
		else:
			shatter(true) # beaten: it bursts and is gone until the next machine
			GameManager.boss_defeated(info)


## The ordinary bumper is beaten: the boss shows itself (outside story mode).
## The game stops: the blue cap bursts apart, the boss's face pops up in its
## place, its lines are said (the player taps through or skips), then the usual
## 3-2-1 countdown and play goes on.
func _reveal() -> void:
	var boss_art := _hidden_art
	_hidden_art = ""
	GameManager.choosing = true
	get_tree().paused = true
	set_hp(maxf(maxf(max_hp * reveal_hp_ratio, roundf(GameManager.score * reveal_score_factor)), reveal_min_hp))
	Sfx.play("guard_break")
	_burst(_body_color())
	var keep := process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS # its pop-in plays while the game waits
	modulate.a = 0.0
	await get_tree().create_timer(0.45, true, false, true).timeout
	art = boss_art
	_pop = 0.3
	modulate.a = 1.0
	_flash = 1.0
	Sfx.play("chime", -4.0, 0.8, 0)
	var pop := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pop.tween_method(func(v: float) -> void:
		_pop = v
		queue_redraw(), 0.3, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var table := owner as Level
	if table and not table.boss_music.is_empty():
		Sfx.play_playlist(Array(table.boss_music))
	await get_tree().create_timer(0.7, true, false, true).timeout
	if not reveal_lines.is_empty() or not reveal_reply.is_empty():
		var box := DialogueBox.new()
		box.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().current_scene.add_child(box)
		box.begin_scene()
		if not reveal_lines.is_empty():
			await box.say("", Array(reveal_lines))
		if not reveal_reply.is_empty():
			await box.say(StoryData.GHOST, Array(reveal_reply))
		box.queue_free()
	process_mode = keep
	if not is_inside_tree():
		return
	GameManager.choosing = false
	GameManager.resume_play() # the 3-2-1 countdown, then the game goes on


## The bumper breaks: shards of its cap fly out and fade (also while paused,
## and in slow motion). With `hide`, it is gone afterwards.
func shatter(hide: bool = false) -> void:
	_burst(_body_color())
	if hide:
		modulate.a = 0.0


## The color of the bumper's cap as it looks now (its shards are this color).
func _body_color() -> Color:
	match art:
		"plain", "plain_dial":
			return Palette.BUMPER if Engine.is_editor_hint() else Cosmetics.bumper_color()
		"collector":
			return Color(0.45, 0.33, 0.12).lightened(0.25)
		"clock":
			return CLOCK_WHITE
	return color


## Shards of the bumper's cap flying out and fading (plays while paused).
func _burst(cap: Color) -> void:
	var fx := Node2D.new()
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	fx.z_index = z_index + 2
	fx.global_position = global_position
	get_parent().add_child(fx)
	var shards: Array = []
	for i in 14:
		var a := TAU * i / 14.0 + randf_range(-0.2, 0.2)
		shards.append({"dir": Vector2.from_angle(a), "speed": randf_range(140.0, 260.0), "spin": randf_range(-9.0, 9.0),
				"size": randf_range(6.0, 11.0)})
	var t := [0.0]
	fx.draw.connect(func() -> void:
		var k: float = t[0]
		for s: Dictionary in shards:
			var at: Vector2 = s["dir"] * (radius * 0.6 + float(s["speed"]) * k) + Vector2(0, 260.0 * k * k)
			var r: float = s["size"]
			var rot: float = float(s["spin"]) * k
			var pts := PackedVector2Array()
			for j in 3:
				pts.append(at + Vector2.from_angle(rot + TAU * j / 3.0) * r)
			fx.draw_colored_polygon(pts, Color(cap, 1.0 - k / 0.8)))
	var tw := fx.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void:
		t[0] = v
		fx.queue_redraw(), 0.0, 0.8, 0.8)
	tw.tween_callback(fx.queue_free)


## Give the boss a new health pool (story mode: the reveal, the Splitter).
## The ramp-loop strike, part one: start spinning counter-clockwise (the way
## the ball goes round him), blinking and shaking, until land_strike().
func begin_strike() -> void:
	if hp <= 0.0 or _striking:
		return
	_striking = true
	_strike_age = 0.0
	_landing = 0.0
	Sfx.play("powerup", -2.0, 0.7)


## Part two: the loop is done. Settle over STRIKE_SETTLE seconds, then take
## the player's score x `factor` (at that moment) as damage.
func land_strike(factor: float) -> void:
	if not _striking:
		begin_strike()
		if not _striking:
			return
	if _landing > 0.0:
		return
	_strike_factor = factor
	_landing = STRIKE_SETTLE
	_land_from = _spin
	_land_to = floorf(_spin / TAU) * TAU # carry on round to the next upright


func _update_strike(delta: float) -> void:
	if not _striking:
		return
	_strike_age += delta
	var settled := false
	if _strike_factor > 0.0: # landing
		_landing = maxf(0.0, _landing - delta)
		var k := 1.0 - _landing / STRIKE_SETTLE
		_spin = lerpf(_land_from, _land_to, 1.0 - pow(1.0 - k, 3.0))
		settled = _landing <= 0.0
	else:
		var speed := TAU * STRIKE_TURNS_PER_SECOND * minf(1.0, _strike_age / 0.4)
		_spin -= speed * delta # negative: counter-clockwise on screen
	var amount := 5.0 if _strike_factor <= 0.0 else 5.0 * _landing / STRIKE_SETTLE
	_shake = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
	_flash = 1.0 if int(_strike_age * 12.0) % 2 == 0 else 0.0
	_hurt = _flash * 0.6
	if settled or (_strike_factor <= 0.0 and _strike_age > STRIKE_GIVE_UP):
		var factor := _strike_factor
		_striking = false
		_strike_factor = 0.0
		_spin = 0.0
		_shake = Vector2.ZERO
		_flash = 0.0
		_hurt = 0.0
		if settled and hp > 0.0:
			Sfx.play("guard_break")
			var damage := fixed_damage if fixed_damage > 0.0 else maxf(roundf(GameManager.score * factor), 1.0)
			_apply_damage(damage)
	queue_redraw()


func set_hp(new_max: float, current: float = -1.0) -> void:
	max_hp = maxf(new_max, 1.0)
	hp = max_hp if current < 0.0 else clampf(current, 0.0, max_hp)
	_shown_hp = hp
	queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	_update_strike(delta)
	if art == "clock" and not Engine.is_editor_hint():
		_watch_ball(delta)
	if absf(_shown_hp - hp) > maxf(0.5, max_hp * 1e-6) or _hurt > 0.0:
		_shown_hp = lerpf(_shown_hp, hp, 1.0 - exp(-8.0 * delta))
		if absf(_shown_hp - hp) <= maxf(0.5, max_hp * 1e-6):
			_shown_hp = hp
		_hurt = maxf(0.0, _hurt - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	_base_xform = Transform2D(_spin, Vector2.ONE * _pop, 0.0, _shake)
	if _base_xform != Transform2D.IDENTITY:
		draw_set_transform_matrix(_base_xform)
	if art == "plain":
		_draw_plain()
		return
	if art == "clock":
		_draw_clock_face()
		return
	# The Collector is all coin: an old-gold body instead of the boss red.
	# "plain_dial" is an ordinary bumper's blue with the Endless boss's dial.
	var plain_blue := Palette.BUMPER if Engine.is_editor_hint() else Cosmetics.bumper_color()
	var body := Color(0.45, 0.33, 0.12) if art == "collector" else (plain_blue if art == "plain_dial" else color)
	var fill := body.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + _flash * 6.0, body.darkened(0.5))
	draw_circle(Vector2.ZERO, radius, fill)

	# Health dial: dark disc = lost health, colored slice = remaining health.
	var r := radius * dial_ratio
	# The Collector's dial is emerald, so he reads apart from the plain bumper and the Splitter.
	var core := Color(0.1, 0.72, 0.42) if art == "collector" else body
	draw_circle(Vector2.ZERO, r, core.darkened(0.78))
	var ratio := clampf(_shown_hp / float(max_hp), 0.0, 1.0)
	var health_color := core.lightened(0.35).lerp(Color.WHITE, _hurt * 0.5)
	if ratio >= 0.999:
		draw_circle(Vector2.ZERO, r, health_color)
	elif ratio > 0.0:
		var segments := maxi(2, int(64.0 * ratio))
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in segments + 1:
			# From 12 o'clock, clockwise (angles grow clockwise with y pointing down).
			var angle := -PI * 0.5 + TAU * ratio * float(i) / segments
			pts.append(Vector2.from_angle(angle) * r)
		draw_colored_polygon(pts, health_color)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(core.lightened(0.6), 0.7), 1.5, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 2.0, true)

	if art == "splitter":
		_draw_crack()
		if fixed_damage > 0.0:
			var broken := hp <= 0.0
			_draw_hit_cracks(roundi((max_hp - hp) / fixed_damage) + (1 if broken else 0))
			if broken: # the cap gives way: its old crack opens up
				var crack := crack_points(radius)
				draw_polyline(crack, Color(0, 0, 0, 1.0), 10.0, true)
				draw_polyline(crack, Color(1.0, 0.55, 0.25, 0.9), 2.0, true)
	elif art == "collector":
		_draw_collector()

	if show_hp_number and fixed_damage <= 0.0: # a phase counted in hits shows cracks, not numbers
		var font := ThemeDB.fallback_font
		var text := GameManager.format_short(hp) if not Engine.is_editor_hint() else _short_number(hp)
		var pos := Vector2(-r, 5)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, Color.WHITE)


## Art "clock": a plain white face with just the tips of its two hands, as
## two small upright ovals (no dial, marks or number). It flashes on a hit like any bumper.
func _draw_clock_face() -> void:
	# Its health shows only as red: zigzag cracks creep in from the rim as it is
	# hurt, and near the end the whole face floods red.
	var hurt := 1.0 - clampf(_shown_hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var red := Color(0.8, 0.08, 0.1)
	var face := CLOCK_WHITE.lerp(red, smoothstep(0.55, 1.0, hurt) * 0.92)
	face = face.lerp(Color(1.0, 0.8, 0.75), _hurt * 0.4)
	draw_circle(Vector2.ZERO, radius + _flash * 6.0, face)
	if hurt > 0.0:
		var reach := radius * minf(hurt * 1.15, 0.95) # how far in from the rim
		var width := 1.4 + hurt * 2.6
		for i in CRACKS:
			var a := TAU * i / CRACKS + 0.37 * sin(i * 2.3)
			var dir := Vector2.from_angle(a)
			var side := dir.orthogonal()
			var pts := PackedVector2Array([dir * radius])
			var steps := 6
			for k in range(1, steps + 1):
				var depth := reach * k / steps
				var wiggle := (3.0 + hurt * 2.0) * (1.0 if k % 2 == 1 else -1.0) * (1.0 - float(k) / (steps + 1))
				pts.append(dir * (radius - depth) + side * wiggle)
			draw_polyline(pts, Color(red, 0.55 + hurt * 0.45), width, true)
	# Just the hands' tips: two small dots, like a pair of eyes following the ball.
	_draw_oval(_hour_angle, radius * 0.5, 5.2)
	_draw_oval(_minute_angle, radius * 0.78, 4.2)


## A small oval `dist` from the middle at `angle`, fixed to its hand like a
## hammer head on a stick: its long side lies square to the hand and faces out,
## so it turns with the hand as the hand follows the ball.
func _draw_oval(angle: float, dist: float, size: float) -> void:
	# Stretch first, then turn (draw_set_transform would stretch after turning,
	# which leaves the oval upright whatever the angle).
	var across := Vector2.from_angle(angle) * 0.78 # short side, along the hand
	var along := Vector2.from_angle(angle + PI * 0.5) * 1.25 # long side, square to it
	draw_set_transform_matrix(_base_xform * Transform2D(across, along, Vector2.from_angle(angle) * dist))
	draw_circle(Vector2.ZERO, size, CLOCK_INK)
	draw_set_transform_matrix(_base_xform)


## Art "clock": both hands turn toward the nearest ball, the minute hand
## quickly and the hour hand lazily, as if the face were watching it.
func _watch_ball(delta: float) -> void:
	var nearest: Node2D = null
	var best := INF
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball and ball.in_play:
			var d := ball.global_position.distance_squared_to(global_position)
			if d < best:
				best = d
				nearest = ball
	if nearest == null:
		return
	var target := (nearest.global_position - global_position).angle()
	_minute_angle = rotate_toward(_minute_angle, target, MINUTE_HAND_SPEED * delta)
	_hour_angle = rotate_toward(_hour_angle, target, HOUR_HAND_SPEED * delta)
	queue_redraw()


## The zigzag line the Splitter breaks along (shared with its two halves).
static func crack_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var y := lerpf(-r, r, float(i) / steps)
		var x := 0.0 if i == 0 or i == steps else (r * 0.16 if i % 2 == 1 else -r * 0.14)
		pts.append(Vector2(x, y))
	return pts


## Story art "splitter": one half in shadow and a crack down the middle.
func _draw_crack() -> void:
	var crack := crack_points(radius)
	var shade := PackedVector2Array(crack)
	for i in range(1, 12): # right half of the rim, bottom to top (ends are on the crack)
		shade.append(Vector2.from_angle(PI * 0.5 - PI * float(i) / 12.0) * radius)
	draw_colored_polygon(shade, Color(0, 0, 0, 0.3))
	draw_polyline(crack, Color(0, 0, 0, 0.9), 5.0, true)
	draw_polyline(crack, Color(1, 1, 1, 0.85), 1.5, true)


## Fresh cracks for a phase counted in hits: one more per hit, each running in
## from the rim, the last ones splitting the cap apart.
const HIT_CRACKS := [
	[1.95, [Vector2(0.62, 0.0), Vector2(0.4, 0.12), Vector2(0.22, -0.05)]],
	[0.55, [Vector2(0.7, 0.1), Vector2(0.42, -0.08), Vector2(0.15, 0.06)]],
	[3.75, [Vector2(0.75, -0.06), Vector2(0.5, 0.1), Vector2(0.3, -0.04), Vector2(0.05, 0.03)]],
	[2.85, [Vector2(0.7, 0.08), Vector2(0.45, -0.1), Vector2(0.2, 0.05)]],
]

func _draw_hit_cracks(count: int) -> void:
	for i in mini(count, HIT_CRACKS.size()):
		var angle: float = HIT_CRACKS[i][0]
		var pts := PackedVector2Array([Vector2.from_angle(angle) * radius])
		for p: Vector2 in HIT_CRACKS[i][1]:
			# p.x: distance from the center (share of the radius); p.y: sideways kink.
			pts.append((Vector2.from_angle(angle) * p.x + Vector2.from_angle(angle + PI * 0.5) * p.y) * radius)
		draw_polyline(pts, Color(0, 0, 0, 0.9), 4.0, true)
		draw_polyline(pts, Color(1, 1, 1, 0.8), 1.2, true)
		# A chip knocked out where the crack meets the rim.
		var rim := Vector2.from_angle(angle) * radius
		draw_colored_polygon(PackedVector2Array([rim + Vector2.from_angle(angle + 1.9) * 7.0, rim,
				rim + Vector2.from_angle(angle - 1.9) * 7.0]), Color(0, 0, 0, 0.7))


## Story art "collector": a gold rim milled like a coin's edge, and a loupe.
func _draw_collector() -> void:
	var gold := Color(1.0, 0.8, 0.32)
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 48, gold, 4.0, true)
	for i in 40:
		var dir := Vector2.from_angle(TAU * i / 40.0)
		draw_line(dir * (radius - 4.0), dir * (radius + 1.0), gold.darkened(0.35), 1.5)
	var loupe := Vector2(radius * 0.52, -radius * 0.5)
	draw_circle(loupe, radius * 0.26, Color(0.85, 0.95, 1.0, 0.35))
	draw_arc(loupe, radius * 0.26, 0.0, TAU, 24, gold, 2.5, true)
	draw_arc(loupe + Vector2(-radius * 0.05, -radius * 0.05), radius * 0.15, PI * 1.1, PI * 1.5, 8, Color(1, 1, 1, 0.8), 1.5, true)
	# Its chain, hanging down the bumper's side.
	draw_polyline(PackedVector2Array([loupe + Vector2(radius * 0.2, radius * 0.17), Vector2(radius * 0.86, radius * 0.1),
			Vector2(radius * 0.8, radius * 0.5)]), gold.darkened(0.2), 1.5, true)


## Story art "plain": looks like any pop bumper, with a health bar above it.
func _draw_plain() -> void:
	var base := Palette.BUMPER if Engine.is_editor_hint() else Cosmetics.bumper_color()
	var fill := base.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + _flash * 6.0, base.darkened(0.5))
	draw_circle(Vector2.ZERO, radius, fill)
	draw_circle(Vector2.ZERO, radius * 0.55, base.darkened(0.3))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 2.0, true)
	var w := radius * 2.4
	var bar := Rect2(-w * 0.5, -radius - 22.0, w, 9.0)
	var ratio := clampf(_shown_hp / float(max_hp), 0.0, 1.0)
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.85))
	draw_rect(bar, Color(0.18, 0.2, 0.3))
	var health := Color(0.4, 0.95, 0.5).lerp(Color(1.0, 0.3, 0.3), 1.0 - ratio).lerp(Color.WHITE, _hurt * 0.5)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), health)
	if fixed_damage > 0.0:
		# Counted in hits: one segment per hit, no number.
		var hits := roundi(max_hp / fixed_damage)
		for i in range(1, hits):
			var x := bar.position.x + bar.size.x * float(i) / hits
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.9), 2.0)
		return
	if show_hp_number and not Engine.is_editor_hint():
		var font := ThemeDB.fallback_font
		var text := GameManager.format_short(hp)
		var pos := Vector2(-w * 0.5, bar.position.y - 5.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color.WHITE)


## 100000 -> "100K", 69900 -> "69.9K"
func _short_number(n: float) -> String:
	if n >= 1000:
		var k := n / 1000.0
		return ("%dK" % int(k)) if is_equal_approx(k, roundf(k)) or k >= 100.0 else ("%.1fK" % k)
	return str(n)


## Boss Magnet power-up: pull playfield balls within MAGNET_RANGE toward the boss.
const MAGNET_RANGE := 210.0
const MAGNET_PULL := 3000.0 # px/s² per stack at point blank (gravity is 1100)
## More than this traps the ball in orbit around the boss.
const MAGNET_MAX_STACKS := 3

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or GameManager.boss_magnet <= 0 or hp <= 0:
		return
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null or not ball.in_play or ball.ramp != null:
			continue
		var to_boss := global_position - ball.global_position
		var dist := to_boss.length()
		if dist < MAGNET_RANGE and dist > radius:
			var falloff := 1.0 - dist / MAGNET_RANGE
			ball.add_impulse(to_boss / dist * MAGNET_PULL * mini(GameManager.boss_magnet, MAGNET_MAX_STACKS) * falloff * delta)
