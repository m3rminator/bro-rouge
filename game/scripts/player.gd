extends CharacterBody2D
## The Bro: run, jump, crouch, hold to shoot. Enemy bullets take one heart, explosions several (and
## knock him back). At 0 he dies and emits `died` — main.gd decides what happens next (run
## lives, design/run.yaml). Numbers: design/entities/bro.yaml (GameData.BRO).

signal hp_changed(hp: int, max_hp: int)
signal died

const STATS := GameData.BRO
const MUZZLE: Vector2 = GameData.ANCHORS["bro"]["muzzle"]
const MUZZLE_CROUCH: Vector2 = GameData.ANCHORS["bro"]["muzzle_crouch"]
const SPRITE_Y := -4.0  # the 24 px frame is centered on the node; this puts the feet on the tile bottom (+8)
const BULLET_MASK := 1 | 4  # world (blocks, barrels) + enemies

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var flash: MuzzleFlash = $Flash
@onready var camera: Camera2D = $Camera

var hp: int = STATS.max_hp
var dead := false
var frozen := false  # level clear: no control, cannot be hurt
var facing := 1
var crouching := false
var fire_cooldown := 0.0
var shooting := 0.0
var _invulnerable := 0.0
var _stagger := 0.0  # knocked back by a blast: input ignored
var _shake := 0.0


func _ready() -> void:
	add_to_group("player")
	z_index = 2
	sprite.position.y = SPRITE_Y
	_set_stance(false)
	sprite.frame_changed.connect(_on_frame_changed)


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
	_update_stance()
	if _stagger > 0.0:
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	else:
		velocity.x = dir * (STATS.speed_crouch if crouching else STATS.speed)
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

	fire_cooldown -= delta
	shooting -= delta
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()

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


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Level clear: stop moving and shooting, can't be hurt.
func freeze() -> void:
	frozen = true
	sprite.visible = true


func _die(direction: int) -> void:
	dead = true
	sprite.visible = true
	collision_layer = 0
	Sfx.play(self, "player_death")
	sprite.play("hurt")
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 90.0, -160.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "rotation", PI / 2 * push, 0.35)
	tween.tween_property(sprite, "position:y", SPRITE_Y + 3.0, 0.35)
	died.emit()


func _shoot() -> void:
	fire_cooldown = STATS.fire_interval
	shooting = 0.15
	var tip := MUZZLE_CROUCH if crouching else MUZZLE
	var muzzle := Vector2(tip.x * facing, tip.y + SPRITE_Y)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.BULLET, "bro_shot", BULLET_MASK)
	flash.fire(muzzle, facing)
	Sfx.play(self, "shoot", -8.0)


func _update_animation(dir: float) -> void:
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif crouching:
		anim = "crouch_walk" if dir != 0 else ("crouch_shoot" if shooting > 0.0 else "crouch")
	elif dir != 0:
		anim = "run"
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
	$Collision.position.y = 8 - size[1] / 2.0  # feet always on the bottom of the start tile


## Is there a block where the standing body would be? (Probed slightly smaller than the
## standing box so the floor under his feet does not count.)
func _ceiling_above() -> bool:
	var probe := RectangleShape2D.new()
	probe.size = Vector2(STATS.hitbox[0] - 2, STATS.hitbox[1] - 2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(0, 8 - STATS.hitbox[1] / 2.0 - 1.0))
	query.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_frame_changed() -> void:
	if sprite.animation == "run" and sprite.frame % 2 == 0:
		Sfx.play(self, "footstep", -14.0, 0.15)
