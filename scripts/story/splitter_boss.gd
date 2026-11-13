class_name SplitterBoss
extends Node
## Story boss gimmick, "The Splitter".
## Hitting a bumper in the top third of the table splits the boss into two
## smaller bumpers, each holding half of his remaining HP. Hitting one half and
## then the other within COMBO_WINDOW seconds deals double damage. After
## SPLIT_TIME seconds (or when a half is emptied) they recombine, and the boss
## continues with what the two halves have left.

signal split_started
signal recombined
signal damaged(amount: float)
## The halves were emptied: the boss is beaten.
signal defeated(info: Dictionary)

const TOP_THIRD_Y := 1120.0 / 3.0
const SPLIT_TIME := 8.0
const COMBO_WINDOW := 1.5
## Fallback when no free spot is found: how far each half sits from his center.
const HALF_OFFSET := 62.0
## Size of a half next to the whole boss.
const HALF_RADIUS_RATIO := 0.72
## The halves land at random free spots in here: the top half of the table,
## inside the walls and left of the shooter lane.
const SPLIT_AREA := Rect2(70, 110, 420, 440)

var boss: BossBumper
var active: bool = false
var _halves: Array[SplitHalf] = []
var _time_left: float = 0.0
var _last_half: SplitHalf = null
var _last_hit_ms: int = -100000
## HP the boss had when he split (for the damage total).
var _hp_at_split: float = 0.0


func _ready() -> void:
	GameManager.part_hit.connect(_on_part_hit)


func is_split() -> bool:
	return not _halves.is_empty()


## HP left in the two halves together (while split).
func halves_hp() -> float:
	var total := 0.0
	for half in _halves:
		if is_instance_valid(half):
			total += maxf(half.hp, 0.0)
	return total


func _on_part_hit(part: Node) -> void:
	if not active or is_split() or not is_instance_valid(boss) or boss.hp <= 0.0:
		return
	if part is Bumper and not part is BossBumper and not part is SplitHalf \
			and (part as Node2D).global_position.y < TOP_THIRD_Y:
		_split.call_deferred() # after the physics step: the split looks for free spots


func _split() -> void:
	if is_split() or not is_instance_valid(boss) or boss.hp <= 0.0:
		return
	_hp_at_split = boss.hp
	_time_left = SPLIT_TIME
	_last_half = null
	var spots := _pick_spots(boss.radius * HALF_RADIUS_RATIO)
	boss.visible = false
	boss.process_mode = Node.PROCESS_MODE_DISABLED # also takes its body off the table
	for side: int in [-1, 1]:
		var half := SplitHalf.new()
		half.side = side
		half.radius = boss.radius * HALF_RADIUS_RATIO
		half.kick_strength = boss.kick_strength
		half.score_value = boss.score_value
		half.color = boss.color
		half.hit_pitch = 1.25 if side < 0 else 1.4
		half.max_hp = boss.hp * 0.5
		half.hp = half.max_hp
		half.struck.connect(_on_half_struck)
		boss.get_parent().add_child(half)
		half.global_position = spots[0 if side < 0 else 1]
		_halves.append(half)
	GameManager.popup("SPLIT!", boss.global_position + Vector2(0, -boss.radius - 30), Color(1.0, 0.85, 0.3), true)
	Sfx.play("guard_break")
	split_started.emit()


## Two random spots in SPLIT_AREA where a half of radius `r` fits: clear of
## walls, bumpers and other parts, not under a ramp, not on a light, away from
## the balls and from each other. The left half gets the leftmost spot.
func _pick_spots(r: float) -> Array[Vector2]:
	var space := boss.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = r + 16.0 # room for the ball to get around it
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1 # table parts
	var keep_clear: Array = [] # [point, distance]
	for node in get_tree().get_nodes_in_group("ball"):
		if node is Ball and node.in_play:
			keep_clear.append([(node as Ball).global_position, r + 80.0])
	var level := boss.get_parent().get_parent()
	if level:
		for node in level.find_children("*", "Area2D", true, false):
			if node is Rollover:
				keep_clear.append([(node as Node2D).global_position, r + 26.0])
	var spots: Array[Vector2] = []
	for attempt in 300:
		if spots.size() == 2:
			break
		var p := Vector2(randf_range(SPLIT_AREA.position.x, SPLIT_AREA.end.x),
				randf_range(SPLIT_AREA.position.y, SPLIT_AREA.end.y))
		if spots.size() == 1 and p.distance_to(spots[0]) < r * 2.0 + 70.0:
			continue
		var blocked := false
		for item: Array in keep_clear:
			if p.distance_to(item[0]) < float(item[1]):
				blocked = true
				break
		if blocked:
			continue
		for tunnel in get_tree().get_nodes_in_group("tunnels"):
			if tunnel.covers(p, r + 8.0):
				blocked = true
				break
		if blocked:
			continue
		query.transform = Transform2D(0.0, p)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		spots.append(p)
	if spots.size() < 2: # nowhere free (shouldn't happen): either side of where he stood
		spots.clear()
		spots.append(boss.global_position + Vector2(-HALF_OFFSET, 0))
		spots.append(boss.global_position + Vector2(HALF_OFFSET, 0))
		return spots
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return spots


func _on_half_struck(half: SplitHalf) -> void:
	if not is_split():
		return
	var damage := maxf(roundf(GameManager.score * GameManager.boss_damage_mult), 1.0)
	var now := Time.get_ticks_msec()
	var doubled := _last_half != null and _last_half != half and now - _last_hit_ms <= int(COMBO_WINDOW * 1000.0)
	if doubled:
		damage *= 2.0
	_last_half = half
	_last_hit_ms = now
	half.hp -= damage
	var text := "-%s HP" % GameManager.format_short(damage)
	GameManager.popup("DOUBLE!  " + text if doubled else text,
			half.global_position + Vector2(0, -half.radius - 16),
			Color(1.0, 0.85, 0.3) if doubled else Color(1.0, 0.35, 0.3), true)
	damaged.emit(damage)
	if half.hp <= 0.0:
		_recombine.call_deferred() # not while the physics callback is running


func _process(delta: float) -> void:
	if not is_split():
		return
	_time_left -= delta
	for half in _halves:
		if is_instance_valid(half):
			half.time_left = clampf(_time_left / SPLIT_TIME, 0.0, 1.0)
	if _time_left <= 0.0:
		_recombine()


func _recombine() -> void:
	if not is_split():
		return
	var left := 0.0
	for half in _halves:
		if is_instance_valid(half):
			left += maxf(half.hp, 0.0)
			half.queue_free()
	_halves.clear()
	_last_half = null
	if not is_instance_valid(boss):
		return
	boss.process_mode = Node.PROCESS_MODE_INHERIT
	boss.visible = true
	# If either half was emptied, the overkill doesn't carry: he keeps the other half's HP.
	boss.set_hp(boss.max_hp, left)
	if left <= 0.0:
		defeated.emit({"max_hp": boss.max_hp, "total_damage": boss.max_hp, "ratio": 1.0})
	else:
		recombined.emit()
