extends CharacterBody2D
## The Bro: run, jump, crouch, hold to shoot, knife up close (a knife kill gives a spare magazine),
## grenades (Run.grenades, design/entities/grenade.yaml). Enemy bullets take one heart, explosions several (and
## knock him back). At 0 he dies and emits `died` — main.gd decides what happens next (run
## lives, design/run.yaml). Numbers: design/entities/bro.yaml (GameData.BRO).

signal hp_changed(hp: int, max_hp: int)
signal died
signal ammo_changed(in_mag: int, spare_mags: int, reloading: bool)
signal grenades_changed(left: int)

const BULLET_MASK := 1 | 4 | 8  # world (blocks, barrels) + enemies + bodies
const KNIFE_MASK := 4 | 8  # enemies + bodies
const KNIFE_HIT_FRAME := 3  # first arm-up frame of the "knife" animation

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var flash: MuzzleFlash = $Flash
@onready var camera: Camera2D = $Camera

var STATS: Dictionary = Run.bro_stats()  # the chosen character's numbers
var _bullet_stats: Dictionary = GameData.BULLET.duplicate()
var hp: int = STATS.max_hp
var dead := false
var frozen := false  # level clear: no control, cannot be hurt
var facing := 1
var crouching := false
var _dir := 0.0  # move input this frame
var sprite_y := 0.0  # the frame is centered on the node; this offset puts the feet on the tile bottom (+half a block)
var fire_cooldown := 0.0
var shooting := 0.0
var _invulnerable := 0.0
var _stagger := 0.0  # knocked back by a blast: input ignored
var _shake := 0.0
var ammo: int = STATS.magazine_size  # rounds left in the loaded magazine
var spare_mags: int = STATS.magazines - 1  # full magazines in the belt (one is loaded)
var _reload := 0.0  # > 0 while swapping magazines
var _recoil := 0.0  # horizontal kick from the last shots; decays on its own
var _burst_shots := 0  # shots in a row while running; past STATS.spread_after the aim gets sloppy
var _burst_gap := 0.0  # time since the last shot (resets the burst)
var _shout_timer := 0.0
var _clinging := false  # knife stuck in the side of a block: hangs, then slides down
var _cling_time := 0.0
var _cling_side := 0  # which side the wall is on (+1 right, -1 left)
var _cling_cooldown := 0.0  # no re-grab right after letting go
var _flipping := 0.0  # > 0 while somersaulting after kicking off a wall (the flip animation)
var _flash_2: MuzzleFlash  # the second gun's flash (two-gun Bros like Blala)
var _gun := 0  # two guns: which one fires next (0 main, 1 second), they take turns
var _knifing := false  # the knife animation is playing: no shooting, slow shuffle only


func _ready() -> void:
	add_to_group("player")
	if not Run.loadout.is_empty():  # carried over from the last level (hub restocks refill it)
		hp = Run.loadout.get("hp", hp)
		ammo = Run.loadout.get("ammo", ammo)
		spare_mags = Run.loadout.get("spare_mags", spare_mags)
	hp_changed.emit.call_deferred(hp, STATS.max_hp)
	_bullet_stats.lifetime = STATS.bullet_lifetime
	sprite.sprite_frames = load("res://assets/sprites/%s_frames.tres" % Run.character)  # each Bro has his own sprite
	var tint: Array = STATS.tint
	sprite.self_modulate = Color(tint[0], tint[1], tint[2])
	z_index = 2
	_flash_2 = MuzzleFlash.new()
	add_child(_flash_2)
	sprite_y = Block.SIZE / 2.0 - sprite.sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0
	sprite.position.y = sprite_y
	_set_stance(false)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	ammo_changed.emit.call_deferred(ammo, spare_mags, false)
	grenades_changed.emit.call_deferred(Run.grenades)


