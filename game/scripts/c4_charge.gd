class_name C4Charge
extends CharacterBody2D
## Balal's remote charge (design/entities/c4.yaml, GameData.C4). Thrown like a grenade, it flies
## in an arc and sticks wherever it first touches - floor, wall or ceiling - or to the enemy it
## hits and rides along with him. If the block under it is destroyed it falls again; if its
## host dies it drops from the body. It never goes off by itself: Balal holds the grenade
## button and detonate_all() sets every planted charge off at once. Enemies cannot see it.

const STATS := GameData.C4
const FRAMES := preload("res://assets/sprites/items_frames.tres")
const WORLD_MASK := 1
const ENEMY_MASK := 4

var _stuck := false
var _host: Enemy = null
var _host_offset := Vector2.ZERO
var _sprite: AnimatedSprite2D


## Throws a charge from `pos` in `parent`'s space with velocity `vel`.
static func throw(parent: Node, pos: Vector2, vel: Vector2) -> C4Charge:
	var c := C4Charge.new()
	c.position = pos
	c.velocity = vel
	parent.add_child(c)
	return c


## Sets off every planted charge. Returns how many went off.
static func detonate_all(tree: SceneTree) -> int:
	var count := 0
	for c in tree.get_nodes_in_group("c4"):
		if c._stuck:
			c.detonate()
			count += 1
	return count


static func planted(tree: SceneTree) -> int:
	var count := 0
	for c in tree.get_nodes_in_group("c4"):
		if c._stuck:
			count += 1
	return count


func power() -> Dictionary:
	return {"radius": STATS.blast_radius, "damage": STATS.blast_damage, "player_damage": STATS.blast_player_damage}


func detonate() -> void:
	if is_queued_for_deletion():
		return
	Explosion.detonate(get_parent(), global_position, power(), [global_position])
	queue_free()


func _ready() -> void:
	add_to_group("c4")  # not "grenades": enemies do not see or fear it
	z_index = 3
	collision_layer = 0
	collision_mask = WORLD_MASK
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = STATS.radius
	shape.shape = circle
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.play("c4")
	_sprite.position = Vector2(0, -2)  # sits on the surface it is stuck to
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if _host != null:
		if not is_instance_valid(_host) or _host.dead:  # the body it rode on is dead: it drops
			_host = null
			_stuck = false
			rotation = 0.0
			velocity = Vector2.ZERO
		else:
			global_position = _host.global_position + _host_offset
			return
	if _stuck:
		if not _touches(WORLD_MASK, STATS.radius + 3.0):  # the block it held on to is gone
			_stuck = false
			rotation = 0.0
			velocity = Vector2.ZERO
		return
	velocity.y += GameData.GRENADE.gravity * delta
	var enemy := _enemy_touching()
	if enemy != null:
		_host = enemy
		_host_offset = global_position - enemy.global_position
		_stuck = true
		Sfx.play(self, "knife_stab", -8.0, 0.1)
		return
	var hit := move_and_collide(velocity * delta)
	if hit:
		_stuck = true
		velocity = Vector2.ZERO
		rotation = hit.get_normal().angle() + PI / 2.0  # its back lies flat on whatever it hit
		Sfx.play(self, "grenade_bounce", -8.0, 0.1)


func _touches(mask: int, radius: float) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = mask
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _enemy_touching() -> Enemy:
	var circle := CircleShape2D.new()
	circle.radius = STATS.radius + 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = ENEMY_MASK
	for result in get_world_2d().direct_space_state.intersect_shape(query, 8):
		if result.collider is Enemy and not result.collider.dead:
			return result.collider
	return null
