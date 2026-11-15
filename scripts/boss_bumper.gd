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
## "collector" = the dial in a gold, coin-milled rim with a jeweller's loupe.
var art: String = "":
	set(value):
		art = value
		queue_redraw()

var hp: float = 0.0
var _shown_hp: float = 0.0 # animated value the dial draws
var _hurt: float = 0.0 # white flash on the dial when damaged


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		max_hp = GameManager.boss_max_hp
		color = GameManager.boss_color
	hp = max_hp
	_shown_hp = hp


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
		damage = maxf(roundf(damage * GameManager.boss_damage_mult * bonus), 1.0)
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
			depleted.emit(info)
		else:
			GameManager.boss_defeated(info)


## Give the boss a new health pool (story mode: the reveal, the Splitter).
func set_hp(new_max: float, current: float = -1.0) -> void:
	max_hp = maxf(new_max, 1.0)
	hp = max_hp if current < 0.0 else clampf(current, 0.0, max_hp)
	_shown_hp = hp
	queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if absf(_shown_hp - hp) > maxf(0.5, max_hp * 1e-6) or _hurt > 0.0:
		_shown_hp = lerpf(_shown_hp, hp, 1.0 - exp(-8.0 * delta))
		if absf(_shown_hp - hp) <= maxf(0.5, max_hp * 1e-6):
			_shown_hp = hp
		_hurt = maxf(0.0, _hurt - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	if art == "plain":
		_draw_plain()
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