func _process(delta: float) -> void:
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	_shake = move_toward(_shake, 0.0, 24.0 * delta)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta
	if dead or frozen:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		if frozen and sprite.animation != "idle":
			sprite.play("idle")
		return

	var dir := Input.get_axis("move_left", "move_right")
	_dir = dir
	_cling_cooldown -= delta
	if _clinging:
		_cling_process(delta, dir)
		return
	if Input.is_action_just_pressed("knife"):
		_start_knife()
	if Input.is_action_just_pressed("grenade") and not _knifing:
		_throw_grenade()
	if not _knifing:
		_update_stance()
	if _stagger > 0.0:
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	elif _knifing:
		velocity.x = dir * STATS.knife_speed if signf(dir) == facing else 0.0  # shuffles forward, never turns mid-slash
	else:
		velocity.x = dir * (STATS.speed_crouch if crouching else STATS.speed) + _recoil
		if dir != 0:
			facing = 1 if dir > 0 else -1
			sprite.flip_h = facing < 0

	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouching:
		velocity.y = STATS.jump_velocity
		Sfx.play(self, "jump", -4.0)

	var was_on_floor := is_on_floor()
	move_and_slide()
	if not was_on_floor and is_on_floor():
		Sfx.play(self, "land", -6.0)
	if not is_on_floor() and _cling_cooldown <= 0.0 and not _knifing and _stagger <= 0.0 and dir != 0.0:
		var side := _wall_block_side()
		if side != 0 and side == int(signf(dir)):
			if not _knife_in_air(side):  # a wall his upper body clears is not one to hang on
				_start_cling(side)

	_flipping -= delta
	fire_cooldown -= delta
	shooting -= delta
	_recoil = move_toward(_recoil, 0.0, STATS.recoil_decay * delta)
	_burst_gap += delta
	_shout_timer -= delta
	if _burst_gap > STATS.burst_reset:
		_burst_shots = 0
	_update_reload(delta)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and _reload <= 0.0 and not _knifing:
		if ammo > 0:
			_shoot()
		else:
			fire_cooldown = 0.4
			Sfx.play(self, "dry_fire", -6.0)
			_start_reload()

	_invulnerable -= delta
	sprite.visible = _invulnerable <= 0.0 or fmod(_invulnerable, 0.12) < 0.06
	_update_animation(dir)


## Called by enemy bullets. `direction` = which way the bullet was flying.
func hit(damage: int, direction := 0) -> void:
	if dead or frozen or _invulnerable > 0.0:
		return
	hp = maxi(hp - damage, 0)
	hp_changed.emit(hp, STATS.max_hp)
	if hp == 0:
		_die(direction)
		return
	_invulnerable = STATS.invulnerable_time
	Sfx.play(self, "player_hurt")


## Called by explosions (explosion.gd): thrown away from the center, loses player_damage hearts.
func on_blast(center: Vector2, power: Dictionary) -> void:
	if dead or frozen:
		return
	var dir := 1 if global_position.x >= center.x else -1
	_release_cling()
	_flipping = 0.0
	var fling: float = GameData.EXPLOSION.fling_speed
	velocity = Vector2(dir * fling * 0.6, -fling * 0.7)
	_stagger = 0.3
	hit(power.player_damage, dir)


## Instant death (fell out of the level).
func kill() -> void:
	if dead:
		return
	hp = 0
	hp_changed.emit(hp, STATS.max_hp)
	_die(0)


## Hub stations (main.gd): full magazine, full belt / full hearts.
func restock() -> void:
	_reload = 0.0
	ammo = STATS.magazine_size
	spare_mags = STATS.max_spare_mags
	ammo_changed.emit(ammo, spare_mags, false)


func heal() -> void:
	hp = STATS.max_hp
	hp_changed.emit(hp, STATS.max_hp)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Level clear: stop moving and shooting, can't be hurt.
func freeze() -> void:
	frozen = true
	_knifing = false
	sprite.visible = true


func _die(direction: int) -> void:
	dead = true
	_knifing = false
	sprite.visible = true
	collision_layer = 0
	Sfx.play(self, "player_death")
	sprite.play("hurt")
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 90.0, -160.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "rotation", PI / 2 * push, 0.35)
	tween.tween_property(sprite, "position:y", sprite_y + 3.0, 0.35)
	died.emit()


