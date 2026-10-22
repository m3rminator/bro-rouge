class_name BodyPiece
extends Node2D
## A limb of a soldier torn apart by an explosion (design/entities/body_pieces.yaml,
## GameData.BODY_PIECES). BodyPiece.tear() breaks the body into the drawn pieces (mook piece_*
## animations, from refrences/enemies/default/torn.jpg): torso, two arms, two legs and a few
## scraps of flesh; the head flies off as a Head. Every piece is thrown away from the blast
## spinning, trails blood from its torn end while it flies, bounces a few times spraying blood,
## and stays where it lands for the rest of the level.

const STATS := GameData.BODY_PIECES
const WORLD_MASK := 1
## [animation, offset from the feet of a standing body, half size of the drawing]
const PIECES := [
	["piece_torso", Vector2(0, -18), Vector2(8, 6.5)],
	["piece_arm", Vector2(-8, -18), Vector2(3, 6.5)],
	["piece_arm", Vector2(8, -18), Vector2(3, 6.5)],
	["piece_leg", Vector2(-3, -7), Vector2(3.5, 6.5)],
	["piece_leg_bent", Vector2(3, -7), Vector2(6.5, 6)],
]
const BITS := ["piece_bit_a", "piece_bit_b"]

var velocity := Vector2.ZERO
var _spin := 0.0  # rad/s
var _resting := false
var _half := Vector2.ONE
var _bleed := 0.0  # seconds of blood trail left
var _drip := 0.0
var _trail: CPUParticles2D
var _rest_time := 0.0


## Tear `body` (an Enemy) apart: the pieces fly off away from `center`, and the body is removed.
static func tear(body: Enemy, dir: int, center: Vector2) -> void:
	var parent := body.get_parent()
	var frames := body.sprite.sprite_frames
	if not frames.has_animation("piece_torso"):  # no pieces drawn for this sprite: just toss him
		body.toss(dir, GameData.EXPLOSION.fling_speed)
		return
	if body.can_behead():
		body._behead(dir)  # the head goes its own way (does nothing if it is already off)
	var feet := body.global_position + Vector2(0, Block.SIZE / 2.0)
	var squash := 0.4 if body._lying else 1.0  # a body lying on the ground is torn up flat
	var list := PIECES.duplicate()
	for i in randi_range(STATS.bits[0], STATS.bits[1]):
		list.append([BITS[randi() % BITS.size()], Vector2(randf_range(-6, 6), -randf_range(8, 20)), Vector2(2.5, 2.5)])
	for p in list:
		var offset: Vector2 = p[1] * Vector2(-1 if body.sprite.flip_h else 1, squash)
		var piece := BodyPiece.new()
		var sprite := Sprite2D.new()
		sprite.texture = frames.get_frame_texture(p[0], 0)
		sprite.flip_h = randi() % 2 == 0
		piece.add_child(sprite)
		piece._half = p[2]
		piece.position = feet + offset
		var away := signf(piece.position.x - center.x)
		if absf(piece.position.x - center.x) < 2.0:
			away = float(dir) if randi() % 3 > 0 else -float(dir)
		piece.velocity = Vector2(away * randf_range(STATS.throw_x[0], STATS.throw_x[1]), -randf_range(STATS.throw_y[0], STATS.throw_y[1]))
		piece._spin = deg_to_rad(STATS.spin) * away * randf_range(0.5, 1.2)
		BloodDrops.emit(parent, piece.position, Vector2(away, -1.0), STATS.piece_droplets, 80.0, 200.0)  # every piece sprays blood as it is torn off
		parent.add_child.call_deferred(piece)  # called from a physics callback (explosion)
	Blood.gore(parent, body.global_position)
	Sfx.play(body, "blood_splat", 0.0)
	Blood.pool_under(body)
	body.queue_free()


func _ready() -> void:
	z_index = 3
	rotation = randf_range(-PI, PI)
	_bleed = STATS.trail_time * randf_range(0.7, 1.3)
	_trail = CPUParticles2D.new()  # blood streaming out of the torn end as it flies
	_trail.amount = 24
	_trail.lifetime = 0.5
	_trail.local_coords = false
	_trail.direction = Vector2.UP
	_trail.spread = 70.0
	_trail.initial_velocity_min = 10.0
	_trail.initial_velocity_max = 45.0
	_trail.gravity = Vector2(0, 400)
	_trail.scale_amount_min = 1.0
	_trail.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Blood.COLORS[0], Blood.COLORS[1], Color(Blood.COLORS[2], 0.0)])
	_trail.color_ramp = ramp
	_trail.z_index = -4  # behind the blocks, like the head's trail
	add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	_bleed -= delta
	_trail.emitting = _bleed > 0.0
	_drip -= delta
	if _bleed > 0.0 and _drip <= 0.0:  # real drops too, so its path is stained
		_drip = STATS.drip_interval
		BloodDrops.emit(get_parent(), global_position, Vector2.UP, STATS.drip_droplets, 70.0, 60.0)
	if _resting:
		_rest_time += delta
		var left: float = STATS.rest_time + STATS.fade_time - _rest_time
		if left <= 0.0:
			queue_free()
		elif left < STATS.fade_time:  # sink into the ground (behind the blocks) while fading
			z_index = -1
			modulate.a = left / STATS.fade_time
			global_position.y += STATS.sink_speed * delta
		return
	if global_position.y > 4000.0:  # fell out of the map
		queue_free()
		return
	velocity.y += STATS.gravity * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, _half.y * signf(step.y)), WORLD_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		rotation += _spin * delta
		return
	var normal: Vector2 = hit.normal
	if normal.y < -0.5:  # landed
		if velocity.y > STATS.rest_speed:
			global_position.y = hit.position.y - _half.y
			velocity.y = -velocity.y * STATS.bounce
			velocity.x *= 0.6
			_spin *= 0.5
			Blood.spray(get_parent(), global_position, 1 if velocity.x >= 0.0 else -1)
			BloodDrops.emit(get_parent(), global_position, Vector2.UP, STATS.bounce_droplets, 120.0, 160.0)
		else:  # lie flat on the block
			_resting = true
			velocity = Vector2.ZERO
			rotation = roundf(rotation / (PI / 2.0)) * (PI / 2.0)
			var half_h := _half.x if absf(sin(rotation)) > 0.5 else _half.y
			global_position.y = hit.position.y - half_h + 1.0
	else:  # hit a wall or ceiling: bounce back
		velocity.x = -velocity.x * STATS.bounce
		velocity.y = absf(velocity.y) * 0.3
		global_position += normal * 2.0
