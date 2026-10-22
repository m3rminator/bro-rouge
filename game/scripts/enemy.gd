class_name Enemy
extends CharacterBody2D
## Shared enemy behaviour: line of sight, patrolling, blood on every hit, death (kill count,
## blood burst, a body that stays in a pool of blood), and being tossed by explosions.
## Bodies stay physical: the Bro bumps and drags them, bullets knock them back
## (design/entities/corpse.yaml, GameData.CORPSE).
## Subclasses set `stats` / `eye` / `sprite_name` before calling super._ready() and implement _think().

signal health_changed(hp: int, max_hp: int)

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
const WORLD_MASK := 1
const CORPSE_LAYER := 8  # physics layer 4 "corpses": explosions and the Bro's bullets touch bodies
const CORPSE := GameData.CORPSE

@onready var sprite: AnimatedSprite2D = $Sprite

var stats: Dictionary
var eye := Vector2.ZERO  # eye anchor relative to the body origin (facing right)
var sprite_name := ""  # art/sprites/<name>.yaml — places the frame so the feet are on the tile bottom
var facing := -1
var hp := 1
var dead := false
var death_sound := "enemy_death"
var _pause := 0.0
var _pooled := false
var _air_top := INF  # highest point (smallest y) of the current time in the air; INF while on the ground
var _pool_x := INF  # where the last pool was left (a new one only after the body moved)
var _bubble: AnimatedSprite2D
var _lying := false
var _shots_taken := 0  # bullets this body has absorbed; it bursts at CORPSE.burst_hits
var _bumped := false  # the Bro is walking through this body right now
var _dead_anim := "dead"  # lying pose; sprites with two (dead_a / dead_b) get one at random per body
var tears_apart := true  # a blast rips the body into pieces (BodyPiece); kamikazes keep theirs for the fuse
var _stab_hits := 0  # knife hits taken that did not kill (a slower knife needs knife_hits of them)
var _shoved := 0.0  # > 0 while sliding back from a knife hit he survived (no AI meanwhile)
var _headless := false  # his head was blown off (Head): headless poses, blood fountain from the neck
var _fountain: CPUParticles2D
var _fountain_left := 0.0
var _fountain_drip := 0.0
var _fountain_side := 1  # which way the neck points in the unrotated sprite
var _grenade_seen := 0.0  # how long a live grenade has been in sight (he panics at GRENADE.flee_reaction)
var _fleeing: Node2D = null  # the grenade he is running from


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	hp = stats.hp
	if sprite_name != "":
		sprite.position.y = Block.SIZE / 2.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0
		eye += Vector2(0, sprite.position.y)
	$Collision.shape = $Collision.shape.duplicate()  # every body gets its own box (it changes when he dies)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[0], stats.hitbox[1])
	$Collision.position.y = Block.SIZE / 2.0 - stats.hitbox[1] / 2.0  # feet on the bottom of the start tile
	_bubble = AnimatedSprite2D.new()
	_bubble.sprite_frames = FX_FRAMES
	_bubble.animation = "alert"
	_bubble.position = Vector2(0, 2 - stats.hitbox[1] - 6)
	_bubble.visible = false
	add_child(_bubble)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += stats.gravity * delta
	if dead:
		_dead_process(delta)
		return
	if _shoved > 0.0:
		_shoved -= delta
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		move_and_slide()
		_check_fall()
		_animate()
		return
	if not _flee(delta):
		_think(delta)
	move_and_slide()
	_check_fall()
	_animate()


## Landing after a long drop kills (stats.fall_death_height; 0 = immune). Measured from the
## top of the flight, so being blown high into the air counts too.
func _check_fall() -> void:
	if is_on_floor():
		var fell := global_position.y - _air_top
		_air_top = INF
		var limit: float = stats.get("fall_death_height", 0.0)
		if limit > 0.0 and fell >= limit - 1.0:  # a drop of exactly the limit counts
			_fall_death()
	else:
		_air_top = minf(_air_top, global_position.y)


## Splattered by the landing: dies and bursts into gore on the spot, like a shot body.
func _fall_death() -> void:
	if not dead:
		die(0)
	_burst_body()


