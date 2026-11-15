@tool
class_name SequenceLights
extends Node2D
## A row of light-up pads that must be rolled over in order. The next pad in
## line blinks; rolling over it lights it (and scores). Rolling over any other
## pad does nothing. Lighting the last one pays `bonus`, flashes the whole row
## and starts over. Taking too long between pads (`window` seconds, 0 = never)
## resets the row.

## Pad positions (local), in the order they must be lit.
@export var pads: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0, -40), Vector2(0, -80)]):
	set(value):
		pads = value
		queue_redraw()
@export var pad_radius: float = 11.0
@export var score_value: int = 100
@export var bonus: int = 5000
@export var window: float = 6.0
## Name shown in the pause menu's scoring legend.
@export var legend_name: String = "Sequence lights"
@export var color: Color = Color(0.45, 0.95, 1.0):
	set(value):
		color = value
		queue_redraw()
## Stills: how many pads to draw as lit.
@export var preview_lit: int = 0:
	set(value):
		preview_lit = value
		_next = value
		queue_redraw()

signal completed

var _next: int = 0
var _since: float = 0.0
var _flash: float = 0.0
var _areas: Array[Area2D] = []


func _ready() -> void:
	_next = preview_lit
	if Engine.is_editor_hint():
		return
	for i in pads.size():
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = Ball.LAYER_BALL
		area.monitorable = false
		area.position = pads[i]
		var circle := CircleShape2D.new()
		circle.radius = pad_radius
		var cs := CollisionShape2D.new()
		cs.shape = circle
		area.add_child(cs)
		add_child(area)
		area.body_entered.connect(_on_pad.bind(i))
		_areas.append(area)


func _on_pad(body: Node, index: int) -> void:
	var ball := body as Ball
	if ball == null or not ball.in_play or GameManager.tilted or index != _next:
		return
	_next += 1
	_since = 0.0
	GameManager.add_score(score_value, to_global(pads[index]))
	Sfx.play("click", -4.0, 1.0 + 0.15 * index)
	if _next >= pads.size():
		_next = 0
		_flash = 1.0
		GameManager.add_score(bonus, to_global(pads[pads.size() - 1]))
		GameManager.popup("SEQUENCE!", to_global(pads[pads.size() - 1]) + Vector2(-40, -20), color, true)
		Sfx.play("ramp_complete")
		completed.emit()
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _next > 0 and window > 0.0:
		_since += delta
		if _since > window:
			_next = 0
	_flash = maxf(0.0, _flash - delta * 2.0)
	queue_redraw() # the next pad blinks


func _draw() -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.5)
	for i in pads.size():
		var lit := i < _next or _flash > 0.0
		var p := pads[i]
		draw_circle(p, pad_radius + 2.0, color.darkened(0.7))
		var fill := color.darkened(0.55)
		if lit:
			fill = color.lerp(Color.WHITE, _flash * 0.6)
		elif i == _next:
			fill = color.darkened(0.55).lerp(color, 0.35 + 0.4 * blink)
		draw_circle(p, pad_radius, fill)
		# Arrow toward the next pad, so the order reads at a glance.
		if i + 1 < pads.size():
			var d := (pads[i + 1] - p).normalized()
			var tip := p + d * (pad_radius + 9.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - d * 6.0 + d.orthogonal() * 4.0, tip - d * 6.0 - d.orthogonal() * 4.0]), Color(color, 0.55))
