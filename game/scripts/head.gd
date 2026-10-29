class_name Head
extends CharacterBody2D
## A soldier's head blown off (design/entities/head.yaml, GameData.HEAD). It flies off
## spinning, trailing blood, bounces and rolls, then stays for the rest of the level.
## It never blocks anything: it only touches the ground (bullets fly through it and just
## nudge it, the Bro running into it kicks it away, spraying blood). The Bro's knife bursts it.

const STATS := GameData.HEAD
const FRAMES := preload("res://assets/sprites/mook_frames.tres")
const WORLD_MASK := 1

var _spin := 0.0  # rad/s
var _idle := 0.0  # seconds lying untouched; past rest_time it sinks and fades away
var _bleed := 0.0  # seconds of blood trail left
var _drip := 0.0
var _nudged := {}  # instance ids of bullets that already nudged it
var _kicked := 0.0  # > 0 just after a kick (one kick per touch)
var _trail: CPUParticles2D
var _sprite: AnimatedSprite2D


## Throws head `anim` (head_a / head_b) from `pos` in `parent`'s space, away to side `dir`.
static func throw(parent: Node, pos: Vector2, anim: String, dir: int, flip: bool, frames: SpriteFrames = FRAMES) -> Head:
	var head := Head.new()
	head.position = pos
	head.velocity = Vector2(dir * randf_range(STATS.throw_x[0], STATS.throw_x[1]), -randf_range(STATS.throw_y[0], STATS.throw_y[1]))
	head._spin = deg_to_rad(STATS.spin) * dir * randf_range(0.7, 1.2)
	head._sprite = AnimatedSprite2D.new()
	head._sprite.sprite_frames = frames
	head._sprite.animation = anim
	head._sprite.flip_h = flip
	head._sprite.position = Vector2(0, 0.5)  # the head sits in the middle of the 47 × 34 frame
	parent.add_child.call_deferred(head)  # often called from a bullet's physics callback
	return head


func _ready() -> void:
	add_to_group("heads")
	z_index = 3  # in front of the grass, so a head lying in it stays visible
	collision_layer = 0  # nothing hits it...
	collision_mask = WORLD_MASK  # ...it only lands on blocks
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = STATS.radius
	shape.shape = circle
	add_child(shape)
	add_child(_sprite)
	_bleed = STATS.trail_time
	_trail = CPUParticles2D.new()  # blood streaming out of the neck as it flies
	_trail.amount = Quality.n(40)
	_trail.lifetime = 0.6
	_trail.local_coords = false
	_trail.direction = Vector2.UP
	_trail.spread = 60.0
	_trail.initial_velocity_min = 10.0
	_trail.initial_velocity_max = 50.0
	_trail.gravity = Vector2(0, 400)
	_trail.scale_amount_min = 1.0
	_trail.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Blood.COLORS[0], Blood.COLORS[1], Color(Blood.COLORS[2], 0.0)])
	_trail.color_ramp = ramp
	_trail.z_index = -4  # behind the blocks (z 0): the ground hides drops falling past it
	add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	if _idle > GameData.BODY_PIECES.rest_time:
		_fade(delta)
		return
	velocity.y += STATS.gravity * delta
	var hit := move_and_collide(velocity * delta)
	if hit:
		var n := hit.get_normal()
		if n.y < -0.5 and absf(velocity.y) < STATS.rest_speed:  # resting on the ground: roll
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, STATS.roll_friction * delta)
			_spin = velocity.x / STATS.radius
			_idle = _idle + delta if absf(velocity.x) < 8.0 else 0.0
		else:
			_idle = 0.0  # bounce, losing speed; a little blood where it hits
			if velocity.length() > 80.0:
				BloodDrops.emit(get_parent(), global_position, n, 3, 50.0, 60.0)
			velocity = velocity.bounce(n) * STATS.bounce
			_spin *= -0.6 if n.y < -0.5 else 1.0
	_sprite.rotation += _spin * delta
	_nudge_from_bullets()
	_kicked -= delta
	if _kicked <= 0.0:
		_kick_from_bro()
	_bleed -= delta
	_trail.emitting = _bleed > 0.0
	_drip -= delta
	if _bleed > 0.0 and _drip <= 0.0:  # real drops too, so its path is stained
		_drip = 0.12
		BloodDrops.emit(get_parent(), global_position, Vector2.UP, 2, 70.0, 60.0)


## Untouched for rest_time: sinks into the ground behind the blocks and fades, like the gore pieces.
func _fade(delta: float) -> void:
	var pieces: Dictionary = GameData.BODY_PIECES
	_idle += delta
	var left: float = pieces.rest_time + pieces.fade_time - _idle
	if left <= 0.0:
		queue_free()
		return
	z_index = -1
	modulate.a = left / pieces.fade_time
	global_position.y += pieces.sink_speed * delta
	_trail.emitting = false


## Bullets fly straight through; one passing close gives the head a small knock and spin.
func _nudge_from_bullets() -> void:
	for b in get_tree().get_nodes_in_group("bullets"):
		if _nudged.has(b.get_instance_id()) or b.global_position.distance_to(global_position) > STATS.radius + 4.0:
			continue
		_nudged[b.get_instance_id()] = true
		_idle = 0.0
		velocity += Vector2(b.direction * STATS.bullet_nudge, -STATS.bullet_nudge * 0.6)
		_spin += deg_to_rad(360.0) * b.direction
		BloodDrops.emit(get_parent(), global_position, Vector2(b.direction, -0.5), 3, 30.0, 70.0)


## The Bro running into it kicks it away (only while he is moving), spraying blood.
func _kick_from_bro() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or p.dead or absf(p.velocity.x) < 20.0:
		return
	var d: Vector2 = global_position - p.global_position
	if absf(d.x) > STATS.kick_reach or d.y < Block.SIZE / 2.0 - p.STATS.hitbox[1] or d.y > Block.SIZE / 2.0 + 2.0:
		return
	var dir := signf(p.velocity.x)
	velocity = Vector2(dir * STATS.kick_speed + p.velocity.x * 0.5, -STATS.kick_up * randf_range(0.8, 1.2))
	_spin = deg_to_rad(STATS.spin) * dir
	_kicked = 0.4
	_idle = 0.0
	_bleed = maxf(_bleed, STATS.kick_bleed)  # the kick squeezes more blood out of it
	BloodDrops.emit(get_parent(), global_position, Vector2(dir, -1.0), STATS.kick_drops, 80.0, 170.0)


## The Bro's knife: the head bursts into blood.
func burst() -> void:
	Blood.burst(get_parent(), global_position)
	BloodDrops.emit(get_parent(), global_position, Vector2.UP, STATS.burst_drops, 140.0, 160.0)
	Sfx.play(get_parent(), "blood_splat", -4.0)
	queue_free()
