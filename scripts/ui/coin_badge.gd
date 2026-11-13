class_name CoinBadge
extends Control
## The player's story coins: a big coin and a big number, for a corner of the
## Story menu pages. Follows the Story autoload by itself.

const SIZE := Vector2(190, 64)
const GOLD := Color(1.0, 0.82, 0.25)

var _shown: int = -1
var _bump: float = 0.0


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if Story.coins != _shown:
		if _shown >= 0:
			_bump = 1.0 # a little pop when the amount changes
		_shown = Story.coins
		queue_redraw()
	if _bump > 0.0:
		_bump = maxf(0.0, _bump - delta * 4.0)
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var text := str(maxi(_shown, 0))
	var font_size := 40
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var r := 24.0 + _bump * 3.0
	# Right-aligned: number at the right edge, coin to its left.
	var text_x := SIZE.x - 8.0 - text_w
	var center := Vector2(text_x - r - 10.0, SIZE.y * 0.5)
	draw_coin(self, center, r)
	draw_string_outline(font, Vector2(text_x, SIZE.y * 0.5 + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color.BLACK)
	draw_string(font, Vector2(text_x, SIZE.y * 0.5 + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD)


## A strange coin: gold, with a square hole that isn't always there.
static func draw_coin(canvas: CanvasItem, center: Vector2, r: float) -> void:
	canvas.draw_circle(center + Vector2(1.5, 2.5), r, Color(0, 0, 0, 0.5))
	canvas.draw_circle(center, r, GOLD.darkened(0.45))
	canvas.draw_circle(center, r * 0.88, GOLD)
	canvas.draw_arc(center, r * 0.68, 0.0, TAU, 32, GOLD.darkened(0.3), maxf(r * 0.08, 1.0), true)
	var hole := r * 0.26
	canvas.draw_rect(Rect2(center - Vector2(hole, hole), Vector2(hole, hole) * 2.0), GOLD.darkened(0.6))
	canvas.draw_arc(center, r * 0.88, PI * 1.1, PI * 1.6, 12, Color(1, 1, 1, 0.7), maxf(r * 0.1, 1.0), true)
