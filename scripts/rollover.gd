@tool
class_name Rollover
extends Area2D
## A lane switch the ball rolls over. It scores and lights up. When every
## rollover in the same group is lit, they all pay `group_bonus`, flash and reset.

@export var group_name: StringName = &"top_lanes"
@export var size: Vector2 = Vector2(16, 16)
@export var score_value: int = 50
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Rollover"
## Paid once when the whole group is lit (only the rollover that completes it pays).
@export var group_bonus: int = 2000
@export var color: Color = Color(1.0, 0.85, 0.2)
## Completing this rollover's group offers a power-up pick.
@export var grants_powerup: bool = true
## Which kind of pick: "minor" (the inlane lights behind the bottom slingshots)
## or "major" (the machine's own lights near the boss).
@export_enum("major", "minor") var powerup_tier: String = "major"
## Every `sets_per_step` completed sets raise the group's bonus by this much
## (0 = the bonus never changes). Small dots under each rollover count the sets
## toward the next raise.
@export var bonus_step: int = 0
@export_range(1, 9) var sets_per_step: int = 2

## Bumpers that can sit on top of this light (the Clock Tower's hour hand).
## While one covers it, the light counts as on, so its group needs one light
## less; once uncovered it counts as off again (unless the ball lit it).
@export var blockers: Array[NodePath] = []

## Sets completed so far, per group (shared by its rollovers; reset with the table).
static var _sets: Dictionary = {}

var lit: bool = false
## A blocker is over it (see `blockers`).
var covered: bool = false
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # playfield ball only: a ball riding a tunnel passes over
	monitorable = false
	add_to_group(group_name)
	var rect := RectangleShape2D.new()
	rect.size = size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)
	if not Engine.is_editor_hint():
		_sets.erase(group_name) # a fresh table starts the count again
		GameManager.game_started.connect(func() -> void:
			lit = false
			_sets.erase(group_name)
			queue_redraw())


func _process(delta: float) -> void:
	if not blockers.is_empty() and not Engine.is_editor_hint():
		var now := _is_covered()
		if now != covered:
			covered = now
			queue_redraw()
			if covered and not GameManager.tilted:
				_check_group() # the last light it needed has just been covered
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 0.8)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted:
		return
	GameManager.add_score(score_value, global_position)
	Sfx.play("rollover")
	if lit:
		return
	lit = true
	queue_redraw()
	_check_group()


## Lit or covered: what counts toward the group.
func counts_on() -> bool:
	return lit or covered


func _is_covered() -> bool:
	for path in blockers:
		var b := get_node_or_null(path) as Node2D
		if b == null:
			continue
		var reach: float = (b.get("radius") if b.get("radius") != null else 20.0) + minf(size.x, size.y) * 0.5
		if b.global_position.distance_to(global_position) < reach:
			return true
	return false


## Every light in the group on (lit or covered): pay the bonus, offer the
## part, and start the set again.
func _check_group() -> void:
	var any_lit := false
	for node in get_tree().get_nodes_in_group(group_name):
		var other := node as Rollover
		if other and not other.counts_on():
			return
		if other and other.lit:
			any_lit = true
	if not any_lit:
		return # covered lights alone never complete a set
	var done: int = _sets.get(group_name, 0)
	GameManager.add_score(group_bonus + bonus_step * (done / sets_per_step), global_position + Vector2(0, -26))
	_sets[group_name] = done + 1
	Sfx.play("ramp_complete")
	if grants_powerup:
		GameManager.request_powerup_choice(powerup_tier)
	for node in get_tree().get_nodes_in_group(group_name):
		var other := node as Rollover
		if other:
			other.lit = false
			other._flash = 1.0


func _draw() -> void:
	var on := counts_on() or (_flash > 0.0 and fmod(_flash * 8.0, 1.0) > 0.5)
	var r := minf(size.x, size.y) * 0.5
	if on:
		draw_circle(Vector2.ZERO, r + 4.0, Color(color, 0.25))
	draw_circle(Vector2.ZERO, r, color if on else color.darkened(0.75))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, color.darkened(0.3), 1.5, true)
	if bonus_step > 0 and sets_per_step > 1:
		var done: int = _sets.get(group_name, 0) % sets_per_step
		for i in sets_per_step:
			var x := (i - (sets_per_step - 1) * 0.5) * 7.0
			draw_circle(Vector2(x, r + 7.0), 2.2, color if i < done else color.darkened(0.7))