## `aim` = which way the bullet flies (0 = the way he faces; clinging to a wall he fires away from it).
func _shoot(aim := 0) -> void:
	var aim_dir := aim if aim != 0 else facing
	_flipping = 0.0  # firing straightens him out of the flip
	fire_cooldown = STATS.fire_interval
	shooting = 0.15
	ammo -= 1
	ammo_changed.emit(ammo, spare_mags, false)
	_update_animation(_dir)  # the pose the bullet leaves from (run, crouch, shoot...)
	# Held fire while running: after a few shots the aim goes sloppy and the Bro starts yelling.
	_burst_gap = 0.0
	if _dir != 0.0 and is_on_floor():
		_burst_shots += 1
	elif _dir == 0.0:
		_burst_shots = 0
	var angle := randf_range(-STATS.base_spread, STATS.base_spread)  # the gun's own sloppiness
	if _burst_shots > STATS.spread_after:
		angle += randf_range(-STATS.spread_degrees, STATS.spread_degrees)
		if _shout_timer <= 0.0:
			_shout_timer = STATS.shout_interval
			Sfx.play(self, "bro_shout", -2.0, 0.05)
			shake(1.5)
	var two_guns := not MuzzleFlash.second_tips(Run.character).is_empty()
	if two_guns:
		_gun = 1 - _gun  # the guns take turns
	var muzzle := MuzzleFlash.gun_tip(sprite, Run.character, aim_dir, _gun == 1)
	Bullet.spawn(get_parent(), position + muzzle, aim_dir, _bullet_stats, "bro_shot", BULLET_MASK, angle)
	(_flash_2 if two_guns and _gun == 1 else flash).fire(muzzle, aim_dir)
	Sfx.play(self, "shoot", -8.0)
	if not _clinging:
		_recoil = clampf(_recoil - aim_dir * STATS.recoil, -STATS.recoil_max, STATS.recoil_max)
	if ammo == 0:
		_start_reload()


func _start_reload() -> void:
	if _reload > 0.0 or spare_mags <= 0 or ammo >= STATS.magazine_size:
		return
	_reload = STATS.reload_time
	Sfx.play(self, "reload", -4.0)
	ammo_changed.emit(ammo, spare_mags, true)


func _update_reload(delta: float) -> void:
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if _reload <= 0.0:
		return
	_reload -= delta
	if _reload <= 0.0:
		spare_mags -= 1
		ammo = STATS.magazine_size
		ammo_changed.emit(ammo, spare_mags, false)


## Grenade: thrown in an arc in front of him (a low roll while crouched), half his running speed added.
func _throw_grenade() -> void:
	if Run.grenades <= 0 or _stagger > 0.0:
		return
	_use_grenade()
	var speed: Array = GameData.GRENADE.crouch_throw_speed if crouching else GameData.GRENADE.throw_speed
	var from := position + Vector2(facing * 4.0, Block.SIZE / 2.0 - (STATS.hitbox_crouch[1] if crouching else STATS.hitbox[1]) + 8.0)
	Grenade.throw(get_parent(), from, Vector2(facing * speed[0] + velocity.x * 0.5, -speed[1]))


func _use_grenade() -> void:
	Run.grenades -= 1
	grenades_changed.emit(Run.grenades)
	Sfx.play(self, "grenade_throw", -4.0)


## Knife: stands up if crouched (and there is room), plays the knife animation; the hit
## itself happens on its first arm-up frame (_on_frame_changed -> _knife_strike).
func _start_knife() -> void:
	if _knifing or _stagger > 0.0:
		return
	if crouching:
		if _ceiling_above():
			return
		_set_stance(false)
	_knifing = true
	_flipping = 0.0
	sprite.play("knife")
	Sfx.play(self, "knife_swing", -4.0, 0.08)


