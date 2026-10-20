class_name Explosion
extends Node2D
## A blast (design/entities/explosion.yaml, GameData.EXPLOSION). Hits everything inside the
## radius at once: blocks break, enemies take damage, the Bro loses hearts, barrels ignite,
## bodies are tossed. One source -> one of three small blasts; a cluster of barrels -> a
## mushroom fireball + shockwave scaled to the cluster, with a small blast on every barrel.

const SMALL := preload("res://assets/sprites/explosion_frames.tres")
const BIG := preload("res://assets/sprites/explosion_big_frames.tres")
const STATS := GameData.EXPLOSION
const SMALL_BLASTS := ["blast_a", "blast_b", "blast_c"]
const HIT_MASK := 1 | 2 | 4 | 8  # world, player, enemies, corpses
const BIG_GROUND: Vector2 = GameData.ANCHORS["explosion_big"]["ground"]  # where the fireball touches the ground
const SHOCK_CENTER := Vector2(0, 8)  # ring center relative to the 64 px frame center (art: y = 40)
const SHOCK_RADIUS := 31.0  # ring radius in the last frame of "shockwave"

var power: Dictionary  # radius (px), damage (to enemies), player_damage (hearts)
var sources: Array  # positions of the barrels in the cluster (or the one kamikaze)


## Explode at `center` (in `parent`'s space).
static func detonate(parent: Node, center: Vector2, blast_power: Dictionary, blast_sources: Array) -> void:
	var boom := Explosion.new()
	boom.position = center
	boom.power = blast_power
	boom.sources = blast_sources
	parent.add_child(boom)


func _ready() -> void:
	z_index = 4
	var extra := sources.size() - 1
	_hit_everything()
	if extra == 0:
		_blast(SMALL_BLASTS[_variant(position)], Vector2.ZERO, 0.0)
		_smoke(Vector2.ZERO, STATS.smoke_puffs)
		_fire(STATS.fire_particles, 90.0)
		Sfx.play(self, "explosion_small", -2.0)
	else:
		_big(extra)
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.shake(minf(STATS.shake + STATS.shake_per_extra * extra, 9.0))
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _hit_everything() -> void:
	var circle := CircleShape2D.new()
	circle.radius = power.radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = HIT_MASK
	var seen := {}
	for result in get_world_2d().direct_space_state.intersect_shape(query, 512):
		var body: Object = result.collider
		if body == null or seen.has(body) or not body.has_method("on_blast"):
			continue
		seen[body] = true
		body.on_blast(global_position, power)


## Cluster: fireball + shockwave at the bottom of the pile, a small blast on every barrel.
func _big(extra: int) -> void:
	var ground := 0.0
	for s in sources:
		ground = maxf(ground, s.y - position.y + 8.0)
	var grow := 1.0 + STATS.big_scale_per_extra * maxi(extra - 1, 0)
	var fireball := _sprite(BIG, "inferno", Vector2(0, ground) - BIG_GROUND * grow, grow)
	fireball.z_index = 1
	var ring: float = power.radius / SHOCK_RADIUS
	_sprite(BIG, "shockwave", Vector2(0, ground - 4) - SHOCK_CENTER * ring, ring)
	for i in sources.size():
		var at: Vector2 = sources[i] - position
		_blast(SMALL_BLASTS[(_variant(sources[i]) + i) % 3], at, i * STATS.secondary_delay)
		_smoke(at, STATS.smoke_puffs)
	_fire(STATS.fire_particles * 2 + 8 * extra, 160.0)
	Sfx.play(self, "explosion_big", 0.0)


func _blast(anim: String, at: Vector2, delay: float) -> void:
	var s := _sprite(SMALL, anim, at, 1.0)
	if delay > 0.0:
		s.visible = false
		s.stop()
		get_tree().create_timer(delay).timeout.connect(func():
			s.visible = true
			s.play(anim))


func _smoke(at: Vector2, count: int) -> void:
	for i in count:
		var s := _sprite(SMALL, "smoke_%d" % (i % 2), at + Vector2((i * 2 - 1) * 6, -4), 1.0)
		s.z_index = -1
		s.speed_scale = 0.8 + 0.15 * i


func _sprite(frames: SpriteFrames, anim: String, at: Vector2, scale_by: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.position = at
	s.scale = Vector2(scale_by, scale_by)
	add_child(s)
	s.play(anim)
	s.animation_finished.connect(s.queue_free)
	return s


## Burning sparks in fire colors (master palette: fire_white -> fire_red -> smoke).
func _fire(amount: int, speed: float) -> void:
	var fire := CPUParticles2D.new()
	fire.one_shot = true
	fire.amount = amount
	fire.lifetime = 0.7
	fire.explosiveness = 1.0
	fire.direction = Vector2.UP
	fire.spread = 80.0
	fire.initial_velocity_min = speed * 0.4
	fire.initial_velocity_max = speed
	fire.gravity = Vector2(0, 400)
	fire.scale_amount_min = 1.0
	fire.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.55, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color("fff6c8"), Color("ffd23e"), Color("f07c22"), Color("c43a1a"), Color("6c6878")])
	fire.color_ramp = ramp
	fire.finished.connect(fire.queue_free)
	add_child(fire)
	fire.emitting = true


## Same formula as terrain variants, so the same barrel always gets the same small blast.
static func _variant(at: Vector2) -> int:
	var x := int(floor(at.x / 16.0))
	var y := int(floor(at.y / 16.0))
	return ((x * 73) ^ (y * 151)) % 3
