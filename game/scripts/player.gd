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
const MANTLE_TIME := 0.22  # climbing onto a one-block step under a low ceiling

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
var _pump_due := false  # a shotgun Bro cycles the pump after each shot (if his sprite has a "pump" animation)
var _pumping := false
var _windup := 0.0  # seconds the barrels have been spinning up (minigun Bro); fires once it reaches windup_time
var _winding := false  # spinning up right now (no bullets yet)
var _c4_hold := -1.0  # seconds the grenade button has been held (C4 Bro; -1 = not held)
var _c4_fired := false  # the hold already set the charges off
var _invulnerable := 0.0
var _stagger := 0.0  # knocked back by a blast: input ignored
var _shake := 0.0
var ammo: int = STATS.shells_start if STATS.shells_start > 0 else STATS.magazine_size  # rounds left in the loaded magazine (or shells, for a shell-count Bro)
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
var _mantle := 0.0  # seconds left of climbing onto a step (he crouches and rises, then crawls on)
var _mantle_from := Vector2.ZERO
var _mantle_to := Vector2.ZERO
var _hand_cell := Vector2i.ZERO  # the wall block his knife is in while he clings; when it breaks he lets go and falls
var _hand_block: Block
var _roll_box := false  # the roll shrinks the hitbox to one block so he rolls through a one-block gap
var _rolling := false  # the landing roll is playing (after a long fall, moving, not shooting)
var _air_peak := INF  # highest point (smallest y) of the current time in the air
var _flipping := 0.0  # > 0 while somersaulting after kicking off a wall (the flip animation)
var _revolver_flash: MuzzleFlash  # the big flash of the revolver shot (Sharif)
var _flash_2: MuzzleFlash  # the second gun's flash (two-gun Bros like Blala)
var _gun := 0  # two guns: which one fires next (0 main, 1 second), they take turns
var _crouch_knife := -1.0  # seconds into a knife stab thrown from a crouch (-1 = none); timed, so it needs no animation
var _revolver := -1.0  # seconds into the revolver action (-1 = not drawn): rooted to the spot, one shot straight ahead
var _revolver_fired := false
var _kick_due := false  # raygun: play run_recoil once for the shot just fired
var _kicking := false
var _crush := 0.0  # seconds something solid has been inside him
var _charge := 0.0  # seconds the revolver button was held; stronger shot the longer (design/entities/revolver.yaml)
var _ring: ChargeRing
var _dust := 0.0  # time until the next puff of dust under his running feet
var _blasted := false  # the hit being handled is an explosion: a death from it tears him apart
var _corpse := false  # lying on the ground in the dead pose
var _climb_side := 0  # hopping up a wall: which side it is on; he re-grabs it by himself at the top of the hop
var _climb_time := 0.0
var _knifing := false  # the knife animation is playing: no shooting, slow shuffle only
var _default_flash: SpriteFrames
var _tap_time := {"move_left": -9.0, "move_right": -9.0}  # when each direction was last pressed (double tap = run)
var _sprint := 0  # +1 / -1 while running after a double tap, 0 otherwise
var _sprint_time := 0.0  # seconds since the run began: the speed builds up from run_start to run_multiplier
var _heat := 0  # shots fired in a row (Hamid's minigun overheats after STATS.overheat_shots)
var _overheat := 0.0  # seconds the gun stays jammed


func _ready() -> void:
	add_to_group("player")
	if not Run.loadout.is_empty():  # carried over from the last level (hub restocks refill it)
		hp = Run.loadout.get("hp", hp)
		ammo = Run.loadout.get("ammo", ammo)
		spare_mags = Run.loadout.get("spare_mags", spare_mags)
	hp_changed.emit.call_deferred(hp, STATS.max_hp)
	_default_flash = flash.sprite_frames
	z_index = 2
	_flash_2 = MuzzleFlash.new()
	add_child(_flash_2)
	_apply_look()
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	ammo_changed.emit.call_deferred(ammo, spare_mags, false)
	grenades_changed.emit.call_deferred(Run.grenades)


## Everything that depends on which Bro he is: bullet range, flash, sprite sheet, tint, feet offset.
func _apply_look() -> void:
	_bullet_stats.lifetime = STATS.bullet_lifetime
	flash.sprite_frames = load("res://assets/sprites/%s_frames.tres" % STATS.muzzle_flash) if STATS.get("muzzle_flash", "") != "" else _default_flash  # a character with his own flash picture (shotgun)
	sprite.sprite_frames = load("res://assets/sprites/%s_frames.tres" % Run.look())  # each Bro has his own sprite
	var tint: Array = STATS.tint
	sprite.self_modulate = Color(tint[0], tint[1], tint[2])
	if STATS.explosive == "revolver" and _revolver_flash == null:
		_revolver_flash = MuzzleFlash.new()
		add_child(_revolver_flash)
		_revolver_flash.sprite_frames = load("res://assets/sprites/%s_frames.tres" % GameData.REVOLVER.flash)
	sprite_y = Block.SIZE / 2.0 - sprite.sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0
	sprite.position.y = sprite_y
	_set_stance(false)


