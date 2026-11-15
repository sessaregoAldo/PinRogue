@tool
class_name UpperDeck
extends Node2D
## A second floor above part of the table. Its parts (any walls, bumpers,
## kickers, lights... added as children) only touch a ball that is up on the
## deck, and a ball on the deck only touches them.
##
## - A ramp (Tunnel) with `to_deck` pointing here lands the ball on the deck.
## - DeckDrop children are the holes that drop it back to the playfield.
## - While no ball is up here only the deck's supports (and a faint shadow and
##   outline) show. When one arrives (or reaches the deck's edge on its ramp) the
##   deck's solid floor and parts appear, the table below dims and, with a single
##   ball in play, the view leans in toward the deck.
##
## `outline` is the deck's floor shape (local points, clockwise). Walls around
## the edge are not automatic: add them as children (they hold the ball in).

@export var outline: PackedVector2Array = PackedVector2Array([Vector2(90, 70), Vector2(470, 70), Vector2(470, 200), Vector2(90, 200)]):
	set(value):
		outline = value
		queue_redraw()
@export var floor_color: Color = Color(0.1, 0.09, 0.2):
	set(value):
		floor_color = value
		queue_redraw()
@export var trim_color: Color = Color(1.0, 0.8, 0.35):
	set(value):
		trim_color = value
		queue_redraw()
## How visible the deck is while no ball is on it (0..1). Its supports always show.
@export_range(0.0, 1.0) var idle_alpha: float = 0.05
## How high the deck stands: its supports' length and how far its shadow falls.
@export var height: float = 30.0
@export var support_color: Color = Color(0.55, 0.45, 0.4)
## Front face (the deck's thickness seen from the player's side).
@export var edge_color: Color = Color(0.45, 0.3, 0.12)
## Camera zoom while a ball is on the deck (1 = no zoom), and where it looks.
## A zero center means just below the deck's middle.
@export var zoom_view: float = 1.3
@export var zoom_center: Vector2 = Vector2.ZERO
## How much the table below darkens while a ball is on the deck.
@export_range(0.0, 1.0) var dim_below: float = 0.55
## Editor / stills: draw the deck as if a ball were on it.
@export var preview_active: bool = false:
	set(value):
		preview_active = value
		_shown = 1.0 if value else 0.0
		_apply_look()

const TABLE_SIZE := Vector2(600, 1120) # the whole view at zoom 1

## 0 = idle look, 1 = a ball is up here (eased).
var _shown: float = 0.0
## Supports, shadow and front face: drawn under the deck, and not faded with it.
var _under: Node2D
var _zoomed: bool = false


func _ready() -> void:
	if preview_active:
		_shown = 1.0
	_apply_look()
	if Engine.is_editor_hint():
		return
	_move_to_deck_layers.call_deferred(self)
	_under = Node2D.new()
	_under.name = name + "Supports"
	_under.z_index = z_index - 1
	_under.draw.connect(_draw_under)
	get_parent().add_child.call_deferred(_under)


