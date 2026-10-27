class_name SteamPuff
extends Node2D
## A wisp of pale cyan steam that rises from a cooling raygun (MIB's reload, player.gd). Made in code:
## a few square puffs that drift up, swell and fade. A few cyan sparks fly off when `sparks` is set.

const COLOR := Color("cdf4f4")
const SPARK := Color("5ae6f0")
const LIFE := 0.8

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _size := PackedFloat32Array()
var _sparks := PackedVector2Array()
var _spark_vel := PackedVector2Array()
var _age := 0.0


static func emit(parent: Node, pos: Vector2, sparks := false) -> void:
	var puff := SteamPuff.new()
	puff.position = pos
	puff.z_index = 4
	for i in 2:
		puff._pos.append(Vector2(randf_range(-1.5, 1.5), 0.0))
		puff._vel.append(Vector2(randf_range(-6.0, 6.0), -randf_range(14.0, 28.0)))
		puff._size.append(randf_range(1.5, 2.5))
	if sparks:
		for i in 4:
			puff._sparks.append(Vector2.ZERO)
			puff._spark_vel.append(Vector2.from_angle(randf() * TAU) * randf_range(20.0, 45.0))
	parent.add_child(puff)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	for i in _pos.size():
		_pos[i] += _vel[i] * delta
		_vel[i].x += randf_range(-30.0, 30.0) * delta
	for i in _sparks.size():
		_sparks[i] += _spark_vel[i] * delta
		_spark_vel[i] *= 1.0 - 5.0 * delta
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFE
	for i in _pos.size():
		var s := _size[i] * (1.0 + t * 1.2)
		draw_rect(Rect2((_pos[i] - Vector2(s, s) / 2.0).round(), Vector2(s, s).round()), Color(COLOR, 0.55 * (1.0 - t)))
	if t < 0.5:
		for p in _sparks:
			draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(SPARK, 1.0 - t * 2.0))