## A crate gave him another Bro (Run.character already changed): new gun, new look, full hearts and ammo.
func switch_character() -> void:
	STATS = Run.bro_stats()
	hp = STATS.max_hp
	ammo = STATS.shells_start if STATS.shells_start > 0 else STATS.magazine_size
	spare_mags = STATS.magazines - 1
	_reload = 0.0
	_windup = 0.0
	_winding = false
	_revolver = -1.0
	_heat = 0
	_overheat = 0.0
	_apply_look()
	sprite.play("idle")
	hp_changed.emit(hp, STATS.max_hp)
	ammo_changed.emit(ammo, spare_mags, false)
	grenades_changed.emit(Run.grenades)


## A crate upgraded the gun or the legs (Run.upgrades): re-read the numbers, keep the rounds.
func refresh_stats() -> void:
	STATS = Run.bro_stats()
	if _uses_shells():
		ammo = mini(ammo, STATS.shells_max)
	ammo_changed.emit(ammo, spare_mags, false)


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

	if _box_blocked(STATS.hitbox_crouch if crouching else STATS.hitbox, Vector2.ZERO):
		_crush += delta  # something solid (a barrel, a block) is on top of him: after a moment he is crushed
		if _crush >= 0.2:
			_crush = 0.0
			_crushed()
			return
	else:
		_crush = 0.0
	var dir := Input.get_axis("move_left", "move_right")
	_dir = dir
	_double_tap(dir)
	_sprint_time = _sprint_time + delta if _sprint != 0 else 0.0
	_cling_cooldown -= delta
	if _mantle > 0.0:
		_mantle_step(delta)
		return
	if _clinging:
		_cling_process(delta, dir)
		return
	if Input.is_action_just_pressed("knife") and _revolver < 0.0:
		_start_knife()
	_revolver_step(delta, dir)
	_crouch_knife_step(delta)
	if _explosive_is_c4():
		_c4_input(delta)
	elif Input.is_action_just_pressed("grenade") and not _knifing:
		_throw_grenade()
	if not _knifing:
		_update_stance()
	if _stagger > 0.0:
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	elif _revolver >= 0.0:
		velocity.x = 0.0  # the revolver is out: he does not move
	elif _knifing:
		velocity.x = dir * STATS.knife_speed if signf(dir) == facing else 0.0  # shuffles forward, never turns mid-slash
	else:
		var walk: float = STATS.speed_crouch if crouching else STATS.speed
		if _reload > 0.0:
			walk *= STATS.reload_move_mult  # swapping the belt slows him down
		if _sprint != 0 and not crouching:
			var run: Dictionary = GameData.RUN
			walk *= lerpf(run.run_start, run.run_multiplier, clampf(_sprint_time / run.run_ramp_time, 0.0, 1.0))  # a running start that builds up
		velocity.x = dir * walk + _recoil
		if _climb_side != 0 and dir == 0.0:
			velocity.x = _climb_side * 30.0  # stays against the wall while hopping up it
		if dir != 0:
			facing = 1 if dir > 0 else -1
			sprite.flip_h = facing < 0

	var stepped := Input.is_action_just_pressed("jump") and is_on_floor() and dir != 0.0 and not _knifing and _step_up(int(signf(dir)))
	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouching and not stepped:
		velocity.y = STATS.jump_velocity
		Sfx.play(self, "jump", -4.0)
		DustPuff.burst(get_parent(), _feet(), 14, 55.0, 1.5, 0.8)  # kick-off cloud

	var was_on_floor := is_on_floor()
	move_and_slide()
	if not is_on_floor():
		_air_peak = minf(_air_peak, position.y)
	if not was_on_floor and is_on_floor():
		var drop := position.y - _air_peak
		_air_peak = INF
		if drop > Block.SIZE * 2.5 and dir != 0.0 and not crouching and shooting <= 0.0 and not Input.is_action_pressed("shoot") and not _knifing and sprite.sprite_frames.has_animation("roll"):
			_rolling = true
			_set_roll_box(true)
			sprite.play("roll")
		Sfx.play(self, "land", -6.0)
		var heavy := clampf(drop / (Block.SIZE * 6.0), 0.0, 1.0)  # a longer fall kicks up more
		DustPuff.burst(get_parent(), _feet(), 18 + int(heavy * 22.0), 70.0 + heavy * 60.0, 1.7 + heavy * 0.6, 1.0, 0.8)
	_dust -= delta
	if is_on_floor() and absf(velocity.x) > 40.0 and _dust <= 0.0 and not _knifing:
		var rolling := _rolling and sprite.animation == "roll"
		var sprinting := _sprint != 0 and not crouching and not rolling
		_dust = 0.03 if rolling else (0.05 if sprinting else (0.14 if not crouching else 0.25))
		var behind := -int(signf(velocity.x))
		if rolling:  # the roll drags a thick trail of dust
			DustPuff.emit(get_parent(), _feet() - Vector2(signf(velocity.x) * 4.0, 0), behind, 7, 70.0)
			DustPuff.burst(get_parent(), _feet(), 4, 35.0, 1.5, 1.3, 0.6)
		elif sprinting:  # a running start throws up a thick trail
			DustPuff.emit(get_parent(), _feet() - Vector2(signf(velocity.x) * 4.0, 0), behind, 7, 45.0)
		else:
			DustPuff.emit(get_parent(), _feet() - Vector2(signf(velocity.x) * 4.0, 0), behind)
	if _climb_side != 0:
		_climb_time -= delta
		if is_on_floor() or _climb_time <= 0.0:
			_climb_side = 0
	var auto_grab := _climb_side != 0 and velocity.y >= -20.0  # top of the hop: knife back into the wall
	if not is_on_floor() and _cling_cooldown <= 0.0 and not _knifing and _stagger <= 0.0 and (dir != 0.0 or auto_grab):
		var side := _wall_block_side()
		if side != 0 and (auto_grab and side == _climb_side or (dir != 0.0 and side == int(signf(dir)))):
			if not _squeeze_in(side) and not _knife_in_air(side) and is_nan(_squeeze_floor(side)):  # a wall his upper body clears, or a one-block gap he can crouch into, is not one to hang on
				_start_cling(side)
	_flipping -= delta
	fire_cooldown -= delta
	shooting -= delta
	_recoil = move_toward(_recoil, 0.0, STATS.recoil_decay * delta)
	_burst_gap += delta
	_shout_timer -= delta
	_overheat -= delta
	if _burst_gap > STATS.get("overheat_reset", 0.5):
		_heat = 0
	if _overheat > 0.0 and fmod(_overheat, 0.12) < delta:  # steam pours off the gun
		DustPuff.burst(get_parent(), position + Vector2(facing * 10.0, 2.0), 3, 18.0, 1.4, 1.6, 0.6)
	if _burst_gap > STATS.burst_reset:
		_burst_shots = 0
	_update_reload(delta)
	var spun_up := _windup_step(delta, Input.is_action_pressed("shoot") and _reload <= 0.0 and not _knifing and ammo > 0 and _overheat <= 0.0)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and _reload <= 0.0 and not _knifing and _revolver < 0.0 and _overheat <= 0.0:
		if ammo > 0:
			if spun_up:
				_shoot()
		else:
			fire_cooldown = 0.4
			Sfx.play(self, "dry_fire", -6.0)
			_start_reload()

	_invulnerable -= delta
	sprite.visible = _invulnerable <= 0.0 or fmod(_invulnerable, 0.12) < 0.06
	_update_animation(dir)


