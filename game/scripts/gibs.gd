class_name Gibs
extends Node2D
## Chunks of flesh thrown out when a body bursts (design/entities/blood.yaml, GameData.BLOOD).
## They fly and fall like blood drops; one that lands on top of a block stays there for the
## rest of the level as a red lump (BlockChunks). Chunks that hit anything else just vanish.

const LIFETIME := 2.5
const WORLD_MASK := 1

var _pos: PackedVector2Array
var _vel: PackedVector2Array
var _w: PackedInt32Array
var _h: PackedInt32Array
var _bump: PackedInt32Array  # 0 plain, 1 bump on the left of the top, 2 on the right, 3 jutting out the side
var _color: PackedColorArray
var _age := 0.0


## `amount` chunks from `pos` (in `parent`'s space), thrown upward-ish in every direction at up to `speed` px/s.
static func emit(parent: Node, pos: Vector2, amount: int, speed: float) -> void:
	var gibs := Gibs.new()
	gibs.position = pos
	gibs.z_index = 3
	for i in amount:
		var v := Vector2.UP.rotated(deg_to_rad(randf_range(-110.0, 110.0))) * randf_range(speed * 0.35, speed)
		gibs._pos.append(Vector2.ZERO)
		gibs._vel.append(v)
		var w := randi_range(GameData.BLOOD.gib_size_min, GameData.BLOOD.gib_size_max)
		gibs._w.append(w)
		gibs._h.append(clampi(randi_range(GameData.BLOOD.gib_size_min, mini(w + 1, GameData.BLOOD.gib_size_max)) - 1, 2, 5))
		gibs._bump.append(randi() % 4 if w >= 4 else 0)
		gibs._color.append(Blood.GIB_COLORS[randi() % Blood.GIB_COLORS.size()])
	parent.add_child(gibs)


func _physics_process(delta: float) -> void:
	_age += delta
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = WORLD_MASK
	var i := 0
	while i < _pos.size():
		var before := _pos[i]
		_vel[i].y += GameData.BLOOD.droplet_gravity * delta
		_pos[i] += _vel[i] * delta
		query.position = global_position + _pos[i]
		var hits := space.intersect_point(query, 1)
		if not hits.is_empty() or _age > LIFETIME:
			if not hits.is_empty() and hits[0].collider is Block and _vel[i].y > 0.0:
				_land(hits[0].collider, global_position + before, i)
			_remove(i)
			continue
		i += 1
	if _pos.is_empty():
		queue_free()
	queue_redraw()


## Rest on top of the block the chunk fell onto (nothing happens if it came in from the side).
func _land(block: Block, from: Vector2, i: int) -> void:
	var a := block.to_local(from)
	if a.y > -Block.SIZE / 2.0:
		return
	block.add_chunk(a.x, _w[i], _h[i], _bump[i], _color[i])


func _remove(i: int) -> void:
	_pos.remove_at(i)
	_vel.remove_at(i)
	_w.remove_at(i)
	_h.remove_at(i)
	_bump.remove_at(i)
	_color.remove_at(i)


func _draw() -> void:
	for i in _pos.size():
		Gibs.draw_lump(self, _pos[i].floor(), _w[i], _h[i], _bump[i], _color[i])


## A lump of flesh with its top-left corner at `at`: a block with an uneven edge, no outline.
static func draw_lump(canvas: CanvasItem, at: Vector2, w: int, h: int, bump: int, color: Color) -> void:
	canvas.draw_rect(Rect2(at, Vector2(w, h)), color)
	match bump:
		1:
			canvas.draw_rect(Rect2(at + Vector2(0, -1), Vector2(maxi(w / 2, 1), 1)), color)
		2:
			canvas.draw_rect(Rect2(at + Vector2(w - maxi(w / 2, 1), -1), Vector2(maxi(w / 2, 1), 1)), color)
		3:
			canvas.draw_rect(Rect2(at + Vector2(w, maxi(h / 2, 1) - 1), Vector2(1, 1)), color)
	if w >= 3 and h >= 3:  # a darker underside so it reads as a lump
		canvas.draw_rect(Rect2(at + Vector2(1, h - 1), Vector2(w - 1, 1)), color.darkened(0.3))
