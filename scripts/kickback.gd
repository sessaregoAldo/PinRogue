class_name Kickback
extends Area2D
## Kickback (minor spare part): a kicker at the bottom of an outlane that fires
## a draining ball straight back up the lane. Fires once, then recharges after
## BOSS_HITS boss hits or BUMPER_HITS bumper hits (whichever comes first).
## The first pick puts one in the left outlane, the second in the right.

signal changed

const BOSS_HITS := 10
const BUMPER_HITS := 20
const KICK_SPEED := 1400.0
## Tilted this many degrees toward the middle of the table.
const KICK_ANGLE_DEG := 4.0
const LANE_WIDTH := 34.0
const ZONE_HEIGHT := 56.0
const READY_COLOR := Color(0.45, 1.0, 0.6)
const EMPTY_COLOR := Color(0.45, 0.5, 0.6)

## "L" or "R" (which outlane).
var side: String = "L"
var charged: bool = true
var boss_hits: int = 0
var bumper_hits: int = 0
var _flash: float = 0.0
var _pulse: float = 0.0
var _last_kick_ms: int = -100000


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	z_index = 2
	var rect := RectangleShape2D.new()
	rect.size = Vector2(LANE_WIDTH, ZONE_HEIGHT)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)
	GameManager.part_hit.connect(_on_part_hit)


## 0..1 toward the next charge (the closer of the two counts).
func progress() -> float:
	if charged:
		return 1.0
	return maxf(float(boss_hits) / BOSS_HITS, float(bumper_hits) / BUMPER_HITS)


## "ready", or "boss 3/10 · bumpers 12/20".
func status_text() -> String:
	if charged:
		return "ready"
	return "boss %d/%d · bumpers %d/%d" % [boss_hits, BOSS_HITS, bumper_hits, BUMPER_HITS]


func _on_part_hit(part: Node) -> void:
	if charged:
		return
	if part is BossBumper:
		boss_hits += 1
	elif part is Bumper:
		bumper_hits += 1
	else:
		return
	if boss_hits >= BOSS_HITS or bumper_hits >= BUMPER_HITS:
		charged = true
		boss_hits = 0
		bumper_hits = 0
		_flash = 1.0
		GameManager.popup("KICKBACK READY", _popup_pos(), READY_COLOR, false)
		Sfx.play("guard_hit", 0.0, 1.3)
	changed.emit()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or not charged or GameManager.tilted:
		return
	if ball.linear_velocity.y < -200.0: # already on its way up
		return
	var now := Time.get_ticks_msec()
	if now - _last_kick_ms < 300:
		return
	_last_kick_ms = now
	charged = false
	_flash = 1.0
	var a := deg_to_rad(KICK_ANGLE_DEG) * (1.0 if side == "L" else -1.0)
	ball.set_velocity_safe(Vector2(sin(a), -cos(a)) * KICK_SPEED)
	GameManager.popup("KICKBACK!", _popup_pos(), READY_COLOR, true)
	Sfx.play("launch")
	changed.emit()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
	if charged or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var half := LANE_WIDTH * 0.5
	var base_y := ZONE_HEIGHT * 0.5 + 8.0
	# Kicker plate at the bottom of the zone.
	var plate := READY_COLOR if charged else EMPTY_COLOR
	plate = plate.lerp(Color.WHITE, _flash * 0.6)
	draw_rect(Rect2(-half + 3.0, base_y - 6.0, LANE_WIDTH - 6.0, 6.0), plate)
	# Arrow lamp: pulses while ready, dim while recharging.
	var a := 0.55 + 0.45 * sin(_pulse * TAU * 1.3) if charged else 0.25
	var lamp := Color(plate, a)
	var tip := Vector2(0, -12)
	draw_colored_polygon(PackedVector2Array([tip, Vector2(-9, 2), Vector2(9, 2)]), lamp)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 12), Vector2(-9, 14), Vector2(9, 14)]), Color(lamp, a * 0.6))
	# Recharge bar beside the lamp.
	if not charged:
		var h := (ZONE_HEIGHT - 10.0) * progress()
		draw_rect(Rect2(half - 5.0, base_y - 10.0 - h, 3.0, h), Color(READY_COLOR, 0.8))


## Popups sit a little toward the middle so the text isn't cut off at the edge.
func _popup_pos() -> Vector2:
	return global_position + Vector2(110.0 if side == "L" else -110.0, -70.0)
