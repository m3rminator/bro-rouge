class_name Shards
extends Node2D
## Scraps of a broken thing (the helmet): square specks in the given colors that spray out,
## fall, land on the ground or a block and lie there a few seconds, then fade.

const WORLD_MASK := 1
const REST := 4.0
const FADE := 1.5

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _color := PackedColorArray()
var _size := PackedInt32Array()
var _rest := PackedFloat32Array()  # -1 while flying, else seconds lying


## `amount` specks from `at` (in `parent`'s space), thrown up and out at up to `speed` px/s.
static func burst(parent: Node, at: Vector2, colors: Array, amount: int, speed: float) -> void:
	var shards := Shards.new()
	shards.position = at
	shards.z_index = 3
	for i in amount:
		var angle := randf_range(-PI * 0.95, -PI * 0.05)  # the upper half circle
		shards._pos.append(Vector2.ZERO)
		shards._vel.append(Vector2.from_angle(angle) * randf_range(speed * 0.3, speed))
		shards._color.append(colors[randi() % colors.size()])
		shards._size.append(randi_range(1, 3))
		shards._rest.append(-1.0)
	parent.add_child.call_deferred(shards)


func _physics_process(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var gone := 0
	for i in _pos.size():
		if _rest[i] >= 0.0:
			_rest[i] += delta
			gone += 1 if _rest[i] > REST + FADE else 0
			continue
		_vel[i].y += 520.0 * delta
		var next := _pos[i] + _vel[i] * delta
		var query := PhysicsRayQueryParameters2D.create(global_position + _pos[i], global_position + next, WORLD_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_pos[i] = next
		else:
			_pos[i] = hit.position - global_position + hit.normal * 0.5
			_rest[i] = 0.0
		if _pos[i].y > 4000.0:
			_rest[i] = REST + FADE
	if gone >= _pos.size():
		queue_free()
	queue_redraw()


func _draw() -> void:
	for i in _pos.size():
		var a := 1.0
		if _rest[i] > REST:
			a = clampf(1.0 - (_rest[i] - REST) / FADE, 0.0, 1.0)
		var s := _size[i]
		draw_rect(Rect2(_pos[i].round() - Vector2(s, s) / 2.0, Vector2(s, s)), Color(_color[i], a))
