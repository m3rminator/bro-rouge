class_name TreeDecor
extends Node2D
## A background palm on top of a grass block (design/entities/tree.yaml, GameData.TREE). Not solid, nobody
## pushes it; it only sways when something explodes nearby (TreeDecor.blast) and topples when its
## block is destroyed (fall). Child of its Block. The sprite is any animation of the trees sheet.

const MAIN := preload("res://scripts/main.gd")
const STATS := GameData.TREE
const FRAMES := preload("res://assets/sprites/trees_frames.tres")
const PLANTS := ["palm_3", "palm_4"]  # low plants (bush, fern) of the trees sheet; every other animation is a tree
const LEAF_COLORS := [Color("24502a"), Color("3e8034"), Color("7cc04e")]

var anim := ""  # which animation of the sheet
var dx := 0.0  # px from the block's middle
var _sprite: AnimatedSprite2D
var _angle := 0.0  # degrees, + leans right
var _vel := 0.0
var _falling := false


## What grows where: tile (Vector2i) -> [[anim, dx], ...] for every grass block under open sky (`sky`).
## Palms stand in groups - a first one and group_size - 1 more beside it, each a random gap away
## (gap_min..gap_max blocks, either side), each a random kind. Low plants (bush, fern) grow at the foot of
## palms, between them, and now and then alone. Same level -> same plants (all seeded by tile position).
static func plan(sky: Array) -> Dictionary:
	var by_column := {}
	for t in sky:
		if not by_column.has(t.x):
			by_column[t.x] = []
		by_column[t.x].append(t)
	var trees := _tree_kinds()
	var out := {}
	var palm_tiles := {}  # Vector2i -> true
	for t in sky:
		if palm_tiles.has(t) or MAIN.tile_hash(t.x, t.y, 7) % 1000 >= int(STATS.chance * 1000.0) or _crowded(palm_tiles, t):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = MAIN.tile_hash(t.x, t.y, 9)
		var members: Array[Vector2i] = [t]
		palm_tiles[t] = true
		var x: int = t.x
		var dir: int = 1 if rng.randf() < 0.5 else -1
		for i in int(STATS.group_size) - 1:
			x += dir * rng.randi_range(int(STATS.gap_min), int(STATS.gap_max))
			if rng.randf() < 0.3:
				dir = -dir  # the group does not always march one way
			for c in by_column.get(x, []):
				if absi(c.y - t.y) <= 4 and not _crowded(palm_tiles, c):
					palm_tiles[c] = true
					members.append(c)
					break
		for m in members:
			_put(out, m, trees[rng.randi() % trees.size()], 0.0)
			if rng.randf() < STATS.plant_foot_chance:  # a bush or fern beside the trunk
				_put(out, m, PLANTS[rng.randi() % PLANTS.size()], rng.randf_range(-9.0, 9.0))
		members.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		for i in members.size() - 1:  # between neighbours
			for xx in range(members[i].x + 1, members[i + 1].x):
				if rng.randf() < STATS.plant_between_chance:
					for c in by_column.get(xx, []):
						if absi(c.y - t.y) <= 4 and not palm_tiles.has(c):
							_put(out, c, PLANTS[rng.randi() % PLANTS.size()], rng.randf_range(-6.0, 6.0))
							break
	for t in sky:  # the odd one alone
		if not palm_tiles.has(t) and not out.has(t) and MAIN.tile_hash(t.x, t.y, 11) % 1000 < int(STATS.plant_alone_chance * 1000.0):
			_put(out, t, PLANTS[MAIN.tile_hash(t.x, t.y, 12) % PLANTS.size()], 0.0)
	return out


static func _put(out: Dictionary, t: Vector2i, anim: String, dx: float) -> void:
	if not out.has(t):
		out[t] = []
	out[t].append([anim, dx])


static func _tree_kinds() -> Array:
	var trees := []
	for n in FRAMES.get_animation_names():
		if not PLANTS.has(String(n)):
			trees.append(String(n))
	return trees


