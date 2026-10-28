class_name Ladder
extends Node2D
## A plain wooden ladder on the end of a temple floor (level_gen.gd _temples), drawn in code. The Bro grabs it with Jump
## (up) or Crouch (down) when he stands at its foot or top, and climbs it (player.gd). `top` and `bottom` are the y of
## the floor surfaces at its two ends; `step` is the way from its top onto the floor above (-1 left, 1 right).

const RAIL := Color("6b4a2b")
const RAIL_DARK := Color("3f2a18")
const RUNG := Color("8a6338")
const REACH := 20.0  # how far from the ladder he may stand and still grab it

static var all: Array[Ladder] = []

var top := 0.0
var bottom := 0.0
var step := 1


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## The ladder he can grab from `feet` (the point just under his feet): going up from its foot, or down from its top.
static func find(feet: Vector2, up: bool) -> Ladder:
	for l in all:
		if absf(l.position.x - feet.x) > REACH:
			continue
		if up and feet.y >= l.top + 2.0 and feet.y <= l.bottom + 3.0:
			return l
		if not up and feet.y >= l.top - 4.0 and feet.y <= l.bottom - 3.0:
			return l
	return null


## The ladder his body overlaps at `feet`, if any: he stays on it only as long as he is over it.
static func near(feet: Vector2) -> Ladder:
	for l in all:
		if absf(l.position.x - feet.x) <= 12.0 and feet.y >= l.top - 3.0 and feet.y <= l.bottom + 4.0:
			return l
	return null


func _ready() -> void:
	position.y = 0.0
	queue_redraw()


func _draw() -> void:
	var h := bottom - top
	draw_rect(Rect2(-7, top - 4, 3, h + 4), RAIL)  # the two rails
	draw_rect(Rect2(4, top - 4, 3, h + 4), RAIL)
	draw_rect(Rect2(-5, top - 4, 1, h + 4), RAIL_DARK)
	draw_rect(Rect2(6, top - 4, 1, h + 4), RAIL_DARK)
	var y := top + 2.0
	while y < bottom - 2.0:  # the rungs
		draw_rect(Rect2(-5, y, 10, 2), RUNG)
		y += 7.0
