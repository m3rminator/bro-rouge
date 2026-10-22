class_name Grenade
extends CharacterBody2D
## The Bro's hand grenade (design/entities/grenade.yaml, GameData.GRENADE). Flies in an arc,
## bounces off blocks and rolls, blinking red faster and faster, then explodes like one
## barrel. Only touches the world: characters never stop it. Enemies run from it (enemy.gd).

const STATS := GameData.GRENADE
const FRAMES := preload("res://assets/sprites/items_frames.tres")
const WORLD_MASK := 1

var _fuse: float = STATS.fuse_time
var _spin := 0.0
var _sprite: AnimatedSprite2D


## Throws a grenade from `pos` in `parent`'s space with velocity `vel`.
static func throw(parent: Node, pos: Vector2, vel: Vector2) -> Grenade:
	var g := Grenade.new()
	g.position = pos
	g.velocity = vel
	g._spin = signf(vel.x) * TAU * 2.0
	parent.add_child(g)
	return g


## Goes off right now at `pos` (thrown while hanging on a wall: it never leaves his hand).
static func blow(parent: Node, pos: Vector2) -> void:
	Explosion.detonate(parent, pos, power(), [pos])


static func power() -> Dictionary:
	return {"radius": STATS.blast_radius, "damage": STATS.blast_damage, "player_damage": STATS.blast_player_damage}


func _ready() -> void:
	add_to_group("grenades")
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
	_sprite.play("grenade")
	_sprite.position = Vector2(0, -1)  # the ball sits on the collision circle, the lever above it
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	velocity.y += STATS.gravity * delta
	var hit := move_and_collide(velocity * delta)
	if hit:
		var n := hit.get_normal()
		if n.y < -0.5 and absf(velocity.y) < 60.0:  # on the ground: roll to a stop
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, STATS.roll_friction * delta)
			_spin = velocity.x / STATS.radius
		else:
			if velocity.length() > 70.0:
				Sfx.play(self, "grenade_bounce", -8.0, 0.1)
			velocity = velocity.bounce(n) * STATS.bounce
	_sprite.rotation += _spin * delta
	_fuse -= delta
	var t := 1.0 - _fuse / STATS.fuse_time
	# 2 frames per blink: frames per second = 2 x blinks per second
	_sprite.speed_scale = lerpf(STATS.blink_speed[0], STATS.blink_speed[1], t * t) * 2.0 / FRAMES.get_animation_speed("grenade")
	if _fuse <= 0.0:
		blow(get_parent(), position)
		queue_free()

