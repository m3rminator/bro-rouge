class_name BloodDrops
extends Node2D
## A handful of real blood droplets (design/entities/blood.yaml, GameData.BLOOD). Each one
## flies, falls with gravity and, where it hits a block, leaves a stain on that block that
## stays (BloodStains). Drops that hit anything else, or fall for too long, just vanish.

const LIFETIME := 2.5
const WORLD_MASK := 1

var _pos: PackedVector2Array
var _vel: PackedVector2Array
var _color: PackedColorArray
var _size: PackedInt32Array
var _age := 0.0
var _budget := 0


## `amount` drops from `pos` (in `parent`'s space) flying around `dir`, within `spread`
## degrees either side, at up to `speed` px/s.
static func emit(parent: Node, pos: Vector2, dir: Vector2, amount: int, spread: float, speed: float) -> void:
	amount = Quality.take("drops", Quality.n(amount))  # a cap on how many are alive at once
	if amount <= 0:
		return
	var drops := BloodDrops.new()
	drops._budget = amount
	drops.position = pos
	drops.z_index = 3
	for i in amount:
		var v := dir.normalized().rotated(deg_to_rad(randf_range(-spread, spread))) * randf_range(speed * 0.4, speed)
		drops._pos.append(Vector2.ZERO)
		drops._vel.append(v)
		drops._color.append(Blood.COLORS[randi() % Blood.COLORS.size()])
		drops._size.append(randi_range(GameData.BLOOD.drop_size_min, GameData.BLOOD.drop_size_max))
	parent.add_child(drops)


func _exit_tree() -> void:
	Quality.give("drops", _budget)


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
			if not hits.is_empty() and hits[0].collider is Block:
				_land(hits[0].collider, global_position + before, global_position + _pos[i], i)
			_remove(i)
			continue
		i += 1
	if _pos.is_empty():
		queue_free()
	queue_redraw()


## Stain the block on the face the drop came through.
func _land(block: Block, from: Vector2, to: Vector2, i: int) -> void:
	var a := block.to_local(from)
	var b := block.to_local(to)
	var half := Block.SIZE / 2.0
	var at: Vector2
	var shape: Vector2
	if a.y <= -half:  # fell on top: splats wider
		shape = Vector2(_size[i] + 2, 2)
		at = Vector2(clampf(b.x, -half, half - shape.x), -half)
	elif a.x <= -half:  # left wall
		shape = Vector2(2, _size[i])
		at = Vector2(-half, clampf(b.y, -half, half - shape.y))
	elif a.x >= half:  # right wall
		shape = Vector2(2, _size[i])
		at = Vector2(half - 2, clampf(b.y, -half, half - shape.y))
	else:  # ceiling
		shape = Vector2(2, 2)
		at = Vector2(clampf(b.x, -half, half - 2), half - 2)
	block.stain(at.floor(), shape, _color[i])
	if a.y <= -half:  # and the grass standing there keeps it
		for c in block.get_children():
			if c is Grass:
				c.stain_at(b.x, _color[i])


func _remove(i: int) -> void:
	_pos.remove_at(i)
	_vel.remove_at(i)
	_color.remove_at(i)
	_size.remove_at(i)


func _draw() -> void:
	for i in _pos.size():
		draw_rect(Rect2(_pos[i].floor(), Vector2(_size[i], _size[i])), _color[i])
