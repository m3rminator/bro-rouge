class_name SweatDrops
extends Node2D
## Sweat drops (the kneeling Brute): they fall, land ON the ground (a block's top) as little wet specks,
## stay there a few seconds and fade away. Each drop is one entry in the arrays below.

const WORLD_MASK := 1
const GRAVITY := 260.0
const COLOR := Color("bfe6f2")

var _pos := PackedVector2Array()  # global positions
var _vel := PackedVector2Array()
var _landed := PackedFloat32Array()  # -1 while falling; else seconds it has lain there
var _rest := PackedFloat32Array()  # how long this one lies before it is gone
var _size := PackedInt32Array()


## `amount` drops from `pos` (global), thrown a little sideways and down.
static func emit(parent: Node, pos: Vector2, amount := 1) -> void:
	var drops := SweatDrops.new()
	drops.z_index = 3
	for i in amount:
		drops._pos.append(pos + Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0)))
		drops._vel.append(Vector2(randf_range(-22.0, 22.0), randf_range(-8.0, 22.0)))
		drops._landed.append(-1.0)
		drops._rest.append(randf_range(2.5, 4.5))
		drops._size.append(randi_range(1, 2))
	parent.add_child(drops)


func _physics_process(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var alive := false
	for i in _pos.size():
		if _landed[i] >= 0.0:
			_landed[i] += delta
			alive = alive or _landed[i] < _rest[i]
			continue
		alive = true
		_vel[i].y += GRAVITY * delta
		var next := _pos[i] + _vel[i] * delta
		var query := PhysicsRayQueryParameters2D.create(_pos[i], next, WORLD_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_pos[i] = next
			if _pos[i].y > 4000.0:
				_landed[i] = 999.0
		else:
			_pos[i] = hit.position + Vector2(0, -1)  # on the surface, not in it
			_landed[i] = 0.0
	queue_redraw()
	if not alive:
		queue_free()


func _draw() -> void:
	for i in _pos.size():
		var p := to_local(_pos[i])
		if _landed[i] < 0.0:
			draw_rect(Rect2(p, Vector2(1, 2)), COLOR)
			continue
		var fade := clampf(1.0 - (_landed[i] - (_rest[i] - 1.0)), 0.0, 1.0)  # fades over the last second
		if fade <= 0.0:
			continue
		var c := Color(COLOR.r, COLOR.g, COLOR.b, 0.85 * fade)
		draw_rect(Rect2(p + Vector2(-1 - _size[i] / 2, -1), Vector2(2 + _size[i], 1)), c)  # a flat wet speck
