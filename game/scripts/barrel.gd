class_name Barrel
extends CharacterBody2D
## Explosive barrel (design/entities/barrel.yaml, GameData.BARREL). A hit sets it burning;
## after the fuse it explodes together with every barrel touching it (one bigger blast).
## Solid world body: bullets hit it, the Bro can stand on it, it falls when undermined.
## Once hit it bulges (burning animation) and little flames keep breaking out at random spots on it.

const FRAMES := preload("res://assets/sprites/barrel_frames.tres")
const STATS := GameData.BARREL
const DRUM := Vector2(22, 32)  # solid drum (the idle drum is 24 x 33 px); stands on the tile bottom
const TOUCH := DRUM + Vector2(6, 5)  # barrels closer than this on each axis count as touching (one drum + slack)
const FIRE_RAMP := [Color("fff6c8"), Color("ffd23e"), Color("f07c22"), Color("c43a1a"), Color(0.42, 0.41, 0.47, 0.0)]  # master: fire_white -> fire_red -> fading smoke

var burning := false
var exploded := false
var _fuse := 0.0
var _sprite: AnimatedSprite2D
var _puff := 0.0
var _vx := 0.0  # sideways speed while Bruce's blow has thrown it (otherwise it never moves sideways)
var _thrown := false  # thrown and not landed yet
var _thrown_air := false
var _fall_speed := 0.0  # fastest fall of the current drop; a hard landing sets it burning


func _ready() -> void:
	add_to_group("barrels")
	collision_layer = 1
	collision_mask = 1
	z_index = 1
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = "idle"
	_sprite.position.y = Block.SIZE / 2.0 - GameData.SPRITE_SIZES["barrel"].y / 2.0  # bottom on the tile bottom
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = DRUM
	shape.shape = rect
	shape.position = Vector2(0, Block.SIZE / 2.0 - DRUM.y / 2.0)
	add_child(shape)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta
		if _thrown:
			_thrown_air = true
	if is_on_wall():
		_vx = 0.0
	velocity.x = _vx
	if is_on_floor():
		_vx = move_toward(_vx, 0.0, 500.0 * delta)
	var falling := velocity.y > 40.0
	_fall_speed = maxf(_fall_speed, velocity.y)
	move_and_slide()
	if falling:
		_crush_below()
	if is_on_floor():
		if _fall_speed > 200.0 or _thrown_air:  # dropped from a height, or thrown by Bruce: it lights up on impact
			ignite(0.3)
		if _thrown_air:
			collision_layer = 1
			_thrown = false
			_thrown_air = false
		_fall_speed = 0.0
	if burning:
		_puff -= delta
		while _puff <= 0.0:
			_puff += STATS.fire_puff_interval * randf_range(0.5, 1.5)
			_flame_puff()
		_fuse -= delta
		if _fuse <= 0.0:
			explode()


## Bruce's blow: it flies `dir` at `speed` and is lifted by `hop` (negative is up), and lights up when it lands.
func toss(dir: int, speed: float, hop: float) -> void:
	_vx = dir * speed
	velocity.y = hop
	_thrown = true
	_thrown_air = false
	collision_layer = 0  # in flight it is solid to nothing, so the barrels thrown together do not stop each other


## A falling barrel crushes whoever is under it (the Bro bursts into gibs, see player.gd _crushed).
func _crush_below() -> void:
	var box := RectangleShape2D.new()
	box.size = DRUM
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.transform = Transform2D(0.0, global_position + Vector2(0, Block.SIZE / 2.0 - DRUM.y / 2.0 + 2.0))
	query.collision_mask = 2 | 4
	for result in get_world_2d().direct_space_state.intersect_shape(query, 4):
		if result.collider.has_method("_crushed"):
			result.collider._crushed()
		elif result.collider is Enemy and not result.collider.dead and velocity.y > 120.0:
			explode()  # dropped on someone's head: it goes off at once
			return


## Bullets: any hit lights it.
func hit(_damage: int, _direction := 0) -> void:
	ignite(STATS.fuse_time)


## Another explosion reached it: short fuse, so chains ripple outward.
func on_blast(_center: Vector2, _power: Dictionary) -> void:
	ignite(STATS.chain_fuse)


func ignite(fuse: float) -> void:
	if burning or exploded:
		return
	burning = true
	_fuse = fuse
	_sprite.play("burning")
	Sfx.play(self, "barrel_ignite", -8.0)


## One little flame breaking out somewhere on the drum (sides, top or front), in a random size.
func _flame_puff() -> void:
	var fire := CPUParticles2D.new()
	var spot := Vector2(randf_range(-DRUM.x / 2.0, DRUM.x / 2.0), Block.SIZE / 2.0 - randf_range(2.0, DRUM.y))
	fire.position = spot
	fire.z_index = 2  # in front of the drum
	fire.one_shot = true
	fire.amount = maxi(2, int(STATS.fire_particles * randf_range(0.5, 1.2)))
	fire.explosiveness = 0.6
	fire.lifetime = randf_range(0.35, 0.75)
	fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fire.emission_rect_extents = Vector2(2, 2)
	fire.direction = Vector2(spot.x / DRUM.x * 0.8, -1)  # leans away from the middle of the drum
	fire.spread = 30.0
	fire.initial_velocity_min = STATS.fire_speed * 0.3
	fire.initial_velocity_max = STATS.fire_speed
	fire.gravity = Vector2(0, -50)
	fire.scale_amount_min = 1.0
	fire.scale_amount_max = randf_range(2.5, 4.5)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.2))
	fire.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.7, 1.0])
	ramp.colors = PackedColorArray(FIRE_RAMP)
	fire.color_ramp = ramp
	fire.finished.connect(fire.queue_free)
	add_child(fire)
	fire.emitting = true


## Blow up this barrel and every barrel touching it (directly or through others) as one blast.
func explode() -> void:
	if exploded:
		return
	var cluster := _cluster()
	var center := Vector2.ZERO
	var sources := []
	for b in cluster:
		b.exploded = true
		center += b.position
		sources.append(b.position)
		b.queue_free()
	center /= cluster.size()
	var extra := cluster.size() - 1
	var power := {
		"radius": minf(STATS.blast_radius + STATS.radius_per_extra * extra, STATS.max_radius),
		"damage": STATS.blast_damage + STATS.damage_per_extra * extra,
		"player_damage": STATS.blast_player_damage,
	}
	Explosion.detonate(get_parent(), center, power, sources)


func _cluster() -> Array:
	var all := get_tree().get_nodes_in_group("barrels").filter(func(b): return not b.exploded)
	var found := [self]
	var i := 0
	while i < found.size():
		var a: Node2D = found[i]
		for b in all:
			if b not in found and absf(b.position.x - a.position.x) <= TOUCH.x and absf(b.position.y - a.position.y) <= TOUCH.y:
				found.append(b)
		i += 1
	return found
