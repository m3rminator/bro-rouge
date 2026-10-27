class_name ZipSparks
extends Node2D
## Sparks off the zipline handle: the metal rubbing on the cable above his head (player.gd, while he rides).
## A few tiny yellow-white specks fly back along the cable, drop a little and fade. Made in code.

const LIFE := 0.35
const HOT := Color("fff3b0")
const WARM := Color("ffb347")

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := 0.0


## `back` is the direction the sparks fly (opposite to the ride, 1 or -1).
static func emit(parent: Node, at: Vector2, back: int) -> void:
	var s := ZipSparks.new()
	s.position = at
	s.z_index = 5
	for i in randi_range(3, 5):
		s._pos.append(Vector2.ZERO)
		s._vel.append(Vector2(back * randf_range(25.0, 80.0), -randf_range(10.0, 55.0)))
	parent.add_child(s)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	for i in _pos.size():
		_pos[i] += _vel[i] * delta
		_vel[i].y += 240.0 * delta
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFE
	for p in _pos:
		draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(HOT if t < 0.4 else WARM, 1.0 - t))
