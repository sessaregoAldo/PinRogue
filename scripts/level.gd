@tool
class_name Level
extends Node2D
## A table layout ("machine configuration").
##
## Every level inherits scenes/levels/level_base.tscn, which holds the parts all
## machines share: outer walls, launcher lane and gate, inlanes, slingshots,
## flippers, funnel and drain. A level adds its own upper playfield on top
## (bumpers, a BossBumper, tunnels, buttons, kickers...).
## The game loads levels through LevelRegistry (scripts/level_registry.gd).

@export var level_name: String = "Classic"
@export_multiline var description: String = ""
## Where a new ball appears (the launcher).
@export var spawn_point: Vector2 = Vector2(560, 1020)
## A ball that leaves this rectangle counts as drained.
@export var table_bounds: Rect2 = Rect2(-50, -50, 700, 1250)
@export var background_color: Color = Color(0.07, 0.08, 0.16):
	set(value):
		background_color = value
		queue_redraw()
## Decorative rings printed on the playfield: x, y = center, z = radius.
@export var art_rings: PackedVector3Array = PackedVector3Array():
	set(value):
		art_rings = value
		queue_redraw()
@export var art_title: String = "PINROGUE":
	set(value):
		art_title = value
		queue_redraw()
@export var art_title_position: Vector2 = Vector2(180, 860)
@export_group("Power-up guard positions")
@export var gap_guard: PackedVector2Array = PackedVector2Array([Vector2(262, 1030), Vector2(298, 1030)])
@export var left_outlane_guard: PackedVector2Array = PackedVector2Array([Vector2(26, 806), Vector2(55, 806)])
@export var right_outlane_guard: PackedVector2Array = PackedVector2Array([Vector2(505, 806), Vector2(534, 806)])


func _ready() -> void:
	queue_redraw.call_deferred() # tunnels are ready by then, for the arrows


## The level's boss bumper (or null).
func boss() -> BossBumper:
	return _find(self, func(n: Node) -> bool: return n is BossBumper) as BossBumper


func _find(node: Node, pred: Callable) -> Node:
	for child in node.get_children():
		if pred.call(child):
			return child
		var found := _find(child, pred)
		if found:
			return found
	return null


func _tunnels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Tunnel:
			out.append(child)
		_tunnels(child, out)


func _draw() -> void:
	draw_rect(Rect2(-100, -100, 800, 1400), background_color.darkened(0.5))
	draw_rect(Rect2(20, 20, 560, 1100), background_color)
	var accent := Color(0.35, 0.45, 0.9, 0.35)
	for ring in art_rings:
		draw_arc(Vector2(ring.x, ring.y), ring.z, 0.0, TAU, 64, accent, 3.0, true)
		draw_arc(Vector2(ring.x, ring.y), ring.z + 8.0, 0.0, TAU, 64, Color(accent, 0.15), 2.0, true)
	# Arrow inserts leading into each of this level's tunnel mouths.
	var tunnels := []
	_tunnels(self, tunnels)
	for tunnel: Tunnel in tunnels:
		if tunnel.path.size() >= 2:
			var mouth := to_local(tunnel.to_global(tunnel.path[0]))
			_draw_arrows(mouth, tunnel.path[1] - tunnel.path[0], Color(tunnel.color, 0.45))
	# Drain hole at the bottom of the funnel.
	draw_rect(Rect2(252, 1076, 56, 50), Color(0.01, 0.01, 0.02))
	draw_line(Vector2(252, 1077), Vector2(308, 1077), Color(1, 0.25, 0.2, 0.6), 2.0)
	# Outlane danger stripes.
	for x in [40.0, 520.0]:
		for i in 4:
			var y := 850.0 + i * 40.0
			draw_line(Vector2(x - 10, y), Vector2(x + 10, y + 10), Color(1, 0.25, 0.2, 0.35), 4.0, true)
	if art_title != "":
		draw_string(ThemeDB.fallback_font, art_title_position, art_title, HORIZONTAL_ALIGNMENT_CENTER, 200, 30, Color(1, 1, 1, 0.12))


func _draw_arrows(mouth: Vector2, dir: Vector2, c: Color) -> void:
	var d := dir.normalized()
	var side := d.orthogonal() * 9.0
	for k in 3:
		var tip := mouth - d * (34.0 + k * 22.0)
		var col := Color(c, c.a * (1.0 - k * 0.25))
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 + side, tip - d * 14.0 - side]), col)