## The blade lands: the nearest enemy (or else body) within knife_range in front gets it;
## loose heads there burst.
func _knife_strike() -> void:
	var probe := RectangleShape2D.new()
	probe.size = Vector2(STATS.knife_range, STATS.hitbox[1])
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(facing * STATS.knife_range / 2.0, Block.SIZE / 2.0 - STATS.hitbox[1] / 2.0))
	query.collision_mask = KNIFE_MASK
	var target: Enemy = null
	for hit_info in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var e = hit_info.collider
		if not e is Enemy:
			continue
		var closer: bool = target == null or absf(e.global_position.x - global_position.x) < absf(target.global_position.x - global_position.x)
		if target == null or (target.dead and not e.dead) or (target.dead == e.dead and closer):
			target = e
	var heads := 0
	for h in get_tree().get_nodes_in_group("heads"):  # loose heads are not physical: checked by position
		var d: Vector2 = h.global_position - global_position
		if d.x * facing >= -4.0 and absf(d.x) <= STATS.knife_range and d.y > Block.SIZE / 2.0 - STATS.hitbox[1] - 4.0 and d.y < Block.SIZE / 2.0 + 4.0:
			h.burst()
			heads += 1
	if target == null:
		if _knife_block():
			return
		if heads > 0:
			Sfx.play(self, "knife_stab", -2.0, 0.08)
		return
	Sfx.play(self, "knife_stab", -2.0, 0.08)
	shake(2.0)
	if target.stab(facing, STATS.knife_boss_damage, STATS.knife_knockback, STATS.knife_hop, STATS.knife_blood, STATS.knife_hits, STATS.knife_stun):
		_gain_mag()


## No enemy in reach: the blade bites into the nearest block in front and breaks it in one
## stab (every character; the numbers come from the knife range only).
func _knife_block() -> bool:
	var best: Block = null
	for dy in [-8.0, 6.0]:  # chest and belt height
		var from := global_position + Vector2(0, dy)
		var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(facing * (STATS.knife_range + 6.0), 0), 1)
		var result := get_world_2d().direct_space_state.intersect_ray(query)
		if not result.is_empty() and result.collider is Block:
			if best == null or absf(result.collider.global_position.x - global_position.x) < absf(best.global_position.x - global_position.x):
				best = result.collider
	if best == null:
		return false
	Sfx.play(self, "knife_stab", -2.0, 0.08)
	shake(3.0)
	best.destroy()
	return true


## A knife kill: one more spare magazine (up to max_spare_mags) and the "+ magazine" pop-up.
func _gain_mag() -> void:
	if spare_mags >= STATS.max_spare_mags:
		return
	spare_mags += 1
	ammo_changed.emit(ammo, spare_mags, _reload > 0.0)
	MagPopup.show_over(self, sprite_y - GameData.SPRITE_SIZES[Run.character].y / 2.0)
	if ammo == 0:
		_start_reload()


## The side (+1 right, -1 left) a block is touching the Bro on after the last move, else 0.
func _wall_block_side() -> int:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is Block and absf(c.get_normal().x) > 0.9:
			return -int(signf(c.get_normal().x))
	return 0


## The wall on `side` is too short for the knife: no block where it would go in, a bit below the
## top of his head (his upper body is above it). Then he does not cling.
func _knife_in_air(side: int) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = Vector2(global_position.x + side * (STATS.hitbox[0] / 2.0 + 2.0), global_position.y + Block.SIZE / 2.0 - STATS.hitbox[1] + 2.0)
	q.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


## Jumping into the side of a block: the knife goes into the dirt and he hangs there (the knife
## animation held on its stab frame).
func _start_cling(side: int) -> void:
	_clinging = true
	_cling_time = 0.0
	_cling_side = side
	facing = side
	sprite.flip_h = facing < 0
	velocity = Vector2.ZERO
	sprite.play("cling")
	Sfx.play(self, "knife_stab", -2.0, 0.08)
	shake(1.5)


func _release_cling() -> void:
	if not _clinging:
		return
	_clinging = false
	_cling_cooldown = STATS.cling_cooldown
	sprite.play("jump")