## Every solid part becomes deck-only; every sensor watches deck balls only.
func _move_to_deck_layers(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject2D:
			var body := child as CollisionObject2D
			if body is Area2D:
				if body.collision_mask & Ball.LAYER_BALL:
					body.collision_mask = (body.collision_mask & ~Ball.LAYER_BALL) | Ball.LAYER_BALL_DECK
			elif body.collision_layer != 0:
				body.collision_layer = Ball.LAYER_DECK
		_move_to_deck_layers(child)


## A ball is on the deck, or on the last stretch of its ramp (under the deck's floor).
func has_ball() -> bool:
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball == null or not ball.in_play:
			continue
		if ball.deck == self:
			return true
		if ball.ramp != null and ball.ramp.get_node_or_null(ball.ramp.to_deck) == self 				and Geometry2D.is_point_in_polygon(to_local(ball.global_position), outline):
			return true
	return false


func _balls_in_play() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("ball"):
		var ball := node as Ball
		if ball and ball.in_play:
			count += 1
	return count


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or preview_active:
		return
	var up := has_ball()
	var target := 1.0 if up or _forced else 0.0
	if not is_equal_approx(_shown, target) and not (_force_tween and _force_tween.is_running()):
		_shown = move_toward(_shown, target, delta * 5.0)
		_apply_look()
	_update_zoom(up)


var _forced: bool = false
var _force_tween: Tween

## Show the deck as if a ball were on it (or let it go back to normal), also
## while the game is paused: story mode points it out, and upgrade placement
## shows it while one of its parts is highlighted.
func set_forced(on: bool) -> void:
	if on == _forced:
		return
	_forced = on
	if _force_tween:
		_force_tween.kill()
	var target := 1.0 if on or has_ball() else 0.0
	_force_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_force_tween.tween_method(func(v: float) -> void:
		_shown = v
		_apply_look(), _shown, target, 0.3).set_trans(Tween.TRANS_SINE)


## The ramps that lead up here.
func ramps() -> Array:
	var out := []
	var table := get_parent()
	for node in table.find_children("*", "Tunnel", true, false):
		var t := node as Tunnel
		if t and not t.to_deck.is_empty() and t.get_node_or_null(t.to_deck) == self:
			out.append(t)
	return out


## Lean the view in toward the deck while the only ball in play is up here.
## Story mode's slow-motion close-up has the camera then, so it is left alone.
func _update_zoom(up: bool) -> void:
	if zoom_view <= 1.0:
		return
	var game := get_tree().current_scene
	if game == null or not game.has_method("focus_camera"):
		return
	var calm := is_equal_approx(Engine.time_scale, 1.0) and not GameManager.is_game_over
	var want := up and calm and _balls_in_play() == 1
	if want and not _zoomed:
		_zoomed = true
		game.focus_camera(_zoom_point(), zoom_view, 0.5)
	elif _zoomed and not want:
		_zoomed = false
		if calm:
			game.reset_camera(0.5)


## Where the zoomed view centers, kept so the view never shows past the table's edges.
func _zoom_point() -> Vector2:
	var point := zoom_center
	if point == Vector2.ZERO:
		var box := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			box = box.expand(p)
		point = to_global(box.get_center() + Vector2(0, 180))
	var half := TABLE_SIZE * 0.5 / zoom_view
	return point.clamp(half, TABLE_SIZE - half)


func _apply_look() -> void:
	modulate.a = lerpf(idle_alpha, 1.0, _shown)
	queue_redraw()
	if _under:
		_under.queue_redraw()


## Under the deck: its shadow on the table, its front face (only while shown) and
## its supports, which stand at the corners of its lower edges.
func _draw_under() -> void:
	if outline.size() < 3:
		return
	var o := PackedVector2Array()
	for p in outline:
		o.append(_under.to_local(to_global(p)))
	var drop := Vector2(0, height)
	var shadow := PackedVector2Array()
	for p in o:
		shadow.append(p + drop)
	_under.draw_colored_polygon(shadow, Color(0, 0, 0, lerpf(0.06, 0.22, _shown)))
	var feet := []
	var face := Vector2(0, 14)
	for i in o.size():
		var a := o[i]
		var b := o[(i + 1) % o.size()]
		var nrm := (b - a).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 3.0, o):
			nrm = -nrm
		if nrm.y <= 0.15:
			continue # only edges facing the player
		if _shown > 0.01:
			_under.draw_colored_polygon(PackedVector2Array([a, b, b + face, a + face]), Color(edge_color, _shown))
		for q in [a, b]:
			if not feet.has(q):
				feet.append(q)
	for q in feet:
		_under.draw_line(q + drop, q, support_color, 6.0)
		_under.draw_circle(q + drop, 5.0, support_color.darkened(0.45))
		_under.draw_circle(q, 4.0, Color(trim_color, lerpf(0.7, 1.0, _shown)))


func _draw() -> void:
	if outline.size() < 3:
		return
	# The table below dims while the deck is in use (drawn first, under the floor).
	if _shown > 0.01 and dim_below > 0.0:
		draw_rect(Rect2(to_local(Vector2(-50, -50)), Vector2(700, 1250)), Color(0, 0, 0, dim_below * _shown / maxf(modulate.a, 0.01)))
	# Floor: invisible while idle (only the trim shows), solid while in use.
	var floor_fill := Color(floor_color, _shown)
	if floor_fill.a > 0.01:
		draw_colored_polygon(outline, floor_fill)
		# Floor planks, so it reads as a raised platform.
		var box := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			box = box.expand(p)
		var y := box.position.y + 18.0
		while y < box.end.y:
			draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(trim_color, 0.06 * _shown), 1.0)
			y += 18.0
	var ring := PackedVector2Array(outline)
	ring.append(outline[0])
	draw_polyline(ring, Color(trim_color, 0.55 + 0.45 * _shown), 2.0 + _shown * 1.5, true)
