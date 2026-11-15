class_name CollectorBoss
extends Node
## Story boss gimmick, "The Collector" (chapter 2, on the Showroom).
##  - The showpiece: one of the Till's exits is his showcase (a ring of sparkles).
##    A ball that comes out of it is admired: its next hit on him deals
##    SHOWPIECE_MULT x damage. The showcase then moves to another exit.
##  - The private gallery: a ball that drops through the upper deck's hole deals
##    GALLERY_MULT x damage if it hits him within GALLERY_SECONDS.
##  - New arrangement: at 2/3 and 1/3 of his health the table rearranges itself:
##    its bumpers and display cases slide to new places.

signal rearranged
## A marked ball was let out (kind: "showpiece" or "gallery").
signal marked(kind: String)
## A marked ball hit him (kind as above).
signal bonus_hit(kind: String)

const SHOWPIECE_MULT := 3.0
const SHOWPIECE_SECONDS := 10.0
const GALLERY_MULT := 2.0
const GALLERY_SECONDS := 2.5
const REARRANGE_AT: Array[float] = [2.0 / 3.0, 1.0 / 3.0]
const SLIDE_SECONDS := 0.9
## Where the moving parts go, per arrangement after the first (the first is the
## table as built). Cases also get a new eject direction, toward the middle.
const ARRANGEMENTS := [
	{
		"Bumpers/BumperLeft": [Vector2(125, 330)],
		"Bumpers/BumperRight": [Vector2(435, 330)],
		"CaseLeft": [Vector2(185, 262), Vector2(430, -160)],
		"CaseRight": [Vector2(375, 262), Vector2(-430, -160)],
	},
	{
		"Bumpers/BumperLeft": [Vector2(140, 380)],
		"Bumpers/BumperRight": [Vector2(420, 380)],
		"CaseLeft": [Vector2(195, 250), Vector2(420, -180)],
		"CaseRight": [Vector2(365, 250), Vector2(-420, -180)],
	},
]

var boss: BossBumper
var level: Node2D
var game: Node
var active: bool = false

var _till: BallTrap
var _showcase: TrapExit
## Ball -> {kind, left (seconds)}
var _marks: Dictionary = {}
var _next_arrangement: int = 0
var _pending: bool = false
var _sliding: bool = false
var _marks_fx: Node2D


func _ready() -> void:
	boss.hit_multiplier = _multiplier
	_till = level.find_child("Till", true, false) as BallTrap
	if _till:
		_till.launched.connect(_on_till_launched)
		_pick_showcase()
	for drop in level.find_children("*", "DeckDrop", true, false):
		(drop as DeckDrop).dropped.connect(_on_deck_drop)
	_marks_fx = Node2D.new()
	_marks_fx.z_index = 30
	_marks_fx.draw.connect(_draw_marks)
	level.add_child(_marks_fx)


func _exit_tree() -> void:
	if is_instance_valid(boss):
		boss.hit_multiplier = Callable()
	if is_instance_valid(_marks_fx):
		_marks_fx.queue_free()
	if is_instance_valid(_showcase):
		_showcase.showcase = false


## The showcase moves to another of the Till's exits.
func _pick_showcase() -> void:
	var exits := _till.exits()
	if exits.is_empty():
		return
	if is_instance_valid(_showcase):
		_showcase.showcase = false
		if exits.size() > 1:
			exits.erase(_showcase)
	_showcase = exits[randi() % exits.size()]
	_showcase.showcase = true


func _on_till_launched(ball: Ball, exit: TrapExit) -> void:
	if not active or exit != _showcase:
		return
	_marks[ball] = {"kind": "showpiece", "left": SHOWPIECE_SECONDS}
	marked.emit("showpiece")
	_pick_showcase()


func _on_deck_drop(ball: Ball) -> void:
	if not active:
		return
	var mark: Dictionary = _marks.get(ball, {})
	if mark.get("kind", "") == "showpiece":
		return # the bigger bonus stays
	_marks[ball] = {"kind": "gallery", "left": GALLERY_SECONDS}
	marked.emit("gallery")


