class_name Block
extends StaticBody2D
## Destructible terrain tile (GameData.BLOCK.size square). Cracks more with every hit and breaks into debris after GameData.BLOCK.hp hits, or at
## once when an explosion's radius covers its center.

const SIZE: int = GameData.BLOCK.size
const FRAMES := preload("res://assets/sprites/terrain_frames.tres")
const CRACK_FRAMES := preload("res://assets/sprites/cracks_frames.tres")
const EARTH_DEBRIS := Color("4a4a2c")  # master palette: earth
const STONE_DEBRIS := Color("6c6e60")  # master palette: stone

## Tuning numbers live in design/entities/block.yaml (generated into GameData.BLOCK).
var hp: int = GameData.BLOCK.hp
var _sprite: AnimatedSprite2D
var _stains: BloodStains
var _chunks: BlockChunks
var _cracks: AnimatedSprite2D
var _debris_color := EARTH_DEBRIS


func setup(tile_anim: String, flip_h := false, flip_v := false, debris_color := EARTH_DEBRIS) -> Block:
	_debris_color = debris_color
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = tile_anim
	_sprite.flip_h = flip_h
	_sprite.flip_v = flip_v
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE, SIZE)
	shape.shape = rect
	add_child(shape)
	collision_layer = 1
	collision_mask = 0
	return self


## A blood drop landed on this block (BloodDrops). `at` is in block space.
func stain(at: Vector2, size: Vector2, color: Color) -> void:
	if _stains == null:
		_stains = BloodStains.new()
		_stains.z_index = 1  # in front of the tile
		add_child(_stains)
	_stains.add(at, size, color)


## A chunk of flesh landed on top of this block (Gibs). `x` is in block space.
func add_chunk(x: float, w: int, h: int, bump: int, color: Color) -> void:
	if _chunks == null:
		_chunks = BlockChunks.new()
		_chunks.z_index = 1
		add_child(_chunks)
	_chunks.add(x, w, h, bump, color)


func hit(damage: int, _direction := 0) -> void:
	hp -= damage
	if hp > 0:
		_crack()
		Sfx.play(self, "block_hit", -10.0)
		_sprite.modulate = Color(2, 2, 2)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.08)
		return
	Sfx.play(self, "block_break", -4.0)
	destroy()


## Cracks grow with the damage taken: the last stage shows one hit before the block breaks.
## Each block has its own crack pattern, picked from its map position (art/sprites/cracks.yaml).
func _crack() -> void:
	var stages: int = GameData.BLOCK.crack_stages
	var patterns := CRACK_FRAMES.get_animation_names().size() / stages
	var taken := GameData.BLOCK.hp - hp
	var stage := ceili(float(taken) * stages / (GameData.BLOCK.hp - 1))
	if _cracks == null:
		_cracks = AnimatedSprite2D.new()
		_cracks.sprite_frames = CRACK_FRAMES
		_cracks.z_index = 1  # in front of the tile, behind blood stains (added later)
		add_child(_cracks)
	_cracks.animation = "crack_%d_%d" % [((int(position.x) * 73) ^ (int(position.y) * 151)) % patterns, stage]


## Explosions: destroyed if the blast covers the block's center (the explosion plays the sound).
func on_blast(center: Vector2, power: Dictionary) -> void:
	var d := global_position.distance_to(center)
	if d <= power.radius * GameData.EXPLOSION.core_share or (power.has("tri") and _in_triangle(global_position, power.tri)):
		destroy()


static func _in_triangle(p: Vector2, t: Array) -> bool:
	var d1: float = (p - t[1]).cross(t[0] - t[1])
	var d2: float = (p - t[2]).cross(t[1] - t[2])
	var d3: float = (p - t[0]).cross(t[2] - t[0])
	return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


func destroy() -> void:
	if is_queued_for_deletion():
		return
	var walls = get_parent().get("walls")
	if walls:
		walls.reveal(position)
	_chain_above()
	for c in get_children().duplicate():
		if c is Grass:
			c.burst()
		elif c is TreeDecor:
			c.fall()
	var debris := CPUParticles2D.new()
	debris.one_shot = true
	debris.amount = GameData.BLOCK.debris_amount
	debris.lifetime = 0.6
	debris.explosiveness = 1.0
	debris.direction = Vector2.UP
	debris.spread = 70.0
	debris.initial_velocity_min = 60.0
	debris.initial_velocity_max = 140.0
	debris.gravity = Vector2(0, 500)
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 3.0
	debris.color = _debris_color
	debris.position = position
	debris.z_index = 2
	debris.finished.connect(debris.queue_free)
	get_parent().add_child(debris)
	debris.emitting = true
	queue_free()


## Sometimes the block right above breaks as well, a beat later (the chain can continue upward).
func _chain_above() -> void:
	if randf() >= GameData.BLOCK.chain_break:
		return
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position + Vector2(0, -SIZE)
	query.collision_mask = 1
	for result in get_world_2d().direct_space_state.intersect_point(query, 4):
		var above: Object = result.collider
		if above is Block and not above.is_queued_for_deletion():
			get_tree().create_timer(0.08).timeout.connect(func():
				if is_instance_valid(above):
					above.destroy())
			return
