class_name SplitHalf
extends Bumper
## One half of the Splitter boss while he is split in two (see SplitterBoss).
## A bumper with its own HP, drawn as half of the cracked disc.

signal struck(half: SplitHalf)

## -1 = the left half, 1 = the right half.
var side: int = -1
var hp: float = 1.0
var max_hp: float = 1.0
## 0..1: how much of the split time is left (the rim drains with it).
var time_left: float = 1.0
var _hurt: float = 0.0


func _ready() -> void:
	legend_name = "Splitter half"
	set_meta("no_multiplier", true) # gone again in a few seconds
	super()


func _after_hit(_ball: Ball) -> void:
	_hurt = 1.0
	struck.emit(self)


func _process(delta: float) -> void:
	super(delta)
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	queue_redraw() # the timer rim keeps moving


func _draw() -> void:
	var body := color if side < 0 else color.darkened(0.3)
	body = body.lerp(Color.WHITE, maxf(_flash * 0.7, _hurt * 0.4))
	# Half disc: the jagged crack on the inner side, the round rim on the outer.
	var pts := PackedVector2Array()
	for p in BossBumper.crack_points(radius):
		pts.append(Vector2(p.x - side * radius * 0.25, p.y))
	var rim := PackedVector2Array()
	for i in range(1, 16):
		# From the bottom, around the outer side, to the top.
		var angle := PI * 0.5 - side * PI * float(i) / 16.0
		rim.append(Vector2(cos(angle) * radius - side * radius * 0.25, sin(angle) * radius))
	pts.append_array(rim)
	draw_colored_polygon(pts, body.darkened(0.45))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.86)
	draw_colored_polygon(inner, body)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color.WHITE, 2.0, true)
	# Split timer: an arc on the outer side that shrinks as time runs out.
	if time_left > 0.0:
		var span := PI * 0.9 * time_left
		var mid := PI if side < 0 else 0.0
		draw_arc(Vector2(-side * radius * 0.25, 0), radius + 5.0, mid - span * 0.5, mid + span * 0.5, 24,
				Color(1.0, 0.85, 0.3, 0.9), 2.5, true)
	var font := ThemeDB.fallback_font
	var text := GameManager.format_short(maxf(hp, 0.0))
	var pos := Vector2(-radius + side * radius * 0.12, 5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, Color.WHITE)
