class_name Barrel
extends CharacterBody2D
## Explosive barrel (design/entities/barrel.yaml, GameData.BARREL). A hit sets it burning;
## after the fuse it explodes together with every barrel touching it (one bigger blast).
## Solid world body: bullets hit it, the Bro can stand on it, it falls when undermined.

const FRAMES := preload("res://assets/sprites/barrel_frames.tres")
const STATS := GameData.BARREL
const TOUCH := 20.0  # barrels closer than this on both axes count as touching (one tile + slack)

var burning := false
var exploded := false
var _fuse := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("barrels")
	collision_layer = 1
	collision_mask = 1
	z_index = 1
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = "idle"
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 13)  # the drum (rows 3-15 of the 16 px frame); flames above are not solid
	shape.shape = rect
	shape.position = Vector2(0, 1.5)
	add_child(shape)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta
	velocity.x = 0.0
	move_and_slide()
	if burning:
		_fuse -= delta
		if _fuse <= 0.0:
			explode()


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
			if b not in found and absf(b.position.x - a.position.x) <= TOUCH and absf(b.position.y - a.position.y) <= TOUCH:
				found.append(b)
		i += 1
	return found