## Two quick taps on the same direction start a run (x run_multiplier) that lasts until he lets go of it.
func _double_tap(dir: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for action in _tap_time:
		if Input.is_action_just_pressed(action):
			var side := -1 if action == "move_left" else 1
			if now - _tap_time[action] <= GameData.RUN.double_tap_time:
				_sprint = side
			_tap_time[action] = now
	if int(signf(dir)) != _sprint:
		_sprint = 0


## Called by enemy bullets. `direction` = which way the bullet was flying.
## The ground under his feet (the bottom of his tile).
func _feet() -> Vector2:
	return position + Vector2(0, Block.SIZE / 2.0 - 1.0)


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
	_blasted = true
	hit(power.player_damage, dir)
	_blasted = false


## Crushed by something falling on him or stuck inside the earth: he bursts into gibs and blood, like a blast.
func _crushed() -> void:
	if dead:
		return
	hp = 0
	hp_changed.emit(hp, STATS.max_hp)
	_blasted = true
	_die(0)
	_blasted = false
	Blood.burst(get_parent(), global_position)


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
	if _uses_shells():
		ammo = STATS.shells_max
		ammo_changed.emit(ammo, 0, false)
		return
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
	var push := direction if direction != 0 else -facing
	if _blasted:  # torn into gibs (the shared gore pieces); nothing of the body is left to see
		sprite.visible = false
		velocity = Vector2.ZERO
		BodyPiece.scatter(get_parent(), global_position, push, global_position - Vector2(push * 6.0, 0.0))
		Sfx.play(self, "blood_splat", 0.0)
		died.emit()
		return
	velocity = Vector2(push * 90.0, -160.0)  # knocked back, already drawn as his corpse
	_lie_down()
	died.emit()


## After a normal death: the sprite becomes the corpse lying on its belly
## (assets/sprites/<id>_dead, the same pose as the soldiers' dead_a).
func _lie_down() -> void:
	_corpse = true
	var path := "res://assets/sprites/%s_dead_frames.tres" % Run.look()
	if not ResourceLoader.exists(path):
		return
	sprite.sprite_frames = load(path)
	sprite.play("dead")
	sprite.rotation = 0.0
	sprite.position.y = Block.SIZE / 2.0 - sprite.sprite_frames.get_frame_texture("dead", 0).get_height() / 2.0
	Blood.pool_under(self)


## `aim` = which way the bullet flies (0 = the way he faces; clinging to a wall he fires away from it).
func _shoot(aim := 0) -> void:
	var aim_dir := aim if aim != 0 else facing
	_flipping = 0.0  # firing straightens him out of the flip
	fire_cooldown = STATS.fire_interval
	shooting = 0.15
	_pumping = false
	_pump_due = sprite.sprite_frames.has_animation("pump")
	ammo -= 1
	ammo_changed.emit(ammo, spare_mags, false)
	if STATS.get("overheat_shots", 0) > 0:
		_heat += 1
		if _heat >= STATS.overheat_shots:  # the barrels glow: no shooting for a moment
			_heat = 0
			_overheat = STATS.overheat_time
			Sfx.play(self, "dry_fire", -2.0)
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
	var two_guns := not MuzzleFlash.second_tips(Run.look()).is_empty()
	if two_guns:
		_gun = 1 - _gun  # the guns take turns
	var muzzle := MuzzleFlash.gun_tip(sprite, Run.look(), aim_dir, _gun == 1)
	var pellets: int = 0 if STATS.weapon == "raygun" else STATS.pellets
	if STATS.weapon == "raygun":  # a beam to where it hits, and a shockwave there
		Raygun.fire(get_parent(), position + muzzle, aim_dir)
		shake(GameData.RAYGUN.shake)
		_kick_due = sprite.sprite_frames.has_animation("run_recoil")
	for i in pellets:  # a shotgun throws several pellets in a fan, each a little different
		var pellet := _bullet_stats
		var fan := 0.0
		if STATS.pellets > 1 or STATS.damage_mult > 0.0:
			pellet = _bullet_stats.duplicate()
			if STATS.get("pellet_pierce", 0) > 0:
				pellet.pierce_enemies = STATS.pellet_pierce  # a shotgun blast goes through the first body into the next
			pellet.damage = ceili(pellet.damage * (1.0 + STATS.damage_mult))  # a crate boost
		if STATS.pellets > 1:
			fan = randf_range(-STATS.pellet_spread, STATS.pellet_spread)
			pellet.speed *= randf_range(1.0 - STATS.pellet_speed_var, 1.0)
		Bullet.spawn(get_parent(), position + muzzle, aim_dir, pellet, "bro_shot", BULLET_MASK, angle + fan)
	(_flash_2 if two_guns and _gun == 1 else flash).fire(muzzle, aim_dir)
	Sfx.play(self, STATS.shot_sound, -8.0)
	shake(STATS.shoot_shake)
	if not _clinging:
		var air: float = STATS.get("recoil_ground", 1.0) if is_on_floor() else STATS.recoil_air  # the kick throws him further when airborne
		_recoil = clampf(_recoil - aim_dir * STATS.recoil * air, -STATS.recoil_max * air, STATS.recoil_max * air)
		if STATS.recoil_hop > 0.0:
			velocity.y = minf(velocity.y, -STATS.recoil_hop)  # the kick lifts him a little
	if ammo == 0:
		_start_reload()


## Shell-count Bros (Sharif) have no magazines and no reload: one pool of shells.
func _uses_shells() -> bool:
	return STATS.shells_start > 0


## Minigun wind-up: while Shoot is held the barrels spin up for windup_time before the first
## bullet leaves; letting go spins them down over windup_decay (a short pause keeps most of the
## spin). Returns true once he is spun up. Bros with windup_time 0 are always ready.
func _windup_step(delta: float, held: bool) -> bool:
	var need: float = STATS.windup_time
	if need <= 0.0:
		_winding = false
		return true
	if held:
		_windup = minf(_windup + delta, need)
	else:
		_windup = maxf(_windup - delta * need / STATS.windup_decay, 0.0)
	_winding = held and _windup < need
	return _windup >= need


func _start_reload() -> void:
	if _uses_shells():
		return
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
func _explosive_is_c4() -> bool:
	return STATS.explosive == "c4"


## C4 Bro: tap the grenade button to throw a charge, hold it to set every planted charge off.
## The throw happens on release (a tap), so holding does not also throw one.
func _c4_input(delta: float) -> void:
	if Input.is_action_just_pressed("grenade"):
		_c4_hold = 0.0
		_c4_fired = false
	if _c4_hold < 0.0:
		return
	if Input.is_action_pressed("grenade"):
		_c4_hold += delta
		if not _c4_fired and _c4_hold >= GameData.C4.hold_time and C4Charge.planted(get_tree()) > 0:
			_c4_fired = true
			C4Charge.detonate_all(get_tree())
			shake(GameData.C4.detonate_shake)
	else:
		if not _c4_fired and not _knifing:
			_throw_grenade()
		_c4_hold = -1.0


func _throw_grenade() -> void:
	if Run.grenades <= 0 or _stagger > 0.0:
		return
	if STATS.explosive == "airstrike":
		_call_airstrike()
		return
	if STATS.explosive == "revolver":
		_start_revolver()
		return
	if STATS.explosive == "disco":
		_use_grenade()
		var disco_speed: Array = GameData.GRENADE.crouch_throw_speed if crouching else GameData.GRENADE.throw_speed
		DiscoGrenade.throw(get_parent(), position + Vector2(facing * 4.0, Block.SIZE / 2.0 - (STATS.hitbox_crouch[1] if crouching else STATS.hitbox[1]) + 8.0), Vector2(facing * disco_speed[0] + velocity.x * 0.5, -disco_speed[1]))
		return
	_use_grenade()
	var speed: Array = GameData.GRENADE.crouch_throw_speed if crouching else GameData.GRENADE.throw_speed
	var from := position + Vector2(facing * 4.0, Block.SIZE / 2.0 - (STATS.hitbox_crouch[1] if crouching else STATS.hitbox[1]) + 8.0)
	var vel := Vector2(facing * speed[0] + velocity.x * 0.5, -speed[1])
	if _explosive_is_c4():
		C4Charge.throw(get_parent(), from, vel)
	else:
		Grenade.throw(get_parent(), from, vel)


## Air strike (the Gunner): a laser marks a spot far in front of him and the bombs fall on it
## after a delay. If a wall is in the way the call fails (nothing is used).
func _call_airstrike() -> void:
	var dist: float = GameData.AIRSTRIKE.distance
	var from := global_position + Vector2(0, -6)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(facing * dist, 0), 1)
	if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		Sfx.play(self, "dry_fire", -6.0)
		return
	_use_grenade()
	AirStrike.call_in(get_parent(), AirStrike.ground_point(get_world_2d(), Vector2(global_position.x + facing * dist, global_position.y)), {"warn_radius": GameData.AIRSTRIKE.warn_radius})