## Hangs for cling_hold, then slides down, faster and faster. Jump kicks off the wall, pressing
## away or Crouch lets go; landing or losing the wall ends it too.
func _cling_process(delta: float, dir: float) -> void:
	_cling_time += delta
	if Input.is_action_just_pressed("grenade") and Run.grenades > 0:
		_use_grenade()
		Grenade.blow(get_parent(), position + Vector2(_cling_side * 6.0, -6.0))  # no room to throw: it goes off in his hand
		return
	fire_cooldown -= delta  # he can still shoot - backwards, away from the wall
	shooting -= delta
	_burst_gap += delta
	_update_reload(delta)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and _reload <= 0.0 and ammo > 0:
		_shoot(-_cling_side)
	_invulnerable -= delta
	sprite.visible = _invulnerable <= 0.0 or fmod(_invulnerable, 0.12) < 0.06
	if Input.is_action_just_pressed("jump"):
		_kick_off_wall()
		return
	if Input.is_action_pressed("crouch") or (dir != 0.0 and int(signf(dir)) == -_cling_side):
		_release_cling()
		return
	var slide := 0.0
	if _cling_time > STATS.cling_hold:
		slide = minf(STATS.cling_slide_start + STATS.cling_slide_accel * (_cling_time - STATS.cling_hold), STATS.cling_slide_max)
	velocity = Vector2(_cling_side * 30.0, slide)  # pressed into the wall so it stays touching
	move_and_slide()
	if is_on_floor():
		_release_cling()
		Sfx.play(self, "land", -6.0)
	elif _wall_block_side() != _cling_side:
		_release_cling()


## Jump while hanging: kicks off the wall, turns away from it and somersaults (flip).
func _kick_off_wall() -> void:
	var side := _cling_side
	_release_cling()
	velocity = Vector2(-side * STATS.cling_kick[0], STATS.cling_kick[1])
	facing = -side
	sprite.flip_h = facing < 0
	sprite.play("flip")
	_flipping = STATS.flip_time
	Sfx.play(self, "jump", -4.0)


func _update_animation(dir: float) -> void:
	if _knifing or _clinging:
		return
	if _flipping > 0.0 and not is_on_floor():
		return  # the somersault plays out
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif crouching:
		anim = "crouch_walk" if dir != 0 else ("crouch_shoot" if shooting > 0.0 else "crouch")
	elif dir != 0:
		anim = "run_shoot" if shooting > 0.0 else "run"
	elif shooting > 0.0:
		anim = "shoot"
	if sprite.animation != anim:
		sprite.play(anim)


## Hold Crouch on the ground to shrink to one block. Letting go only stands up when there is
## room above; otherwise he stays crouched under the low ceiling.
func _update_stance() -> void:
	var want := Input.is_action_pressed("crouch") and is_on_floor()
	if want == crouching:
		return
	if want or not _ceiling_above():
		_set_stance(want)


func _set_stance(crouch: bool) -> void:
	crouching = crouch
	var size: Array = STATS.hitbox_crouch if crouch else STATS.hitbox
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(size[0], size[1])
	$Collision.position.y = Block.SIZE / 2.0 - size[1] / 2.0  # feet always on the bottom of the start tile


## Is there a block where the standing body would be? (Probed slightly smaller than the
## standing box so the floor under his feet does not count.)
func _ceiling_above() -> bool:
	var probe := RectangleShape2D.new()
	probe.size = Vector2(STATS.hitbox[0] - 2, STATS.hitbox[1] - 2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(0, Block.SIZE / 2.0 - STATS.hitbox[1] / 2.0 - 1.0))
	query.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_frame_changed() -> void:
	if sprite.animation == "run" and sprite.frame % 2 == 0:
		Sfx.play(self, "footstep", -14.0, 0.15)
	elif sprite.animation == "knife" and sprite.frame == KNIFE_HIT_FRAME and not _clinging:
		_knife_strike()


func _on_animation_finished() -> void:
	if sprite.animation == "knife":
		_knifing = false
		_update_animation(_dir)
