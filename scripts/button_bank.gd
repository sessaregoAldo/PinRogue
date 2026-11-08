@tool
class_name ButtonBank
extends Node2D
## Rules for the TargetButton children (all of them, wherever they sit):
## - Every hit toggles that button on/off and scores `hit_points`.
## - Combination: light exactly the buttons marked with a filled diamond to get
##   a bonus of `match_bonus_ratio` x current score. All buttons then switch off
##   and a new combination is drawn.
## - Chase: one button is gold. Hitting it makes it normal and moves the gold to
##   another button that hasn't been gold yet this cycle. Once every button has
##   been cleared, the score is multiplied by `chase_multiplier`.
## Progress carries over between boss rounds and resets on a new run.

@export var hit_points: int = 25
## How many buttons the combination asks for.
@export var goal_count: int = 3
@export var match_bonus_ratio: float = 0.10
@export var chase_multiplier: float = 1.25
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Button"

var _buttons: Array[TargetButton] = []
var _cleared: Dictionary = {} # buttons whose gold was cleared this chase cycle


func _ready() -> void:
	for child in get_children():
		if child is TargetButton:
			_buttons.append(child)
	if Engine.is_editor_hint():
		return
	for b in _buttons:
		b.hit.connect(_on_button_hit)
	GameManager.game_started.connect(_reset)
	_reset()


func button_count() -> int:
	return _buttons.size()


## Buttons still to clear before the x1.25 multiplier.
func chase_remaining() -> int:
	return _buttons.size() - _cleared.size()


func _reset() -> void:
	for b in _buttons:
		b.lit = false
		b.special = false
		b.goal = false
	_cleared.clear()
	_new_goal()
	_move_gold(null)


func _new_goal() -> void:
	var previous: Array[TargetButton] = []
	for b in _buttons:
		if b.goal:
			previous.append(b)
	var count := clampi(goal_count, 1, _buttons.size())
	for attempt in 10: # avoid repeating the previous combination
		var shuffled := _buttons.duplicate()
		shuffled.shuffle()
		var picked := shuffled.slice(0, count)
		var same := picked.size() == previous.size()
		for b in picked:
			if not previous.has(b):
				same = false
		if not same or attempt == 9:
			for b in _buttons:
				b.goal = picked.has(b)
			return


func _move_gold(just_hit: TargetButton) -> void:
	var candidates: Array[TargetButton] = []
	for b in _buttons:
		if b != just_hit and not _cleared.has(b):
			candidates.append(b)
	if candidates.is_empty():
		return
	candidates[randi() % candidates.size()].special = true


func _on_button_hit(b: TargetButton) -> void:
	GameManager.add_score(hit_points, b.center_global())
	Sfx.play("button", 0.0, 1.15 if not b.lit else 0.9)
	b.lit = not b.lit

	if b.special:
		b.special = false
		_cleared[b] = true
		if _cleared.size() >= _buttons.size():
			GameManager.multiply_score(chase_multiplier, b.center_global())
			Sfx.play("multiplier")
			_cleared.clear()
		_move_gold(b)

	if _matches_goal():
		var bonus := int(round(GameManager.score * match_bonus_ratio))
		var where := _bank_center()
		GameManager.add_score(bonus, where + Vector2(0, -18))
		GameManager.popup("COMBO BONUS", where + Vector2(0, 8), Palette.BUTTON_LIT, true)
		Sfx.play("ramp_complete")
		for x in _buttons:
			x.lit = false
			x.flash()
		_new_goal()


func _matches_goal() -> bool:
	for b in _buttons:
		if b.lit != b.goal:
			return false
	return true


func _bank_center() -> Vector2:
	var sum := Vector2.ZERO
	for b in _buttons:
		sum += b.center_global()
	return sum / maxf(1.0, _buttons.size())