## Revolver (Sharif's grenade button): he draws it and cannot move until the shot is done; he may
## still turn to face the other way before it goes off. One heavy round, straight ahead.
func _start_revolver() -> void:
	if _revolver >= 0.0 or _knifing or not is_on_floor():
		return
	_use_grenade()
	_revolver = 0.0
	_revolver_fired = false
	_charge = 0.0
	_pumping = false
	_pump_due = false


func _revolver_step(delta: float, dir: float) -> void:
	if _revolver < 0.0:
		return
	var stats: Dictionary = GameData.REVOLVER
	_revolver += delta
	if not _revolver_fired:
		if dir != 0.0:  # turning round is the only thing he can do
			facing = 1 if dir > 0 else -1
			sprite.flip_h = facing < 0
		var holding := Input.is_action_pressed("grenade")
		var on_shot_frame: bool = _revolver >= stats.shot_delay
		var animated: bool = sprite.sprite_frames.has_animation(sprite.animation) and String(sprite.animation).ends_with("revolver")
		if animated:
			on_shot_frame = sprite.frame >= stats.shot_frame  # the shot leaves on the drawn frame
		if holding:  # charging: he keeps the gun drawn on the frame before the shot until the button is let go
			_charge += delta
			_show_ring(_charge / stats.charge_time)
			if animated and sprite.frame >= stats.shot_frame - 1:
				sprite.pause()
				sprite.frame = stats.shot_frame - 1
				_revolver -= delta
			elif not animated:
				_revolver -= delta
			return
		if animated and not sprite.is_playing():
			sprite.play()
		_show_ring(-1.0)
		if on_shot_frame:
			_revolver_fired = true
			_fire_revolver(stats)
	if _revolver >= stats.lock_time:
		_revolver = -1.0
		_show_ring(-1.0)


