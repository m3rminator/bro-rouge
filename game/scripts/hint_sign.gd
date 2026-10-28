class_name HintSign
extends Node2D
## A small signpost beside a chasm the way over which is up: a round pixel board on a short post with an arrow
## pointing up, so he knows to climb. Drawn in code; `position` is the middle of the cell it stands in.

const BOARD := Color("ffd23e")
const RIM := Color("1f1b2c")
const POST := Color("5a4630")
const RADIUS := 7


func _draw() -> void:
	draw_rect(Rect2(-1, -3, 3, 15), RIM)  # the post, from the ground up under the board
	draw_rect(Rect2(0, -3, 1, 15), POST)
	var middle := Vector2(0, -9)
	for dy in range(-RADIUS - 1, RADIUS + 2):  # the board: a pixel circle with a dark rim
		var half_rim := int(sqrt(float((RADIUS + 1) * (RADIUS + 1) - dy * dy)) + 0.5)
		draw_rect(Rect2(middle.x - half_rim, middle.y + dy, 2 * half_rim, 1), RIM)
	for dy in range(-RADIUS, RADIUS + 1):
		var half := int(sqrt(float(RADIUS * RADIUS - dy * dy)) + 0.5)
		draw_rect(Rect2(middle.x - half, middle.y + dy, 2 * half, 1), BOARD)
	draw_rect(Rect2(-1, -10, 2, 7), RIM)  # the arrow up: a shaft and a head, a row at a time
	for i in 4:
		draw_rect(Rect2(-i - 1, -14 + i, 2 * i + 2, 1), RIM)
