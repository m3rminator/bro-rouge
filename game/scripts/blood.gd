class_name Blood
## Blood effects (design/entities/blood.yaml, GameData.BLOOD): a spray on every hit, a burst
## on every death, and a pool that stays under each body (stuck to the block below it).
## Variants are used in turn, so neighbouring hits never look the same.

const FRAMES := preload("res://assets/sprites/blood_frames.tres")
const SPRAYS := ["spray_0", "spray_1", "spray_2"]
const BURSTS := ["burst_0", "burst_1"]
const POOLS := ["pool_0", "pool_1", "pool_2"]
const SPRAY_ORIGIN: Vector2 = GameData.ANCHORS["blood"]["spray_origin"]
const COLORS := [Color("d4283a"), Color("96142a"), Color("5a0c1c")]  # master palette: blood_bright, blood, blood_dark
const POOL_Y := -18.0  # pool sprite center relative to the block center: rows 22-23 lie on the block's top

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


## Pool spreading under `body` on the block it rests on (none if it is not on a block).
static func pool_under(body: Node2D) -> void:
	var from := body.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 24), 1)
	var result := body.get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty() or not result.collider is Block:
		return
	var block: Block = result.collider
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


static func _droplets(parent: Node, pos: Vector2, dir: Vector2, amount: int, spread: float, speed: float) -> void:
	var drops := CPUParticles2D.new()
	drops.position = pos
	drops.z_index = 3
	drops.one_shot = true
	drops.amount = amount
	drops.lifetime = 0.6
	drops.explosiveness = 1.0
	drops.direction = dir
	drops.spread = spread
	drops.initial_velocity_min = speed * 0.4
	drops.initial_velocity_max = speed
	drops.gravity = Vector2(0, 500)
	drops.scale_amount_min = 1.0
	drops.scale_amount_max = 2.0
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.34, 0.67])
	colors.colors = PackedColorArray(COLORS)
	drops.color_initial_ramp = colors
	drops.finished.connect(drops.queue_free)
	parent.add_child(drops)
	drops.emitting = true