func _show_ring(ratio: float) -> void:
	if _ring == null:
		_ring = ChargeRing.new()
		add_child(_ring)
	var offset: Array = GameData.REVOLVER.ring_offset
	_ring.position = Vector2(facing * offset[0], offset[1])
	if ratio >= 1.0 and _ring._ratio < 1.0:
		Sfx.play(self, "reload", -2.0)  # a click: fully charged
	_ring.show_charge(minf(ratio, 1.0) if ratio >= 0.0 else -1.0)


func _fire_revolver(stats: Dictionary) -> void:
	var held := clampf(_charge / stats.charge_time, 0.0, 1.0)
	var round_stats := {"speed": stats.speed, "lifetime": lerpf(stats.lifetime, stats.max_lifetime, held),
		"damage": ceili(lerpf(stats.damage, stats.max_damage, held) * (1.0 + STATS.damage_mult)), "size": stats.size,
		"behead": stats.behead, "pierce_enemies": roundi(lerpf(stats.pierce_enemies, stats.max_pierce_enemies, held)),
		"pierce_blocks": roundi(lerpf(stats.pierce_blocks, stats.max_pierce_blocks, held)),
		"sprite_scale": stats.sprite_scale, "sheet": stats.bullet_sheet}
	var muzzle := MuzzleFlash.gun_tip(sprite, Run.look(), facing)
	Bullet.spawn(get_parent(), position + muzzle, facing, round_stats, stats.bullet_anim, BULLET_MASK, 0.0)
	(_revolver_flash if _revolver_flash != null else flash).fire(muzzle, facing)
	Sfx.play(self, STATS.shot_sound, -2.0)
	shake(lerpf(stats.shake, stats.max_shake, held))
	_charge = 0.0


func _use_grenade() -> void:
	Run.grenades -= 1
	grenades_changed.emit(Run.grenades)
	Sfx.play(self, "grenade_throw", -4.0)


## Knife: stands up if crouched (and there is room), plays the knife animation; the hit
## itself happens on its first arm-up frame (_on_frame_changed -> _knife_strike).
func _start_knife() -> void:
	if _knifing or _stagger > 0.0:
		return
	if crouching:  # stabs from the crouch: stays low, same hit and reach as the standing knife
		_knifing = true
		_crouch_knife = 0.0
		if sprite.sprite_frames.has_animation("crouch_knife"):
			sprite.play("crouch_knife")  # optional art; the timing below does not depend on it
		Sfx.play(self, "knife_swing", -4.0, 0.08)
		return
	_knifing = true
	_flipping = 0.0
	sprite.play("knife")
	Sfx.play(self, "knife_swing", -4.0, 0.08)


## A crouched stab runs on a timer made from the standing knife animation (its hit frame and
## length), so it lands and ends exactly like the standing one.
func _crouch_knife_step(delta: float) -> void:
	if _crouch_knife < 0.0:
		return
	if not _knifing:  # cancelled (death, reset)
		_crouch_knife = -1.0
		return
	var speed: float = sprite.sprite_frames.get_animation_speed("knife")
	var hit_at := KNIFE_HIT_FRAME / speed
	var total: float = sprite.sprite_frames.get_frame_count("knife") / speed
	var before := _crouch_knife
	_crouch_knife += delta
	if before < hit_at and _crouch_knife >= hit_at:
		_knife_strike()
	if _crouch_knife >= total:
		_crouch_knife = -1.0
		_knifing = false
		_update_animation(_dir)


