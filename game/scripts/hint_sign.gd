class_name HintSign
extends Node2D
## A small signpost beside a chasm: a round pixel board on a short post with an arrow pointing up (the way over is up),
## and a second one pointing down when there is a way in under the ground too. Drawn in code; `position` is the middle of
## the cell it stands in. It stands on the block below it: when that block is gone the sign breaks.

const BOARD := Color("ffd23e")
const RIM := Color("1f1b2c")
const POST := Color("5a4630")

var down := false  # also points down

var _check := 0.0


func _draw() -> void:
	var radius := 9 if down else 7
	var middle := Vector2(0, -9 - (2 if down else 0))
	draw_rect(Rect2(-1, -3, 3, 15), RIM)  # the post, from the ground up under the board
	draw_rect(Rect2(0, -3, 1, 15), POST)
	for dy in range(-radius - 1, radius + 2):  # the board: a pixel circle with a dark rim
		var half_rim := int(sqrt(float((radius + 1) * (radius + 1) - dy * dy)) + 0.5)
		draw_rect(Rect2(middle.x - half_rim, middle.y + dy, 2 * half_rim, 1), RIM)
	for dy in range(-radius, radius + 1):
		var half := int(sqrt(float(radius * radius - dy * dy)) + 0.5)
		draw_rect(Rect2(middle.x - half, middle.y + dy, 2 * half, 1), BOARD)
	if down:
		_arrow(Vector2(-4, middle.y), -1, 3)
		_arrow(Vector2(4, middle.y), 1, 3)
	else:
		_arrow(Vector2(0, middle.y), -1, 4)


## An arrow centred on x = at.x around the board's middle (at.y), pointing up (-1) or down (1): a shaft and a head, a row
## at a time.
func _arrow(at: Vector2, way: int, head: int) -> void:
	if way < 0:
		draw_rect(Rect2(at.x - 1, at.y - 1, 2, 7), RIM)
		for i in head:
			draw_rect(Rect2(at.x - i - 1, at.y - 5 + i, 2 * i + 2, 1), RIM)
	else:
		draw_rect(Rect2(at.x - 1, at.y - 6, 2, 7), RIM)
		for i in head:
			draw_rect(Rect2(at.x - i - 1, at.y + 4 - i, 2 * i + 2, 1), RIM)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	var below := Vector2i(floori(position.x / Block.SIZE), floori(position.y / Block.SIZE) + 1)
	if not Block.cells.has(below):  # what it stood on is gone
		DirtDebris.burst(get_parent(), position, POST, 6)
		DirtDebris.burst(get_parent(), position + Vector2(0, -9), BOARD, 6)
		Sfx.play(self, "block_break", -8.0)
		queue_free()
