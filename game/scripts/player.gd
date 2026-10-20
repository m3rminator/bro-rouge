extends CharacterBody2D
## The Bro: run, jump, hold to shoot. Enemy bullets take hit points; at 0 he dies
## and the level restarts. Numbers: design/entities/bro.yaml (GameData.BRO).

signal hp_changed(hp: int, max_hp: int)

const STATS := GameData.BRO
const MUZZLE: Vector2 = GameData.ANCHORS["bro"]["muzzle"]
const BULLET_MASK := 1 | 4  # world + enemies

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var flash: MuzzleFlash = $Flash

var hp: int = STATS.max_hp
var dead := false
var facing := 1
var fire_cooldown := 0.0
var shooting := 0.0
var _invulnerable := 0.0


func _ready() -> void:
	add_to_group("player")
	z_index = 2
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(STATS.hitbox[0], STATS.hitbox[1])
	$Collision.position.y = 8 - STATS.hitbox[1] / 2.0  # feet on the bottom of the 16 px frame
	sprite.frame_changed.connect(_on_frame_changed)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		move_and_slide()
		return

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * STATS.speed
	if dir != 0:
		facing = 1 if dir > 0 else -1
		sprite.flip_h = facing < 0

	if Input.is_action_just_pressed("jump") and is_on_floor():
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
	if dead or _invulnerable > 0.0:
		return
	hp = maxi(hp - damage, 0)
	hp_changed.emit(hp, STATS.max_hp)
	if hp == 0:
		_die(direction)
		return
	_invulnerable = STATS.invulnerable_time
	Sfx.play(self, "player_hurt")


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
	tween.tween_property(sprite, "position:y", 3.0, 0.35)
	await get_tree().create_timer(STATS.respawn_delay).timeout
	get_tree().reload_current_scene()


func _shoot() -> void:
	fire_cooldown = STATS.fire_interval
	shooting = 0.15
	var muzzle := Vector2(MUZZLE.x * facing, MUZZLE.y)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.BULLET, "bullet", BULLET_MASK)
	flash.fire(muzzle, facing)
	Sfx.play(self, "shoot", -8.0)


func _update_animation(dir: float) -> void:
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif dir != 0:
		anim = "run"
	elif shooting > 0.0:
		anim = "shoot"
	if sprite.animation != anim:
		sprite.play(anim)


func _on_frame_changed() -> void:
	if sprite.animation == "run" and sprite.frame % 2 == 0:
		Sfx.play(self, "footstep", -14.0, 0.15)