## The blade lands: the nearest enemy (or else body) within knife_range in front gets it;
## loose heads there burst.
func _knife_strike() -> void:
	var probe := RectangleShape2D.new()
	var behind: float = STATS.hitbox[0] / 2.0 + 6.0  # the blade also finds one standing inside / right against him
	probe.size = Vector2(STATS.knife_range + behind, STATS.hitbox[1])
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(facing * (STATS.knife_range - behind) / 2.0, Block.SIZE / 2.0 - STATS.hitbox[1] / 2.0))
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
	Sfx.play(self, STATS.melee_hit_sound, -2.0, 0.08)
	shake(2.0)
	if target.stab(facing, STATS.knife_boss_damage, STATS.knife_knockback, STATS.knife_hop, STATS.knife_blood, STATS.knife_hits, STATS.knife_stun, STATS.get("knife_hits_plain", 1)):
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
	if _uses_shells():
		if ammo >= STATS.shells_max:
			return
		ammo = mini(ammo + STATS.shells_per_kill, STATS.shells_max)
		ammo_changed.emit(ammo, 0, false)
		MagPopup.show_over(self, sprite_y - GameData.SPRITE_SIZES[Run.look()].y / 2.0, STATS.pickup_icon, "+%d" % STATS.shells_per_kill)
		return
	if spare_mags >= STATS.max_spare_mags:
		return
	spare_mags += 1
	ammo_changed.emit(ammo, spare_mags, _reload > 0.0)
	MagPopup.show_over(self, sprite_y - GameData.SPRITE_SIZES[Run.look()].y / 2.0, STATS.pickup_icon)
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
	_climb_side = 0
	_clinging = true
	_cling_time = 0.0
	_cling_side = side
	_recoil = 0.0  # the shot's momentum ends when he grabs the wall
	_hold_wall(side)
	facing = side
	sprite.flip_h = facing < 0
	velocity = Vector2.ZERO
	sprite.play("cling")
	Sfx.play(self, "knife_stab", -2.0, 0.08)
	shake(1.5)


## Remembers the wall block his hand is in: if it is shot away or blown up, he drops.
func _hold_wall(side: int) -> void:
	var x: float = global_position.x + side * (STATS.hitbox[0] / 2.0 + 2.0)
	var y: float = global_position.y - 6.0
	_hand_cell = Vector2i(floori(x / Block.SIZE), floori(y / Block.SIZE))
	_hand_block = Block.cells.get(_hand_cell)


func _release_cling() -> void:
	if not _clinging:
		return
	_clinging = false
	_hand_block = null
	_cling_cooldown = STATS.cling_cooldown
	sprite.play("jump")


## Hangs for cling_hold, then slides down, faster and faster. Jump kicks off the wall, pressing
## away or Crouch lets go; landing or losing the wall ends it too.
func _cling_process(delta: float, dir: float) -> void:
	_cling_time += delta
	if _explosive_is_c4():
		_c4_input(delta)
	elif STATS.explosive == "grenade" and Input.is_action_just_pressed("grenade") and Run.grenades > 0:
		_use_grenade()
		Grenade.blow(get_parent(), position + Vector2(_cling_side * 6.0, -6.0))  # no room to throw: it goes off in his hand
		return
	fire_cooldown -= delta  # he can still shoot - backwards, away from the wall
	shooting -= delta
	_burst_gap += delta
	_update_reload(delta)
	var spun_up := _windup_step(delta, Input.is_action_pressed("shoot") and _reload <= 0.0 and ammo > 0)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and _reload <= 0.0 and ammo > 0 and spun_up:
		_shoot(_cling_side)
	_invulnerable -= delta
	sprite.visible = _invulnerable <= 0.0 or fmod(_invulnerable, 0.12) < 0.06
	var away := dir != 0.0 and int(signf(dir)) == -_cling_side
	if Input.is_action_just_pressed("jump") and away:
		_kick_off_wall()
		return
	if Input.is_action_pressed("jump") and not away and _cling_time > 0.12:
		_climb_hop()  # one jump input climbs: hop up, knife in again
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
	elif _hand_block and Block.cells.get(_hand_cell) != _hand_block:
		_release_cling()  # the block under his hand is gone


