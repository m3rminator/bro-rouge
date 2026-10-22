class_name Blood
## Blood effects (design/entities/blood.yaml, GameData.BLOOD): a spray on every hit, a burst
## on every death, and a pool that stays under each body (stuck to the block below it).
## Loose droplets fall and leave stains where they land (blood_drops.gd, blood_stains.gd).
## Variants are used in turn, so neighbouring hits never look the same.

const FRAMES := preload("res://assets/sprites/blood_frames.tres")
const SPRAYS := ["spray_0", "spray_1", "spray_2"]
const BURSTS := ["burst_0", "burst_1"]
const GIB_COLORS := [Color("d4283a"), Color("96142a"), Color("b81e32")]  # flesh: blood_bright, blood and a shade between
const POOLS := ["pool_0", "pool_1", "pool_2"]
const SPRAY_ORIGIN: Vector2 = GameData.ANCHORS["blood"]["spray_origin"]
const COLORS := [Color("d4283a"), Color("96142a"), Color("5a0c1c")]  # master palette: blood_bright, blood, blood_dark
const POOL_Y := -Block.SIZE / 2.0 - 10.0  # pool sprite center relative to the block center: rows 22-23 of its 24 px frame lie on the block's top

static var _turn := 0


static func _next(list: Array) -> String:
	_turn += 1
	return list[_turn % list.size()]


## Hit spray flying in `dir` (+1 right, -1 left) from `pos`.
static func spray(parent: Node, pos: Vector2, dir: int) -> void:
	var s := _effect(parent, pos, _next(SPRAYS))
	s.flip_h = dir < 0
	s.offset = Vector2(-SPRAY_ORIGIN.x * dir, -SPRAY_ORIGIN.y)
	_droplets(parent, pos, Vector2(dir, -0.7), GameData.BLOOD.droplets_hit, 35.0, 110.0)


## Death burst in all directions.
static func burst(parent: Node, pos: Vector2) -> void:
	_effect(parent, pos, _next(BURSTS))
	_droplets(parent, pos, Vector2.UP, GameData.BLOOD.droplets_death, 110.0, 150.0)
	Gibs.emit(parent, pos, GameData.BLOOD.gibs_death, 150.0)


## Knife kill: on top of the death burst, two sprays the way the knife went and a big
## shower of drops that fall and stain the ground.
static func knife_kill(parent: Node, pos: Vector2, dir: int, drops: int) -> void:
	spray(parent, pos, dir)
	spray(parent, pos + Vector2(0, 5), dir)
	_droplets(parent, pos, Vector2(dir, -1.0), drops, 60.0, 240.0)


## Gore: a kamikaze blowing up or a body bursting. Both bursts at once and a huge shower of
## droplets in every direction, so the ground and walls around get soaked.
static func gore(parent: Node, pos: Vector2) -> void:
	for anim in BURSTS:
		_effect(parent, pos, anim)
	_droplets(parent, pos, Vector2.UP, GameData.BLOOD.droplets_gore, 180.0, 230.0)
	Gibs.emit(parent, pos, GameData.BLOOD.gibs_gore, 220.0)
	var player := parent.get_tree().get_first_node_in_group("player")
	if player:
		player.shake(GameData.BLOOD.gore_shake)


## Pool spreading under `body` on the block it rests on (none if it is not on a block).
static func pool_under(body: Node2D) -> void:
	var from := body.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 24), 1)
	var result := body.get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty() or not result.collider is Block:
		return
	var block: Block = result.collider
	var under := from.x - block.global_position.x
	for c in block.get_children():
		if c is Grass:  # the pool soaks the blades around the body
			for dx in range(-8, 9, 2):
				c.stain_at(under + dx, COLORS[1], 5)
	var pool := AnimatedSprite2D.new()
	pool.sprite_frames = FRAMES
	pool.position = Vector2(clampf(from.x - block.global_position.x, -6.0, 6.0), POOL_Y)
	pool.z_index = 1
	block.add_child(pool)
	pool.play(_next(POOLS))


static func _effect(parent: Node, pos: Vector2, anim: String) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = FRAMES
	s.position = pos
	s.z_index = 3
	parent.add_child(s)
	s.play(anim)
	s.animation_finished.connect(s.queue_free)
	return s


## Loose droplets: real drops that fall and stain the blocks they land on (BloodDrops).
static func _droplets(parent: Node, pos: Vector2, dir: Vector2, amount: int, spread: float, speed: float) -> void:
	BloodDrops.emit(parent, pos, dir, amount, spread, speed)