## A live grenade in sight and close: after flee_reaction he panics and runs away from it
## until it is gone. Returns true while fleeing (the normal AI is skipped).
func _flee(delta: float) -> bool:
	if not fears_grenades():
		return false
	if _fleeing != null and not is_instance_valid(_fleeing):
		_fleeing = null
	if _fleeing == null:
		var g := _grenade_in_sight()
		if g == null:
			_grenade_seen = 0.0
			return false
		_grenade_seen += delta
		if _grenade_seen < GameData.GRENADE.flee_reaction:
			return false
		_fleeing = g
		_grenade_seen = 0.0
		Sfx.play(self, "enemy_panic", -4.0, 0.1)
	var away := signf(global_position.x - _fleeing.global_position.x)
	facing = int(away) if away != 0.0 else facing
	velocity.x = facing * GameData.GRENADE.flee_speed
	if is_on_wall():
		velocity.x = 0.0  # cornered
	return true


## Enemies that run from grenades (the Brute does not).
func fears_grenades() -> bool:
	return true


func _grenade_in_sight() -> Node2D:
	var eye_pos := global_position + Vector2(eye.x * facing, eye.y)
	for g in get_tree().get_nodes_in_group("grenades"):
		if g.global_position.distance_to(global_position) <= GameData.GRENADE.flee_range and ray(eye_pos, g.global_position).is_empty():
			return g
	return null


## AI step for living enemies — set velocity here. Overridden by every enemy.
func _think(_delta: float) -> void:
	pass


func _animate() -> void:
	pass


func _dead_process(delta: float) -> void:
	_bump(delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, CORPSE.friction * delta)
	move_and_slide()
	_check_fall()
	if is_on_floor() and not _lying and velocity.y >= 0.0:
		_lie()
	if is_on_floor() and not _pooled and absf(velocity.x) < 20.0:
		_pooled = true
		if absf(global_position.x - _pool_x) > 12.0:
			_pool_x = global_position.x
			Blood.pool_under(self)
	if _fountain_left > 0.0:
		_pump_fountain(delta)


## The Bro walking through a body: a small hop and a push the first moment, then it is
## dragged along while he keeps walking.
func _bump(delta: float) -> void:
	var p := player()
	var touching := false
	if p != null:
		var box: RectangleShape2D = $Collision.shape
		var dx: float = p.global_position.x - global_position.x
		touching = absf(dx) < box.size.x / 2.0 + 6.0 and absf(p.global_position.y - global_position.y) < 14.0 \
				and absf(p.velocity.x) > 20.0
		if touching:
			var mass: float = stats.get("mass", 1.0)
			if not _bumped:
				velocity.x = p.velocity.x * CORPSE.bump_speed / mass
				velocity.y = CORPSE.bump_hop / mass
				_pooled = false  # stays in the lying pose; leaves another pool where it stops
			elif is_on_floor():
				velocity.x = move_toward(velocity.x, p.velocity.x * CORPSE.drag / mass, 600.0 * delta)
	_bumped = touching


## Body leaves the ground: flailing pose (a headless body keeps its headless pose).
func _fly() -> void:
	_lying = false
	_pooled = false  # leaves another pool where it lands
	var anim := _dead_anim if _headless else "hurt"
	sprite.play(anim)
	sprite.rotation = 0.0
	sprite.position = Vector2(0, Block.SIZE / 2.0 - sprite.sprite_frames.get_frame_texture(anim, 0).get_height() / 2.0)


## Body on the ground: its lying pose (drawn in the sprite, picked at death) and a low,
## wide collision box that the Bro's bullets can still hit.
func _lie() -> void:
	_lying = true
	sprite.play(_dead_anim)
	sprite.rotation = 0.0
	sprite.position = Vector2(0, Block.SIZE / 2.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[1] * 0.8, CORPSE.lying_height)
	$Collision.position.y = Block.SIZE / 2.0 - CORPSE.lying_height / 2.0


func player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	return null if p == null or p.dead else p


## True if the Bro is visible looking in `dir`: in range, about eye height, nothing solid between.
func sees_player(dir: int) -> bool:
	var p := player()
	if p == null:
		return false
	var eye_pos := global_position + Vector2(eye.x * dir, eye.y)
	var to_player: Vector2 = p.global_position - eye_pos
	if signf(to_player.x) != dir or absf(to_player.x) > stats.vision_range or absf(to_player.y) > stats.vision_height:
		return false
	return ray(eye_pos, p.global_position).is_empty()