## Jump while hanging (not pressing away): a smaller hop up the wall; at its top he stabs in again.
func _climb_hop() -> void:
	var side := _cling_side
	_release_cling()
	_cling_cooldown = STATS.cling_hop_cooldown  # no grabbing the wall again right away
	velocity = Vector2(side * 30.0, STATS.jump_velocity * STATS.cling_climb_mult)
	_climb_side = side
	_climb_time = STATS.cling_hop_cooldown + 0.8
	sprite.play("flip")  # the somersault, then he can grab the wall again
	_flipping = STATS.flip_time
	Sfx.play(self, "jump", -4.0)


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
	sprite.speed_scale = 1.0
	if _knifing or _clinging:
		return
	if _revolver >= 0.0:
		var draw := "crouch_revolver" if crouching and sprite.sprite_frames.has_animation("crouch_revolver") else "revolver"
		if sprite.sprite_frames.has_animation(draw) and sprite.animation != draw:
			sprite.play(draw)
		return
	if _flipping > 0.0 and not is_on_floor():
		return  # the somersault plays out
	if _rolling and sprite.animation == "roll" and is_on_floor() and dir != 0.0 and shooting <= 0.0 and not Input.is_action_pressed("shoot"):
		return  # the landing roll plays out (stopping, shooting or jumping cuts it short)
	_rolling = false
	if _roll_box:
		_set_roll_box(false)
	if _pumping and sprite.animation == _pump_name(dir) and is_on_floor():
		return  # the pump plays out (standing up, running or stopping cuts it short)
	if _kicking and sprite.animation == "run_recoil" and is_on_floor() and dir != 0.0 and not crouching:
		return  # the run kick plays out once
	_kicking = false
	_pumping = false
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif crouching:
		anim = "crouch_walk" if dir != 0 else ("crouch_shoot" if shooting > 0.0 else "crouch")
	elif dir != 0:
		anim = "run_shoot" if shooting > 0.0 else "run"
		if _sprint != 0:
			sprite.speed_scale = 1.6  # legs keep up with the faster pace
		if _kick_due and shooting > 0.0:
			_kick_due = false
			_kicking = true
			anim = "run_recoil"
	elif shooting > 0.0:
		anim = "shoot"
	if _reload > 0.0 and is_on_floor() and not crouching and sprite.sprite_frames.has_animation("reload"):
		anim = "reload"  # the gun bobs while the belt is swapped (optional art)
		var frames := sprite.sprite_frames
		if dir != 0.0 and frames.has_animation("run_reload"):
			anim = "run_reload"  # the same reload with the legs stepping
		if sprite.animation != anim and (sprite.animation == "reload" or sprite.animation == "run_reload"):
			var progress := float(sprite.frame) / frames.get_frame_count(sprite.animation)  # keep the place in the reload
			sprite.play(anim)
			sprite.frame = int(progress * frames.get_frame_count(anim))
		sprite.speed_scale = (frames.get_frame_count(anim) / frames.get_animation_speed(anim)) / STATS.reload_time  # stretched to last exactly reload_time
	if _winding and is_on_floor():  # barrels spinning, nothing fired yet (optional art)
		var wind := "crouch_windup" if crouching else ("run_windup" if dir != 0.0 else "windup")
		if sprite.sprite_frames.has_animation(wind):
			anim = wind
	if _pump_due and shooting <= 0.0 and is_on_floor():  # cycle the pump after the shot
		var pump := _pump_name(dir)
		_pump_due = false
		if sprite.sprite_frames.has_animation(pump):
			_pumping = true
			anim = pump
	if sprite.animation != anim or anim.ends_with("pump") or anim == "run_recoil":
		sprite.play(anim)


## The pump animation for what he is doing: crouch_pump (crouched, walking or not), run_pump, pump.
func _pump_name(dir: float) -> String:
	return "crouch_pump" if crouching else ("run_pump" if dir != 0.0 else "pump")


## Hold Crouch on the ground to shrink to one block. Letting go only stands up when there is
## room above; otherwise he stays crouched under the low ceiling.
func _update_stance() -> void:
	var want := (Input.is_action_pressed("crouch") and is_on_floor()) or _low_gap_ahead()  # the gap squeeze works in mid-jump too
	if want == crouching:
		return
	if want or not _ceiling_above():
		_set_stance(want)


## Walking into a gap too low to stand in but high enough to crouch in: crouch by himself.
func _low_gap_ahead() -> bool:
	if not STATS.auto_crouch or _dir == 0.0 or _knifing:
		return false
	var shift := Vector2(signf(_dir) * 6.0, 0)
	var stand := _box_blocked(STATS.hitbox, shift)
	return stand and not _box_blocked(STATS.hitbox_crouch, shift)


## A one-block gap in the wall on `side` (block below, empty cell, block above) whose floor he can jump up to:
## returns the y of that floor (NAN when there is none). He crouches and goes in instead of hanging on the wall.
func _squeeze_floor(side: int) -> float:
	var cx := floori((global_position.x + side * (STATS.hitbox[0] / 2.0 + 2.0)) / Block.SIZE)
	var feet: float = global_position.y + Block.SIZE / 2.0
	for r in range(floori((feet - STATS.hitbox[1]) / Block.SIZE) - 1, floori(feet / Block.SIZE) + 1):
		var floor_y: float = (r + 1) * Block.SIZE
		if floor_y > feet + Block.SIZE or floor_y < feet - Block.SIZE * 3.0:  # its floor is at most 3 blocks above his feet
			continue
		if not Block.cells.has(Vector2i(cx, r)) and Block.cells.has(Vector2i(cx, r - 1)) and Block.cells.has(Vector2i(cx, r + 1)):
			return floor_y
	return NAN


## Jump pressed against a one-block step under a low ceiling (too low to jump onto it): he climbs up onto it,
## crouched if the room above the step is low too. Returns whether he did.
func _step_up(side: int) -> bool:
	if _wall_block_side() != side or not _box_blocked(STATS.hitbox, Vector2(0.0, -Block.SIZE - 2.0)):
		return false
	var cx := floori((global_position.x + side * (STATS.hitbox[0] / 2.0 + 2.0)) / Block.SIZE)
	var row := floori((global_position.y + Block.SIZE / 2.0 - 1.0) / Block.SIZE)
	if not Block.cells.has(Vector2i(cx, row)) or Block.cells.has(Vector2i(cx, row - 1)):
		return false
	var up := Vector2(side * 4.0, -Block.SIZE - 1.0)
	if _box_blocked(STATS.hitbox_crouch, up):
		return false
	_mantle = MANTLE_TIME
	_mantle_from = position
	_mantle_to = position + up
	velocity = Vector2.ZERO
	_set_stance(true)  # crouched while he climbs; the stance clears itself afterwards if there is room
	return true


