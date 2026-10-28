class_name Zipline
extends Node2D
## A cable between the tops of two towers over a chasm. Stand at either end and press Interact (E, or the touch
## hand button): the Bro hangs on the handle and rides to the other end (Player.start_zip does the moving).
## Jumping into the cable itself catches it too: he hangs on where he touched it and rides toward the far end.

const REACH := Vector2(22, 30)
const SAG := 6.0  # how far the middle of the cable hangs
const END_SKIP := 30.0  # within this of a post the cable does not catch him by itself
const DIP := 9.0  # how much further it bends where the Bro hangs on a cable of ordinary length (his hands follow it, player.gd)
const COLOR := Color("1f1b2c")
const CABLE := Color("c9c7d6")
const WIRE_OUTER := Color("0c0914")  # the cable in three layers: black outside, a lighter dark in the middle, a thin glint
const WIRE_MID := Color("3b374d")
const WIRE_GLINT := Color("8d89a3")

## The bend under his weight: a long cable (a slope down from a roof) gives more, or it would hardly show.
static func dip_for(from: Vector2, to: Vector2) -> float:
	return DIP * clampf(from.distance_to(to) / 340.0, 1.0, 3.5)


var a := Vector2.ZERO  # both ends: the centre of the cell the Bro stands on
var b := Vector2.ZERO
var in_reach := false  # the touch fire button turns into a hand
var _label := PixelText.make(Vector2.ZERO, PixelText.Align.CENTER)


func _ready() -> void:
	add_to_group("hub_stations")
	z_index = 1
	_label.color = Color("f4f2e8")
	add_child(_label)


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and (p.riding or p.zip_load > 0.0):
		queue_redraw()  # the cable bends under him
	in_reach = false
	_label.text = ""
	if p == null or p.dead or p.riding:
		return
	for end in [a, b]:
		if absf(p.global_position.x - end.x) < REACH.x and absf(p.global_position.y - end.y) < REACH.y:
			in_reach = true
			_label.text = "E RIDE"
			_label.position = end + Vector2(0, Block.SIZE / 2.0 - 46.0)
			if Input.is_action_just_pressed("interact"):
				p.start_zip(a, b, 1 if end == a else -1)
			return
	if p.is_on_floor() or p.zip_cooldown > 0.0:
		return
	var span := b.x - a.x
	var t: float = (p.global_position.x - a.x) / span
	if t < 0.0 or t > 1.0:
		return
	if absf(p.global_position.x - a.x) < END_SKIP or absf(p.global_position.x - b.x) < END_SKIP:
		return  # beside a post he must press Interact: the cable does not snatch him
	var cable_y := lerpf(a.y, b.y, t) + Block.SIZE / 2.0 - 30.0 + sin(t * PI) * SAG  # the cable, at his x (it may slope)
	var head: float = p.global_position.y + Block.SIZE / 2.0 - 30.0  # top of his body
	if head >= cable_y - 6.0 and head <= cable_y + 8.0:  # his hands reach the cable
		var way := 1 if t < 0.5 else -1
		if absf(a.y - b.y) > Block.SIZE:  # a sloped cable carries him downhill
			way = 1 if b.y > a.y else -1
		p.start_zip(a, b, way)


func _draw() -> void:
	for end in [a, b]:
		var base: Vector2 = end + Vector2(0, Block.SIZE / 2.0)
		draw_rect(Rect2(base.x - 2, base.y - 30, 4, 30), COLOR)
		draw_rect(Rect2(base.x - 4, base.y - 32, 8, 4), CABLE)
	var from := a + Vector2(0, Block.SIZE / 2.0 - 30)
	var to := b + Vector2(0, Block.SIZE / 2.0 - 30)
	var load_t := 0.0  # where his weight hangs (0..1 along the cable) and how much of it the cable carries now
	var load := 0.0
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.zip_load > 0.0:
		load = p.zip_load
		load_t = clampf((p.global_position.x - a.x) / (b.x - a.x), 0.02, 0.98)
	var points := PackedVector2Array()
	for i in range(0, 25):
		var t := i / 24.0
		var bend := (t / load_t if t < load_t else (1.0 - t) / (1.0 - load_t)) * load * dip_for(a, b)  # two slopes meeting at the Bro
		points.append(from.lerp(to, t) + Vector2(0, sin(t * PI) * SAG + bend))
	draw_polyline(points, WIRE_OUTER, 3.0)
	draw_polyline(points, WIRE_MID, 2.0)
	draw_polyline(points, WIRE_GLINT, 1.0)