## Walk in `facing`; at a wall or ledge stop for turn_pause, then walk back.
func patrol_step(delta: float, speed: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		velocity.x = 0.0
		return
	if is_on_floor() and (is_on_wall() or not ground_ahead()):
		facing = -facing
		_pause = stats.turn_pause
		velocity.x = 0.0
		return
	velocity.x = facing * speed


func ground_ahead() -> bool:
	var foot := global_position + Vector2(facing * (stats.hitbox[0] / 2.0 + 2.0), 4)
	return not ray(foot, foot + Vector2(0, 12)).is_empty()


func ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)


func show_alert(on: bool) -> void:
	_bubble.visible = on


## Called by bullets. `direction` = which way the bullet was flying. A body is knocked back.
## `at` = where the bullet struck; `behead` = the bullet's power to blow the head off
## ("headshot": a hit on the head kills and beheads, "always": any killing hit beheads).
func hit(damage: int, direction := 0, at := Vector2.INF, behead := "none") -> void:
	if dead:
		_shot_body(direction)
		return
	var off_head := can_behead() and (behead == "always" or (behead == "headshot" and _on_head(at)))
	if off_head and behead == "headshot":
		damage = maxi(damage, hp)  # a shot to the head kills
	hp -= damage
	health_changed.emit(maxi(hp, 0), stats.hp)
	Blood.spray(get_parent(), global_position + Vector2(0, 6 - stats.hitbox[1] / 2.0), direction if direction != 0 else -facing)
	if direction == facing:  # shot from behind: turn to face the shooter
		facing = -facing
	sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.08)
	if hp <= 0:
		die(direction)
		if off_head:
			_behead(direction if direction != 0 else -facing)
	else:
		_on_hurt(direction)


## Called by explosions (explosion.gd). Living enemies take blast damage; bodies get tossed.
func on_blast(center: Vector2, power: Dictionary) -> void:
	var dir := 1 if global_position.x >= center.x else -1
	var was_alive := not dead
	if not dead:
		hit(power.damage, dir)
	if dead:
		if was_alive and can_behead():  # killed by the blast: his head is blown off
			_behead(dir)
		if tears_apart and not is_in_group("bosses"):  # and the rest of him is torn to pieces
			BodyPiece.tear(self, dir, center)
			return
		toss(dir, GameData.EXPLOSION.fling_speed)


func toss(dir: int, speed: float) -> void:
	velocity = Vector2(dir * speed * 0.5, -speed)
	_fly()
	create_tween().tween_property(sprite, "rotation", TAU * dir, 0.6)


## The Bro's knife (player.gd). Every enemy but a boss dies from one hit; a boss takes
## `boss_damage`. The knifed enemy (or body) is thrown back hard, and a kill sprays `blood`
## extra drops. Returns true if this hit killed him.
func stab(direction: int, boss_damage: int, knockback: float, hop: float, blood: int, hits_needed := 1, stun := 0.0) -> bool:
	var mass: float = stats.get("mass", 1.0)
	var throw := Vector2(direction * knockback / mass, hop / mass)
	var chest := global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] * 0.6)
	if dead:  # stabbing a body bursts it at once, like the last bullet would
		Blood.spray(get_parent(), chest, direction)
		if not dead:
			die(0)
		_burst_body(direction)
		return false
	if hits_needed > 1 and not is_in_group("bosses"):
		_stab_hits += 1
		if _stab_hits < hits_needed:  # not dead yet: thrown back and stunned, standing there helpless
			Blood.spray(get_parent(), chest, direction)
			velocity = throw
			_shoved = stun
			show_alert(false)
			return false
	hit(boss_damage if is_in_group("bosses") else hp, direction)
	if dead:
		Blood.knife_kill(get_parent(), chest, direction, blood)
		velocity = throw  # harder than the bullet-kill push _on_death gave
		return true
	velocity.x = throw.x * 0.5  # a boss survives: shoved back a little
	_shoved = 0.25
	return false


func _shot_body(direction: int) -> void:
	var dir := direction if direction != 0 else 1
	var mass: float = stats.get("mass", 1.0)
	Blood.spray(get_parent(), global_position + Vector2(0, 2), dir)
	velocity = Vector2(dir * CORPSE.shot_knockback / mass, CORPSE.shot_hop / mass)
	_fly()
	_shots_taken += 1
	if _shots_taken >= CORPSE.burst_hits:
		_burst_body(dir)


