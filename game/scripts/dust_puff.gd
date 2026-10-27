class_name DustPuff
extends Node2D
## A little cloud of dust kicked up at the Bro's feet when he runs, lands or kicks off a wall.
## Made in code: a few square specks that drift away from the movement, rise a little, grow and fade.

const COLOR := Color("b9a98c")
const LIFE := 0.45

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _size := PackedFloat32Array()
var _age := 0.0
var _life := LIFE


## `dir` = which way the specks drift (opposite to where he runs); `amount` specks; `speed` px/s.
static func emit(parent: Node, pos: Vector2, dir: int, amount := 3, speed := 22.0) -> void:
	var puff := DustPuff.new()
	puff.position = pos
	puff.z_index = 1
	for i in amount:
		puff._pos.append(Vector2(randf_range(-2, 2), randf_range(-1, 0)))
		puff._vel.append(Vector2(dir * randf_range(0.3, 1.0) * speed + randf_range(-6, 6), randf_range(-14, -4)))
		puff._size.append(randf_range(1.5, 2.5))
	parent.add_child(puff)


## A big burst along the ground: `amount` specks fly out to both sides (fast at the edges), rise a little,
## and hang longer than a running puff. `lift` pushes them upward (a jump kick-off), `size` scales the specks.
static func burst(parent: Node, pos: Vector2, amount: int, speed: float, size := 1.6, lift := 1.0, life := 0.7) -> void:
	var puff := DustPuff.new()
	puff.position = pos
	puff.z_index = 1
	puff._life = life
	for i in amount:
		var side := -1.0 if i % 2 == 0 else 1.0
		puff._pos.append(Vector2(randf_range(-6, 6), randf_range(-2, 0)))
		puff._vel.append(Vector2(side * randf_range(0.15, 1.0) * speed, -randf_range(8.0, 44.0) * lift))
		puff._size.append(randf_range(1.8, 3.2) * size)
	parent.add_child(puff)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	for i in _pos.size():
		_pos[i] += _vel[i] * delta
		_vel[i] *= 1.0 - 3.0 * delta
	queue_redraw()


func _draw() -> void:
	var t := _age / _life
	for i in _pos.size():
		var s := roundf(_size[i] * (1.0 + t))
		draw_rect(Rect2((_pos[i] - Vector2(s, s) / 2.0).round(), Vector2(s, s)), Color(COLOR, 0.8 * (1.0 - t)))