## Rises first, then edges over onto the step, in the crouch pose.
func _mantle_step(delta: float) -> void:
	_mantle -= delta
	var t := 1.0 - maxf(_mantle, 0.0) / MANTLE_TIME
	position = Vector2(lerpf(_mantle_from.x, _mantle_to.x, clampf((t - 0.5) * 2.0, 0.0, 1.0)), lerpf(_mantle_from.y, _mantle_to.y, clampf(t * 1.4, 0.0, 1.0)))
	velocity = Vector2.ZERO
	if sprite.sprite_frames.has_animation("crouch") and sprite.animation != "crouch":
		sprite.play("crouch")


## Pressed against the wall with his feet level with the gap: he hops up onto its floor, crouched, ready to crawl in.
func _squeeze_in(side: int) -> bool:
	var floor_y := _squeeze_floor(side)
	var feet: float = global_position.y + Block.SIZE / 2.0
	if is_nan(floor_y) or feet < floor_y - 22.0 or feet > floor_y + 8.0:
		return false
	position.y += floor_y - 1.0 - feet  # a pixel above it, so the step does not catch his side
	velocity.y = 0.0
	_set_stance(true)
	return true


## Would a body of `size` (feet on the bottom of his tile) shifted by `shift` overlap a block?
func _box_blocked(size: Array, shift: Vector2) -> bool:
	var probe := RectangleShape2D.new()
	probe.size = Vector2(size[0] - 2, size[1] - 2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + shift + Vector2(0, Block.SIZE / 2.0 - size[1] / 2.0 - 1.0))
	query.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## While the roll plays the body is one block (the crouch box): he can roll through a one-block gap. Afterwards
## the box goes back - or he stays crouched if something solid is above him.
func _set_roll_box(on: bool) -> void:
	_roll_box = on
	if on:
		var size: Array = STATS.hitbox_crouch
		var box: RectangleShape2D = $Collision.shape
		box.size = Vector2(size[0], size[1])
		$Collision.position.y = Block.SIZE / 2.0 - size[1] / 2.0
	else:
		_set_stance(crouching or _ceiling_above())


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


## The reload animation and its run_reload twin (more frames, legs stepping) show the same moments:
## `frame` of reload is `frame * k` of run_reload, where k is how many times longer run_reload is.
func _reload_k() -> int:
	if sprite.animation != "run_reload":
		return 1
	var frames := sprite.sprite_frames
	return maxi(1, frames.get_frame_count("run_reload") / frames.get_frame_count("reload"))


## Is the reload (either version) on the first frame of reload frame `frame`?
func _reload_frame(anim: String, frame: int) -> bool:
	return (sprite.animation == anim or sprite.animation == "run_reload") and sprite.frame == frame * _reload_k()


## Which reload frame the running or standing reload is at (-1 when not reloading).
func _reload_span() -> int:
	if sprite.animation != "reload" and sprite.animation != "run_reload":
		return -1
	return sprite.frame / _reload_k()


func _on_frame_changed() -> void:
	if sprite.animation == "run" and sprite.frame % 2 == 0:
		Sfx.play(self, "footstep", -14.0, 0.15)
	elif _reload_frame("reload", 3) and STATS.get("drop_mag", false):
		MagDrop.drop(get_parent(), position + sprite.position + Vector2(facing * -0.5, 10.0), facing)  # the empty one falls
	elif _reload_frame("reload", 1) and STATS.get("drop_guns", false):
		for spot in [Vector2(9.5, 4.0), Vector2(-3.5, 6.0)]:  # front and rear SMG, from the frame centre
			GunDrop.drop(get_parent(), position + sprite.position + Vector2(spot.x * facing, spot.y), facing)
	elif STATS.get("steam_reload", false) and _reload_span() >= 2 and _reload_span() <= 13:
		var tip := MuzzleFlash.gun_tip(sprite, Run.look(), facing)  # the raygun cools down while held up
		SteamPuff.emit(get_parent(), position + tip, sprite.frame == 2)
	elif sprite.animation == "knife" and sprite.frame == KNIFE_HIT_FRAME and not _clinging:
		_knife_strike()
	elif sprite.animation.ends_with("pump") and sprite.frame == 1 and STATS.eject_shells:
		var tip := MuzzleFlash.gun_tip(sprite, Run.look(), facing)  # a spent shell leaves the gun as it is pumped
		ShellCasing.eject(get_parent(), position + tip - Vector2(facing * 7.0, 1.0), facing)


func _on_animation_finished() -> void:
	if sprite.animation == "roll":
		_rolling = false
		if _roll_box:
			_set_roll_box(false)
		_update_animation(_dir)
	if sprite.animation == "run_recoil":
		_kicking = false
		_update_animation(_dir)
	if sprite.animation.ends_with("pump"):
		_pumping = false
		_update_animation(_dir)
	if sprite.animation == "knife":
		_knifing = false
		_update_animation(_dir)