static func make(kind: String, offset: float) -> TreeDecor:
	var t := TreeDecor.new()
	t.anim = kind
	t.dx = offset
	return t


static func _crowded(placed: Dictionary, t: Vector2i) -> bool:
	for p in placed:
		if absi(p.x - t.x) < STATS.min_gap and absi(p.y - t.y) <= 4:
			return true
	return false


func _ready() -> void:
	add_to_group("trees")
	z_index = -1  # behind everything on the ground (the block's own grass is drawn over its foot)
	var plant := PLANTS.has(anim)
	var h := MAIN.tile_hash(int(global_position.x), int(global_position.y), 8)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.animation = anim
	var size := FRAMES.get_frame_texture(anim, 0).get_size()
	var base_x: float = STATS.plant_base_x if plant else STATS.base_x
	var bottom: float = STATS.plant_bottom if plant else size.y
	_sprite.position = Vector2(-base_x, -bottom + STATS.sink)
	_sprite.flip_h = (h >> 4) & 1 == 1
	if _sprite.flip_h:
		_sprite.position.x = -(size.x - base_x)
	add_child(_sprite)
	position = Vector2(dx, -Block.SIZE / 2.0)
	set_process(false)


func _process(delta: float) -> void:
	_vel += (-STATS.stiffness * _angle - STATS.damping * _vel) * delta
	_angle = clampf(_angle + _vel * delta, -STATS.max_angle, STATS.max_angle)
	rotation_degrees = _angle
	if absf(_angle) < 0.05 and absf(_vel) < 0.5:
		_angle = 0.0
		_vel = 0.0
		rotation = 0.0
		set_process(false)


## Explosion at `center` (radius `radius`): palms in range sway away from it and shake leaves loose.
static func blast(tree: SceneTree, center: Vector2, radius: float) -> void:
	var reach: float = radius * STATS.blast_range
	for t in tree.get_nodes_in_group("trees"):
		var dist: float = t.global_position.distance_to(center)
		if dist > reach or t._falling:
			continue
		var power: float = 1.0 - dist / reach
		var side := signf(t.global_position.x - center.x)
		t._vel += (side if side != 0.0 else 1.0) * STATS.blast_push * power * randf_range(0.8, 1.1)
		t.set_process(true)
		t._shed(maxi(1, roundi(STATS.leaves * power)))


func _shed(count: int) -> void:
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.amount = count
	bits.lifetime = 1.4
	bits.explosiveness = 0.9
	bits.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bits.emission_rect_extents = Vector2(14.0, 4.0)
	bits.direction = Vector2.DOWN
	bits.spread = 70.0
	bits.initial_velocity_min = 10.0
	bits.initial_velocity_max = 50.0
	bits.gravity = Vector2(0, 90)
	bits.damping_min = 10.0
	bits.damping_max = 30.0
	bits.angular_velocity_min = -240.0
	bits.angular_velocity_max = 240.0
	bits.scale_amount_min = 1.5
	bits.scale_amount_max = 2.5
	var variety := Gradient.new()
	variety.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	variety.offsets = PackedFloat32Array([0.0, 0.33, 0.66])
	variety.colors = PackedColorArray(LEAF_COLORS)
	bits.color_initial_ramp = variety
	bits.position = Vector2(0, -FRAMES.get_frame_texture(_sprite.animation, 0).get_height() * 0.8)
	bits.finished.connect(bits.queue_free)
	add_child(bits)
	bits.emitting = true


## Its block was destroyed: the palm topples over and fades out.
func fall() -> void:
	var level := get_parent().get_parent()
	if level == null or _falling:
		return
	_falling = true
	var at := global_position
	get_parent().remove_child(self)
	level.add_child(self)
	global_position = at
	set_process(false)
	var dir := 1.0 if randf() < 0.5 else -1.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation_degrees", dir * 80.0, STATS.fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, STATS.fall_time * 0.5).set_delay(STATS.fall_time * 0.5)
	tween.chain().tween_callback(queue_free)