## Shot to pieces: bursts into gore (no blast), leaving only blood.
func _burst_body(dir := 0) -> void:
	if tears_apart and not is_in_group("bosses"):  # torn into pieces, like a blast would
		BodyPiece.tear(self, dir if dir != 0 else facing, global_position - Vector2(dir * 6.0, 0.0))
		return
	Blood.gore(get_parent(), global_position)
	Sfx.play(self, "blood_splat", 0.0)
	Blood.pool_under(self)
	queue_free()


## Sprites drawn with headless poses (headless_a / headless_b, head_a / head_b) can lose their head.
func can_behead() -> bool:
	return sprite.sprite_frames.has_animation("headless_a")


## True if the point `at` is on his head (the top head_height px of his standing box).
func _on_head(at: Vector2) -> bool:
	if at == Vector2.INF or dead:
		return false
	var top: float = global_position.y + Block.SIZE / 2.0 - stats.hitbox[1]
	return at.y < top + stats.get("head_height", 0.0)


## Head blown off: the head flies away on its own (Head), the body switches to the matching
## headless pose and blood pumps out of the neck for a few seconds.
func _behead(dir: int) -> void:
	if _headless:
		return
	_headless = true
	var pose := "a" if _dead_anim == "dead_a" else "b"
	_dead_anim = "headless_" + pose
	var head_h: float = stats.get("head_height", 8.0)
	var neck := position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] + head_h / 2.0)
	Head.throw(get_parent(), neck, "head_" + pose, dir, sprite.flip_h)
	Blood.spray(get_parent(), neck, dir)
	if _lying:
		_lie()
	else:
		_fly()
	_fountain_side = -1 if sprite.flip_h else 1
	_fountain = CPUParticles2D.new()
	_fountain.position = Vector2(CORPSE.neck[0] * _fountain_side, CORPSE.neck[1])
	_fountain.amount = 90
	_fountain.lifetime = 0.9
	_fountain.local_coords = false
	_fountain.direction = Vector2(_fountain_side, -0.8)
	_fountain.spread = 18.0
	_fountain.gravity = Vector2(0, 420)
	_fountain.scale_amount_min = 1.0
	_fountain.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([Blood.COLORS[0], Blood.COLORS[1], Color(Blood.COLORS[2], 0.0)])
	_fountain.color_ramp = ramp
	_fountain.z_index = -2  # behind the blocks (the body is z 1): the ground hides drops falling past it
	sprite.add_child(_fountain)  # child of the sprite: it turns with the body while it flies
	_fountain.emitting = true
	_fountain_left = CORPSE.fountain_time


## The neck pumps in heartbeats, weaker and weaker; real drops fall and stain the ground.
func _pump_fountain(delta: float) -> void:
	_fountain_left -= delta
	var strength: float = clampf(_fountain_left / CORPSE.fountain_time, 0.0, 1.0)
	var beat := 0.55 + 0.45 * absf(sin(_fountain_left * CORPSE.fountain_beat * PI))
	_fountain.initial_velocity_min = CORPSE.fountain_speed * 0.4 * strength * beat
	_fountain.initial_velocity_max = CORPSE.fountain_speed * strength * beat
	_fountain.emitting = _fountain_left > 0.0
	_fountain_drip -= delta
	if _fountain_drip <= 0.0 and _fountain_left > 0.0:
		_fountain_drip = 0.1
		var dir := Vector2(_fountain_side, -0.8).rotated(sprite.rotation)
		BloodDrops.emit(get_parent(), _fountain.global_position, dir, CORPSE.fountain_drops, 18.0, CORPSE.fountain_speed * strength * beat)


func die(direction: int) -> void:
	dead = true
	if sprite.sprite_frames.has_animation("dead_b"):
		_dead_anim = "dead_a" if randi() % 2 == 0 else "dead_b"  # 50 / 50
	collision_layer = CORPSE_LAYER
	z_index = 1
	show_alert(false)
	Run.add_kill()
	Blood.burst(get_parent(), global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] / 2.0))
	Sfx.play(self, "blood_splat", -6.0)
	_on_death(direction)


func _on_hurt(_direction: int) -> void:
	pass


## Default death: knocked back flailing, then lies flat where it lands; the body stays.
func _on_death(direction: int) -> void:
	Sfx.play(self, death_sound, -4.0)
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 80.0, -140.0)
	_fly()
