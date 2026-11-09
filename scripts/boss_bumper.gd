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


func _after_hit(_ball: Ball) -> void:
	if hp <= 0:
		return
	var damage: float = GameManager.score if damage_mode == DamageMode.CURRENT_SCORE else float(score_value)
	damage = maxf(roundf(damage * GameManager.boss_damage_mult), 1.0)
	var total_damage := (max_hp - hp) + damage # includes the overkill of this hit
	hp = maxf(0.0, hp - damage)
	_hurt = 1.0
	GameManager.popup("-%s HP" % GameManager.format_short(damage),
			global_position + Vector2(0, -radius - 16), Color(1.0, 0.35, 0.3), true)
	if hp <= 0.0:
		GameManager.boss_defeated({ # GameManager adds "next_max_hp"
			"max_hp": max_hp,
			"total_damage": total_damage,
			"ratio": float(total_damage) / float(max_hp),
		})


func _process(delta: float) -> void:
	super(delta)
	if absf(_shown_hp - hp) > maxf(0.5, max_hp * 1e-6) or _hurt > 0.0:
		_shown_hp = lerpf(_shown_hp, hp, 1.0 - exp(-8.0 * delta))
		if absf(_shown_hp - hp) <= maxf(0.5, max_hp * 1e-6):
			_shown_hp = hp
		_hurt = maxf(0.0, _hurt - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	var fill := color.lerp(Color.WHITE, _flash * 0.7)
	draw_circle(Vector2.ZERO, radius + _flash * 6.0, color.darkened(0.5))
	draw_circle(Vector2.ZERO, radius, fill)

	# Health dial: dark disc = lost health, colored slice = remaining health.
	var r := radius * dial_ratio
	draw_circle(Vector2.ZERO, r, color.darkened(0.78))
	var ratio := clampf(_shown_hp / float(max_hp), 0.0, 1.0)
	var health_color := color.lightened(0.35).lerp(Color.WHITE, _hurt * 0.5)
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
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(color.lightened(0.6), 0.7), 1.5, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 2.0, true)

	if show_hp_number:
		var font := ThemeDB.fallback_font
		var text := GameManager.format_short(hp) if not Engine.is_editor_hint() else _short_number(hp)
		var pos := Vector2(-r, 5)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, Color.WHITE)


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