## BossBumper.hit_multiplier: the marked ball's bonus, used up by the hit.
func _multiplier(ball: Ball) -> float:
	if not active or not _marks.has(ball):
		return 1.0
	var kind: String = _marks[ball]["kind"]
	_marks.erase(ball)
	bonus_hit.emit(kind)
	var mult := SHOWPIECE_MULT if kind == "showpiece" else GALLERY_MULT
	GameManager.popup("x%d %s" % [int(mult), "SHOWPIECE" if kind == "showpiece" else "FROM THE GALLERY"],
			boss.global_position + Vector2(0, -boss.radius - 100.0), Color(1.0, 0.82, 0.3), true)
	return mult


func _process(delta: float) -> void:
	if not active or not is_instance_valid(boss):
		return
	for ball in _marks.keys():
		if not is_instance_valid(ball) or not ball.in_play:
			_marks.erase(ball)
			continue
		_marks[ball]["left"] = float(_marks[ball]["left"]) - delta
		if float(_marks[ball]["left"]) <= 0.0:
			_marks.erase(ball)
	_marks_fx.queue_redraw()
	if _next_arrangement < REARRANGE_AT.size() and boss.hp <= boss.max_hp * REARRANGE_AT[_next_arrangement] and boss.hp > 0.0:
		_pending = true
	if _pending and not _sliding and _parts_free():
		_pending = false
		_rearrange(_next_arrangement)
		_next_arrangement += 1


## No ball sits in a display case or the Till (a held ball would be left behind).
func _parts_free() -> bool:
	for path: String in ARRANGEMENTS[0]:
		var part := level.get_node_or_null(path)
		if part and "_held" in part and part._held != null:
			return false
	return _till == null or not _till.is_holding()


## The table stops, shakes, and the parts slide to their new places.
func _rearrange(index: int) -> void:
	_sliding = true
	var layout: Dictionary = ARRANGEMENTS[mini(index, ARRANGEMENTS.size() - 1)]
	GameManager.choosing = true # no pause menu mid-slide
	get_tree().paused = true
	Sfx.play("guard_break", -4.0, 0.7)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	for path: String in layout:
		var part := level.get_node_or_null(path) as Node2D
		if part == null:
			continue
		var to: Vector2 = layout[path][0]
		tween.tween_property(part, "position", to, SLIDE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		if layout[path].size() > 1 and "eject_velocity" in part:
			part.eject_velocity = layout[path][1]
	for i in 6:
		if game and game.has_method("_shake"):
			game._shake(Vector2.RIGHT if i % 2 == 0 else Vector2.LEFT)
		await get_tree().create_timer(SLIDE_SECONDS / 6.0, true, false, true).timeout
	if tween.is_running():
		await tween.finished
	_clear_balls(layout)
	get_tree().paused = false
	GameManager.choosing = false
	_sliding = false
	rearranged.emit()


## A ball that a part has slid onto is pushed out of its way.
func _clear_balls(layout: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null or not ball.in_play or ball.deck != null or ball.ramp != null:
			continue
		for path: String in layout:
			var part := level.get_node_or_null(path) as Node2D
			if part == null:
				continue
			var room: float = float(part.get("radius")) + ball.radius + 4.0
			var away := ball.global_position - part.global_position
			if away.length() < room:
				var dir := away.normalized() if away.length() > 0.5 else Vector2.DOWN
				ball.teleport(part.global_position + dir * room)


## A gold ring around a showpiece ball, a velvet one around a gallery drop.
func _draw_marks() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for ball in _marks:
		if not is_instance_valid(ball) or not ball.visible:
			continue
		var kind: String = _marks[ball]["kind"]
		var col := Color(1.0, 0.82, 0.3) if kind == "showpiece" else Color(1.0, 0.45, 0.6)
		var at: Vector2 = _marks_fx.to_local(ball.global_position)
		var r: float = ball.radius + 6.0 + 2.0 * sin(t * 10.0)
		_marks_fx.draw_arc(at, r, 0.0, TAU, 24, col, 2.5, true)
		_marks_fx.draw_string(ThemeDB.fallback_font, at + Vector2(-12, -r - 4.0), "x%d" % int(SHOWPIECE_MULT if kind == "showpiece" else GALLERY_MULT), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, col)
